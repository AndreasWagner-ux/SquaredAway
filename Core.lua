-- Squared Away: core
-- Icons that are always shown out of combat:
--   food   Well Fed, with countdown
--   kits   armor kits on chest, legs, hands, feet (and whether a better one fits)
--   boost  agility elixir or scroll, with countdown
--   pet    hunter pet summoned, alive and happy
-- Green check = done, yellow question mark = could be better, red cross = missing.
-- Hover an icon for the suggestion that fits your level. Hidden in combat.
-- Never buys or uses anything.

local ADDON, ns = ...
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

-- ItemData.lua (generated from ForeverDB) says what each known item is.
-- Build the per-kind ID lists from it.
ns.ITEMS = ns.ITEMS or {}
local SEED_KEY = { food = "SEED_FOOD", kit = "SEED_KITS", boost = "SEED_BOOSTS", scroll = "SEED_SCROLLS" }
for _, key in pairs(SEED_KEY) do ns[key] = {} end
ns.KIT_MIN_ILVL = {}
for _, st in ipairs(ns.SCROLL_STATS) do st.label = L[st.label] end
for id, info in pairs(ns.ITEMS) do
    local key = SEED_KEY[info.kind]
    if key then table.insert(ns[key], id) end
    if info.minIlvl and info.minIlvl > 0 then ns.KIT_MIN_ILVL[id] = info.minIlvl end
end
local CREDIT = L["Data from ForeverDB.net (https://foreverdb.net)"]

local PREFIX = "|cff7fd4ffSquared Away|r: "
local ICON_SIZE = 36
local GAP = 6

local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconFn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemSpellFn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemInfoInstantFn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WARN  = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local db
local pending = {}
local QueueUpdate -- set further down
local isHunter = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

-- Spell name in the client language.
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

----------------------------------------------------------------------
-- Tooltip scanning
----------------------------------------------------------------------

local scanTip = CreateFrame("GameTooltip", "SquaredAwayScanTip", nil, "GameTooltipTemplate")

local function ReadScanTip()
    local n = scanTip:NumLines()
    if not n or n == 0 then return nil end
    local parts = {}
    for i = 1, n do
        local line = _G["SquaredAwayScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text then parts[#parts + 1] = text end
    end
    scanTip:Hide()
    return table.concat(parts, "\n"):lower()
end

local function TooltipText(id)
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink("item:" .. id)
    return ReadScanTip()
end

local function SlotTooltipText(slot)
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slot)
    return ReadScanTip()
end

----------------------------------------------------------------------
-- Buffs
----------------------------------------------------------------------

-- Calls fn(name, icon, spellId) for each buff; stops and returns
-- true, expirationTime, name when fn returns true.
local function FindBuff(fn)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if fn(aura.name, aura.icon, aura.spellId) then return true, aura.expirationTime, aura.name end
        end
    else
        for i = 1, 40 do
            local name, icon, _, _, _, expirationTime, _, _, _, spellId = UnitBuff("player", i)
            if not name then break end
            if fn(name, icon, spellId) then return true, expirationTime, name end
        end
    end
    return false
end

local function IsWellFed()
    if not ns.wellFedLocal then
        ns.wellFedLocal = true
        for _, id in ipairs(ns.WELL_FED_SPELLS or {}) do
            local n = SpellName(id)
            if n then ns.WELL_FED_NAMES[n] = true end
        end
    end
    return FindBuff(function(name, icon)
        if name and ns.WELL_FED_NAMES[name] then return true end
        if icon then
            if ns.WELL_FED_ICONS[icon] then return true end
            if type(icon) == "string" and ns.WELL_FED_ICONS[icon:lower()] then return true end
        end
        return false
    end)
end

----------------------------------------------------------------------
-- Learning items from the game
----------------------------------------------------------------------

-- Decides whether an item is Well Fed food, an armor kit, an agility
-- elixir/scroll, or none of these, and remembers the answer.
local function Classify(id)
    id = tonumber(id)
    if not id or db.items[id] ~= nil then return end

    local name, _, _, ilvl, minLevel = GetItemInfoFn(id)
    if not name then
        pending[id] = true
        if RequestLoad then RequestLoad(id) end
        return
    end

    local text = TooltipText(id)
    if not text then
        pending[id] = true
        return
    end
    pending[id] = nil

    local lname = name:lower()
    local info = { lvl = minLevel or 0, ilvl = ilvl or 0 }

    -- arrows and bullets: known by their item class, no tooltip words needed
    local _, _, _, _, _, classID, subID = GetItemInfoInstantFn(id)
    if classID == 6 and (subID == 2 or subID == 3) then
        info.kind, info.sub = "ammo", subID == 2 and "arrow" or "bullet"
        db.items[id] = info
        return
    end

    if text:find("well fed", 1, true) or text:find("%f[%a]satt%f[%A]") then
        info.kind = "food"
    elseif lname:find("armor kit", 1, true) or lname:find("rüstungsset", 1, true)
        or text:find("chest, legs, hands or feet", 1, true) then
        info.kind = "kit"
    elseif text:find("agility", 1, true) or text:find("beweglichkeit", 1, true) then
        if lname:find("elixir", 1, true) or lname:find("elixier", 1, true) then
            info.kind, info.sub = "boost", "elixir"
        elseif lname:find("scroll", 1, true) or lname:find("rolle", 1, true) then
            info.kind, info.sub = "boost", "scroll"
        end
    elseif (lname:find("scroll", 1, true) or lname:find("rolle", 1, true))
        and not text:find("%", 1, true)            -- skip % group scrolls
        and not text:find("summon", 1, true) and not text:find("beschwört", 1, true) then
        -- other stat scrolls: stamina, strength, protection (armor), intellect
        for _, s in ipairs(ns.SCROLL_STATS) do
            for _, word in ipairs(s.words) do
                if text:find(word, 1, true) then
                    info.kind, info.stat = "scroll", s.key
                    break
                end
            end
            if info.kind then break end
        end
    end

    db.items[id] = info.kind and info or false
end

local function ClassifyLink(link)
    if not link then return end
    local id = link:match("item:(%d+)")
    if id then Classify(id) end
end

local function ScanBags()
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    for bag = 0, 4 do
        for slot = 1, (numSlots(bag) or 0) do
            local id = itemID(bag, slot)
            if id then Classify(id) end
        end
    end
end

local function ScanMerchant()
    for i = 1, (GetMerchantNumItems() or 0) do
        ClassifyLink(GetMerchantItemLink(i))
    end
end

-- How useful a Well Fed food is for a hunter, from its tooltip:
-- 3 agility or attack power, 2 stamina or crit, 1 intellect or armor,
-- 0 everything else (strength, spirit, spell power, healing, fishing...).
-- Foods scoring 0 are never suggested.
local FOOD_STATS = {
    { 3, { "agility", "beweglichkeit", "attack power", "angriffskraft" } },
    { 2, { "stamina", "ausdauer", "critical", "kritische" } },
    { 1, { "intellect", "intelligenz", "armor", "rüstung" } },
}

local function FoodScore(id)
    local info = db.items[id]
    if not info then return 0 end
    if info.score then return info.score end
    local text = TooltipText(id)
    if not text then return 0 end
    -- only look at the part after "well fed" / "satt", where the buff is described
    local buff = text:match("well fed(.*)") or text:match("%f[%a]satt%f[%A](.*)") or text
    local score = 0
    for _, group in ipairs(FOOD_STATS) do
        for _, word in ipairs(group[2]) do
            if buff:find(word, 1, true) then score = math.max(score, group[1]) end
        end
    end
    info.score = score
    return score
end

-- Spell power kits (Mystic) are no use to a hunter.
local function KitUseful(id)
    local info = db.items[id]
    if not info then return false end
    if info.caster == nil then
        local text = TooltipText(id)
        if not text then return true end
        info.caster = (text:find("spell power", 1, true) or text:find("spell damage", 1, true)
            or text:find("zaubermacht", 1, true) or text:find("zauberschaden", 1, true)) and true or false
    end
    return not (isHunter and info.caster)
end

-- Best known item of a kind (and optional sub kind) usable at your level.
local function Best(kind, sub)
    local level = UnitLevel("player")
    local bestId, bestLvl, bestScore, bestIlvl
    for id, info in pairs(db.items) do
        if info and info.kind == kind and (not sub or info.sub == sub) then
            local _, _, _, ilvl, minLevel = GetItemInfoFn(id)
            minLevel = minLevel or info.lvl or 0
            ilvl = ilvl or info.ilvl or 0
            local score = 1
            if kind == "food" then score = FoodScore(id) end
            if kind == "kit" and not KitUseful(id) then score = 0 end
            if minLevel <= level and score > 0 then
                if not bestId or minLevel > bestLvl
                    or (minLevel == bestLvl and (score > bestScore
                    or (score == bestScore and ilvl > bestIlvl))) then
                    bestId, bestLvl, bestScore, bestIlvl = id, minLevel, score, ilvl
                end
            end
        end
    end
    return bestId
end

local function ItemText(id)
    local name, link = GetItemInfoFn(id)
    return link or name or (L["item"] .. " " .. id)
end

----------------------------------------------------------------------
-- Armor kits
----------------------------------------------------------------------

-- Armor a kit adds, read from its tooltip ("... feet by 16." / "... um 16").
local function KitArmor(id)
    local info = db.items[id]
    if not info then return nil end
    if info.armor then return info.armor end
    local text = TooltipText(id)
    if not text then return nil end
    local armor = tonumber(text:match("feet by (%d+)") or text:match("füße.-um (%d+)")
        or text:match("by (%d+)") or text:match("um (%d+)"))
    info.armor = armor
    return armor
end

-- Armor of the kit on an equipped item, read from the green line
-- "Reinforced (+16 Armor)" / "Verstärkt (+16 Rüstung)". nil if unknown.
local function EquippedKitArmor(slot)
    local text = SlotTooltipText(slot)
    if not text then return nil end
    return tonumber(text:match("%(%+(%d+) armor%)") or text:match("%(%+(%d+) rüstung%)"))
end

-- Minimum item level a kit can be put on (0 = any). Known values come from
-- Data.lua, others are read from the tooltip.
local function KitMinIlvl(id)
    if ns.KIT_MIN_ILVL[id] then return ns.KIT_MIN_ILVL[id] end
    local info = db.items[id]
    if not info then return 0 end
    if info.minIlvl == nil then
        local text = TooltipText(id)
        if not text then return 0 end
        info.minIlvl = tonumber(text:match("items? of level (%d+)") or text:match("items? level (%d+)")
            or text:match("item level (%d+)") or text:match("gegenstände.-stufe (%d+)")) or 0
    end
    return info.minIlvl
end

-- Best kit you can use on an item of the given item level.
local function BestKitFor(itemLevel)
    local level = UnitLevel("player")
    local bestId, bestArmor, bestLvl
    for id, info in pairs(db.items) do
        if info and info.kind == "kit" and KitUseful(id) then
            local _, _, _, _, minLevel = GetItemInfoFn(id)
            minLevel = minLevel or info.lvl or 0
            local armor = KitArmor(id) or 0
            if minLevel <= level and KitMinIlvl(id) <= (itemLevel or 0) then
                if not bestId or armor > bestArmor or (armor == bestArmor and minLevel > bestLvl) then
                    bestId, bestArmor, bestLvl = id, armor, minLevel
                end
            end
        end
    end
    return bestId, bestArmor
end

-- Returns three things: slot labels with no kit, slot labels with a weaker
-- kit than the best one that fits that item, and the best kit per slot label.
local function KitStatus()
    local missing, weaker, perSlot = {}, {}, {}
    for _, s in ipairs(ns.KIT_SLOTS) do
        local link = GetInventoryItemLink("player", s.slot)
        if link then
            local _, _, _, itemLevel = GetItemInfoFn(link)
            local best, bestArmor = BestKitFor(itemLevel)
            perSlot[s.label] = best
            local enchant = tonumber(link:match("item:%-?%d+:(%-?%d*)")) or 0
            if enchant == 0 then
                missing[#missing + 1] = s.label
            elseif best and bestArmor and bestArmor > 0 then
                local current = EquippedKitArmor(s.slot)
                if current and current < bestArmor then
                    weaker[#weaker + 1] = s.label
                    perSlot[s.label .. "#current"] = current
                end
            end
        end
    end
    return missing, weaker, perSlot
end

----------------------------------------------------------------------
-- Elixirs and scrolls
----------------------------------------------------------------------

-- Is an agility elixir or scroll active? Matches the buff against the
-- spell names of all known boost items.
-- Buff names and spell IDs of all known items of a kind (and stat).
-- info.spell is the buff spell ID (from ItemData or the game), info.spellName
-- its name in the client language.
local function BuffSets(kind, stat)
    local names, ids = {}, {}
    for id, info in pairs(db.items) do
        if info and info.kind == kind and (not stat or info.stat == stat) then
            if type(info.spell) == "string" then -- saved by an older version
                info.spellName, info.spell = info.spell, nil
            end
            if not info.spellName or not info.spell then
                local n, sid = GetItemSpellFn(id)
                info.spellName = info.spellName or n
                info.spell = info.spell or tonumber(sid)
            end
            if info.spell then ids[info.spell] = true end
            if info.spellName then names[info.spellName] = true end
        end
    end
    return names, ids
end

local function ActiveBoost()
    local names, ids = BuffSets("boost")
    return FindBuff(function(name, _, spellId)
        return (spellId and ids[spellId]) or (name and names[name])
    end)
end

-- Agility an elixir or scroll gives, read from its tooltip.
local function BoostAmount(id)
    local info = db.items[id]
    if not info then return 0 end
    if info.amount then return info.amount end
    local text = TooltipText(id)
    if not text then return 0 end
    local amount = tonumber(text:match("agility by (%d+)") or text:match("agility.-by (%d+)")
        or text:match("beweglichkeit um (%d+)") or text:match("beweglichkeit.-um (%d+)")
        or text:match("(%d+) agility") or text:match("(%d+) beweglichkeit"))
    info.amount = amount
    return amount or 0
end

-- Elixir and scroll of the same stat do not stack, so suggest only one:
-- the one you already carry, otherwise the stronger one.
local function BestBoost()
    local level = UnitLevel("player")
    local bestOwned, bestOwnedAmt, bestAny, bestAnyAmt
    for id, info in pairs(db.items) do
        if info and info.kind == "boost" then
            local _, _, _, _, minLevel = GetItemInfoFn(id)
            if (minLevel or info.lvl or 0) <= level then
                local amount = BoostAmount(id)
                if not bestAny or amount > bestAnyAmt then bestAny, bestAnyAmt = id, amount end
                if (GetItemCountFn(id) or 0) > 0 and (not bestOwned or amount > bestOwnedAmt) then
                    bestOwned, bestOwnedAmt = id, amount
                end
            end
        end
    end
    return bestOwned or bestAny
end

----------------------------------------------------------------------
-- Other stat scrolls (stamina, strength, protection, intellect)
-- Agility scrolls stay with the elixirs above, because they block each other.
----------------------------------------------------------------------

-- Amount a stat scroll gives, read from its tooltip ("... by 16" / "... um 16").
local function ScrollAmount(id)
    local info = db.items[id]
    if not info then return 0 end
    if info.amount then return info.amount end
    local text = TooltipText(id)
    if not text then return 0 end
    local amount = tonumber(text:match("by (%d+)") or text:match("um (%d+)"))
    info.amount = amount
    return amount or 0
end

-- Best scroll of a stat for your level: the strongest you carry, otherwise
-- the strongest known.
local function BestScroll(stat)
    local level = UnitLevel("player")
    local bestOwned, bestOwnedAmt, bestAny, bestAnyAmt
    for id, info in pairs(db.items) do
        if info and info.kind == "scroll" and info.stat == stat then
            local _, _, _, _, minLevel = GetItemInfoFn(id)
            if (minLevel or info.lvl or 0) <= level then
                local amount = ScrollAmount(id)
                if not bestAny or amount > bestAnyAmt then bestAny, bestAnyAmt = id, amount end
                if (GetItemCountFn(id) or 0) > 0 and (not bestOwned or amount > bestOwnedAmt) then
                    bestOwned, bestOwnedAmt = id, amount
                end
            end
        end
    end
    return bestOwned or bestAny, bestOwned ~= nil
end

-- Is a scroll of this stat active? Returns true, expirationTime.
local function ActiveScroll(stat)
    local names, ids = BuffSets("scroll", stat)
    return FindBuff(function(name, _, spellId)
        return (spellId and ids[spellId]) or (name and names[name])
    end)
end

-- Is the stat already covered by a class buff (Fortitude, Arcane Intellect)?
-- Then a scroll would not stack. Returns the buff name.
local function CoveredScroll(s)
    if not s.coveredBy then return nil end
    local names = {}
    for _, id in ipairs(s.coveredBy) do
        local n = SpellName(id)
        if n then names[n] = true end
    end
    local found, _, name = FindBuff(function(n) return n and names[n] end)
    return found and name or nil
end

-- One entry per scroll stat you could use at your level:
-- { s = stat, state = "active" | "covered" | "missing", expires, buff, best, owned }
local function ScrollStatus()
    local list, active = {}, 0
    for _, s in ipairs(ns.SCROLL_STATS) do
        local best, owned = BestScroll(s.key)
        local isActive, expires = ActiveScroll(s.key)
        local covered = CoveredScroll(s)
        if best or isActive or covered then
            local e = { s = s, best = best, owned = owned }
            if isActive then
                e.state, e.expires = "active", expires
            elseif covered then
                e.state, e.buff = "covered", covered
            else
                e.state = "missing"
            end
            if e.state ~= "missing" then active = active + 1 end
            list[#list + 1] = e
        end
    end
    return list, active
end

----------------------------------------------------------------------
-- Ammo: count, quiver fill, best ammo at a vendor, one-click restock
----------------------------------------------------------------------

local AMMO_SLOT = INVSLOT_AMMO or 0
local RANGED_SLOT = INVSLOT_RANGED or 18
local merchantOpen = false
local ammoOffer -- best ammo the open vendor sells, see ScanMerchantAmmo
local buying = false

-- "arrow" or "bullet" for the equipped bow, crossbow or gun; nil otherwise.
local function WeaponAmmoType()
    local id = GetInventoryItemID("player", RANGED_SLOT)
    if not id then return nil end
    local _, _, _, _, _, classID, subID = GetItemInfoInstantFn(id)
    if classID ~= 2 then return nil end
    if subID == 2 or subID == 18 then return "arrow" end -- bow, crossbow
    if subID == 3 then return "bullet" end               -- gun
end

local function AmmoType(id)
    local info = db.items[id]
    if info and info.kind == "ammo" then return info.sub end
    local _, _, _, _, _, classID, subID = GetItemInfoInstantFn(id)
    if classID == 6 then
        if subID == 2 then return "arrow" elseif subID == 3 then return "bullet" end
    end
end

-- Damage per second from the tooltip, using the game's own text
-- ("Adds %s damage per second"), so it works in every client language.
local function AmmoDPS(id)
    local info = db.items[id]
    if info and info.dps then return info.dps end
    local template = AMMO_DAMAGE_TEMPLATE
    if not template then return 0 end
    local pattern = template:lower():gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%[%d%.]*[sfd]", "([%%d%%.,]+)")
    local text = TooltipText(id)
    local num = text and text:match(pattern)
    local dps = num and tonumber((num:gsub(",", "."))) or nil
    if info and dps then info.dps = dps end
    return dps or 0
end

local function AmmoLevel(id)
    local _, _, _, _, minLevel = GetItemInfoFn(id)
    local info = db.items[id]
    return minLevel or (info and info.lvl) or 0
end

local function StackSize(id)
    local stack = select(8, GetItemInfoFn(id))
    return (stack and stack > 1) and stack or 200
end

-- Is ammo a better than ammo b? Damage first, then required level.
local function BetterAmmo(a, b)
    if not b then return true end
    local da, dbb = AmmoDPS(a), AmmoDPS(b)
    if da ~= dbb then return da > dbb end
    return AmmoLevel(a) > AmmoLevel(b)
end

-- Best known ammo of a type usable at your level.
local function BestKnownAmmo(kind)
    local level, best = UnitLevel("player"), nil
    for id, info in pairs(db.items) do
        if info and info.kind == "ammo" and info.sub == kind and AmmoLevel(id) <= level
            and BetterAmmo(id, best) then
            best = id
        end
    end
    return best
end

local function NumSlots(bag)
    return (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0
end

local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local t = C_Container.GetContainerItemInfo(bag, slot)
        if t then return t.itemID, t.stackCount end
        return nil
    end
    local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
    return itemID, count
end

-- Bags 1-4 that are a quiver (arrows) or an ammo pouch (bullets).
local function AmmoBags(kind)
    local bags = {}
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local bit_ = kind == "arrow" and 1 or 2
    for bag = 1, NUM_BAG_SLOTS or 4 do
        local _, family = getFree(bag)
        if type(family) == "number" and family > 0 and bit and bit.band(family, bit_) ~= 0 then
            bags[#bags + 1] = bag
        end
    end
    return bags
end

-- Everything the ammo icon needs:
-- kind, count (all matching ammo), main (ammo you use), capacity,
-- quiverSlots, quiverName, free (room for more of `buyId`), ratio.
local function AmmoStatus(buyId)
    local kind = WeaponAmmoType()
    if not kind then return nil end
    local st = { kind = kind, count = 0, counts = {} }

    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, NumSlots(bag) do
            local id, n = SlotInfo(bag, slot)
            if id and AmmoType(id) == kind then
                st.count = st.count + (n or 1)
                st.counts[id] = (st.counts[id] or 0) + (n or 1)
            end
        end
    end

    local equipped = GetInventoryItemID("player", AMMO_SLOT)
    if equipped and AmmoType(equipped) == kind then
        st.main = equipped
    else
        local most = 0
        for id, n in pairs(st.counts) do
            if n > most then st.main, most = id, n end
        end
    end

    local stack = StackSize(buyId or st.main or 2512)
    local bags = AmmoBags(kind)
    st.quiverSlots, st.free = 0, 0
    for _, bag in ipairs(bags) do
        for slot = 1, NumSlots(bag) do
            st.quiverSlots = st.quiverSlots + 1
            local id, n = SlotInfo(bag, slot)
            if not id then
                st.free = st.free + stack
            elseif buyId and id == buyId and (n or 0) < stack then
                st.free = st.free + stack - n
            end
        end
    end
    if #bags > 0 then
        local invID = (C_Container and C_Container.ContainerIDToInventoryID or ContainerIDToInventoryID)(bags[1])
        st.quiverName = invID and GetItemInfoFn(GetInventoryItemID("player", invID) or 0)
    end

    -- How much ammo you want to carry: the quiver, a manual stack limit, or
    -- without a quiver two stacks.
    local limit = (db.ammoStacks or 0) > 0 and db.ammoStacks or nil
    if st.quiverSlots > 0 then
        st.capacity = math.min(st.quiverSlots, limit or st.quiverSlots) * stack
    else
        st.capacity = (limit or 2) * stack
        st.free = math.max(0, st.capacity - (buyId and st.counts[buyId] or st.count))
    end
    if limit and st.quiverSlots > 0 then
        st.free = math.min(st.free, math.max(0, st.capacity - (buyId and st.counts[buyId] or st.count)))
    end
    st.ratio = st.capacity > 0 and math.min(1, st.count / st.capacity) or 0
    return st
end

local function MerchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local t = C_MerchantFrame.GetItemInfo(i)
        if not t then return nil end
        return t.price, t.stackCount, t.numAvailable, t.isPurchasable, t.isUsable, t.hasExtendedCost
    end
    local _, _, price, quantity, numAvailable, isPurchasable, isUsable, extendedCost = GetMerchantItemInfo(i)
    return price, quantity, numAvailable, isPurchasable, isUsable, extendedCost
end

-- Looks at the open vendor and remembers the best ammo for your weapon and
-- level: { index, id, pricePerItem, bundle, amount (to buy), cost }.
local function ScanMerchantAmmo()
    ammoOffer = nil
    if not merchantOpen then return end
    local kind = WeaponAmmoType()
    if not kind then return end
    local level = UnitLevel("player")
    local best
    for i = 1, (GetMerchantNumItems() or 0) do
        local link = GetMerchantItemLink(i)
        local id = (GetMerchantItemID and GetMerchantItemID(i)) or (link and tonumber(link:match("item:(%d+)")))
        if id then
            Classify(id)
            if AmmoType(id) == kind and AmmoLevel(id) <= level then
                local price, bundle, available, purchasable, usable, extended = MerchantItem(i)
                if price and not extended and purchasable ~= false and usable ~= false and available ~= 0
                    and (not best or BetterAmmo(id, best.id)) then
                    best = { index = i, id = id, bundle = math.max(1, bundle or 1),
                             pricePerItem = (price or 0) / math.max(1, bundle or 1) }
                end
            end
        end
    end
    if not best then return end
    local st = AmmoStatus(best.id)
    local amount = st and st.free or 0
    if best.pricePerItem > 0 then
        amount = math.min(amount, math.floor(GetMoney() / best.pricePerItem))
    end
    -- whole bundles only
    amount = math.floor(amount / best.bundle) * best.bundle
    best.amount = amount
    best.cost = math.floor(amount * best.pricePerItem + 0.5)
    best.stack = StackSize(best.id)
    -- weaker than the ammo you shoot now?
    if st and st.main and st.main ~= best.id and BetterAmmo(st.main, best.id) then
        best.worse = true
        best.current = st.main
    end
    ammoOffer = best
end

local function MoneyText(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return string.format("%dg %ds %dc", copper / 10000, (copper / 100) % 100, copper % 100)
end

local BuyAmmo

-- Asked before buying ammo that is weaker than the ammo you shoot now.
-- Only add our own entry: never assign StaticPopupDialogs itself, that would
-- taint Blizzard's popups (for example the logout countdown).
StaticPopupDialogs["SQUAREDAWAY_WORSE_AMMO"] = {
    text = "%s",
    button1 = L["Buy anyway"],
    button2 = CANCEL or "Cancel",
    OnAccept = function() BuyAmmo(true) end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- One click: buys the offered ammo, a stack at a time. Weaker ammo than
-- yours is only bought after you confirm it in a window (force = true).
function BuyAmmo(force)
    if buying or not merchantOpen then return end
    ScanMerchantAmmo()
    local offer = ammoOffer
    if not offer or offer.amount <= 0 then
        Print(L["Nothing to buy: your quiver is full or you need more gold."])
        return
    end
    if offer.worse and not force then
        local yours, theirs = AmmoDPS(offer.current), AmmoDPS(offer.id)
        local text = L["This vendor only has weaker ammo than yours."] .. "\n\n"
            .. L["Yours: %s"]:format(ItemText(offer.current)) .. (yours > 0 and (" (" .. L["%.1f damage per second"]:format(yours) .. ")") or "") .. "\n"
            .. L["Vendor: %s"]:format(ItemText(offer.id)) .. (theirs > 0 and (" (" .. L["%.1f damage per second"]:format(theirs) .. ")") or "") .. "\n\n"
            .. L["Buy it anyway, so you do not run out in the wild? %d for %s."]:format(offer.amount, MoneyText(offer.cost))
        StaticPopup_Show("SQUAREDAWAY_WORSE_AMMO", text)
        return
    end
    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(offer.index)) or offer.stack
    local left, bought = offer.amount, 0
    buying = true

    local function BuyOne()
        if not merchantOpen or left <= 0 then return false end
        local items, call
        if maxStack <= 1 then
            items, call = offer.bundle, 1                       -- vendor sells whole bundles
        else
            items = math.min(left, maxStack, offer.stack)
            call = items
        end
        if offer.pricePerItem > 0 and GetMoney() < items * offer.pricePerItem then return false end
        BuyMerchantItem(offer.index, call)
        left, bought = left - items, bought + items
        return left > 0
    end

    local function Done()
        buying = false
        if bought > 0 then
            Print(L["bought %d %s for %s."]:format(bought, ItemText(offer.id),
                MoneyText(math.floor(bought * offer.pricePerItem + 0.5))))
        end
        C_Timer.After(0.5, function() ScanMerchantAmmo(); QueueUpdate() end)
    end

    -- the first purchase happens inside your click, the rest follow
    if not BuyOne() then Done() return end
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        if not BuyOne() then ticker:Cancel(); Done() end
    end)
end

----------------------------------------------------------------------
-- Pet
----------------------------------------------------------------------

-- Returns "ok" / "warn" / "missing" and a short text.
local function PetStatus()
    if not UnitExists("pet") then return "missing", L["No pet summoned"] end
    if UnitIsDead("pet") then return "missing", L["Your pet is dead"] end
    local happiness = GetPetHappiness and GetPetHappiness()
    if happiness == 1 then return "missing", L["Your pet is unhappy"] end
    if happiness == 2 then return "warn", L["Your pet is content"] end
    return "ok", L["Your pet is happy"]
end

----------------------------------------------------------------------
-- Display
----------------------------------------------------------------------

local frame = CreateFrame("Frame", "SquaredAwayFrame", UIParent)
frame:SetSize(ICON_SIZE, ICON_SIZE)
frame:SetMovable(true)
frame:EnableMouse(false)
frame:SetClampedToScreen(true)

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    db.pos = { point, relPoint, x, y }
end

local function MakeButton(fallbackIcon, withTimer)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(fallbackIcon)
    b.fallback = fallbackIcon
    b.status = b:CreateTexture(nil, "OVERLAY")
    b.status:SetSize(18, 18)
    b.status:SetPoint("TOPRIGHT", b, "TOPRIGHT", 4, 4)
    if withTimer then
        -- the number sits on a dark strip at the bottom of the icon
        b.strip = b:CreateTexture(nil, "OVERLAY")
        b.strip:SetColorTexture(0, 0, 0, 0.7)
        b.strip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        b.strip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        b.strip:SetHeight(14)
        b.strip:Hide()
        b.timer = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.timer:SetDrawLayer("OVERLAY", 7)
        local font = b.timer:GetFont()
        b.timer:SetFont(font or STANDARD_TEXT_FONT, 12, "OUTLINE")
        b.timer:SetPoint("CENTER", b.strip, "CENTER", 0, 0)
        b.SetTimer = function(self, text)
            self.timer:SetText(text or "")
            self.strip:SetShown(text ~= nil and text ~= "")
        end
    end
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if not db.locked then frame:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local foodButton  = MakeButton("Interface\\Icons\\INV_Misc_Food_14", true)
local kitButton   = MakeButton("Interface\\Icons\\INV_Misc_ArmorKit_17")
local boostButton = MakeButton("Interface\\Icons\\INV_Scroll_02", true)
local scrollButton = MakeButton("Interface\\Icons\\INV_Scroll_03", true)
local ammoButton  = MakeButton("Interface\\Icons\\INV_Ammo_Arrow_02", true)
local petButton   = MakeButton("Interface\\Icons\\Ability_Hunter_BeastCall")

-- Time left: minutes (rounded up), seconds under 1 minute.
local function TimeLeftText(expires)
    if not expires or expires <= 0 then return nil end
    local left = expires - GetTime()
    if left <= 0 then return nil end
    if left < 60 then return math.ceil(left) .. "s", left end
    return tostring(math.ceil(left / 60)), left
end

local function UpdateTimer(b)
    local text, left = TimeLeftText(b.expires)
    if not text then
        b:SetTimer("")
        return
    end
    b:SetTimer(text)
    if left < 60 then
        b.timer:SetTextColor(1, 0.3, 0.3)
    elseif left < 180 then
        b.timer:SetTextColor(1, 0.82, 0)
    else
        b.timer:SetTextColor(1, 1, 1)
    end
end

C_Timer.NewTicker(1, function()
    UpdateTimer(foodButton)
    UpdateTimer(boostButton)
end)

local function AddTimeLine(expires)
    local text, left = TimeLeftText(expires)
    if text then
        GameTooltip:AddLine((left < 60 and L["%s left"] or L["%s min left"]):format(text), 1, 1, 1)
    end
end

local function AddSuggestion(id, label)
    if id then
        GameTooltip:AddLine(label or L["Good at level %d:"]:format(UnitLevel("player")), 1, 1, 1)
        GameTooltip:AddLine(ItemText(id))
        local count = GetItemCountFn(id) or 0
        if count > 0 then
            GameTooltip:AddLine(L["You have %d in your bags."]:format(count), 0.5, 1, 0.5)
        end
    elseif not label then
        GameTooltip:AddLine(L["No suggestion yet."], 1, 1, 1)
        GameTooltip:AddLine(L["Hover over items or visit a vendor so I can learn them."], 0.7, 0.7, 0.7, true)
    end
end

foodButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local fed, expires = IsWellFed()
    if fed then
        GameTooltip:AddLine(L["Well Fed"], 0.4, 1, 0.4)
        AddTimeLine(expires)
    else
        GameTooltip:AddLine(L["Not Well Fed"], 1, 0.4, 0.4)
    end
    AddSuggestion(Best("food"))
    GameTooltip:Show()
end)

kitButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local missing, weaker, perSlot = KitStatus()
    if #missing == 0 and #weaker == 0 then
        GameTooltip:AddLine(L["Armor kits applied"], 0.4, 1, 0.4)
    end
    if #missing > 0 then
        GameTooltip:AddLine(L["Armor kit missing:"], 1, 0.4, 0.4)
        for _, label in ipairs(missing) do
            local id = perSlot[label]
            GameTooltip:AddDoubleLine("  " .. label, id and ItemText(id) or L["no kit known yet"],
                1, 0.4, 0.4, 1, 1, 1)
        end
    end
    if #weaker > 0 then
        GameTooltip:AddLine(L["Weaker kit than you could use:"], 1, 0.82, 0)
        for _, label in ipairs(weaker) do
            local id = perSlot[label]
            GameTooltip:AddDoubleLine("  " .. label .. " (+" .. perSlot[label .. "#current"] .. ")",
                ItemText(id) .. " (+" .. (KitArmor(id) or "?") .. ")", 1, 0.82, 0, 1, 1, 1)
        end
    end
    if #missing == 0 and #weaker == 0 then
        local best = Best("kit")
        AddSuggestion(best, best and L["Best kit at your level:"])
    end
    GameTooltip:AddLine(L["Some kits only fit items of a minimum item level."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)

boostButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local active, expires, name = ActiveBoost()
    if active then
        GameTooltip:AddLine(name or L["Agility boost active"], 0.4, 1, 0.4)
        AddTimeLine(expires)
    else
        GameTooltip:AddLine(L["No agility elixir or scroll"], 1, 0.4, 0.4)
    end
    AddSuggestion(BestBoost())
    GameTooltip:AddLine(L["Agility elixir and agility scroll do not stack: use one."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)

scrollButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local list, active = ScrollStatus()
    local r, g, bl = 0.4, 1, 0.4
    if active == 0 then r, g, bl = 1, 0.4, 0.4 elseif active < #list then r, g, bl = 1, 0.82, 0 end
    GameTooltip:AddLine(L["Stat scrolls: %d of %d active"]:format(active, #list), r, g, bl)
    for _, e in ipairs(list) do
        if e.state == "active" then
            local text = TimeLeftText(e.expires)
            GameTooltip:AddDoubleLine(e.s.label, text and (text:find("s") and L["active, %s"] or L["active, %s min"]):format(text) or L["active"],
                1, 1, 1, 0.4, 1, 0.4)
        elseif e.state == "covered" then
            GameTooltip:AddDoubleLine(e.s.label, L["covered by %s"]:format(e.buff), 1, 1, 1, 0.4, 1, 0.4)
        end
    end
    local first = true
    for _, e in ipairs(list) do
        if e.state == "missing" then
            if first then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Missing:"], 1, 0.4, 0.4)
                first = false
            end
            if e.owned then
                local count = GetItemCountFn(e.best) or 0
                GameTooltip:AddDoubleLine("  " .. e.s.label, L["use %s"]:format(ItemText(e.best)), 1, 0.4, 0.4, 1, 1, 1)
                GameTooltip:AddLine("    " .. L["you have %d in your bags"]:format(count), 0.5, 1, 0.5)
            else
                GameTooltip:AddDoubleLine("  " .. e.s.label, L["none in bags"], 1, 0.4, 0.4, 0.7, 0.7, 0.7)
                if e.best then
                    GameTooltip:AddLine("    " .. L["good at your level: %s"]:format(ItemText(e.best)), 0.7, 0.7, 0.7)
                end
            end
        end
    end
    GameTooltip:AddLine(L["Stamina, Strength, Protection, Intellect."], 0.7, 0.7, 0.7)
    GameTooltip:AddLine(L["Agility scrolls are in the agility icon."], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

-- 1234 -> "1234", 12345 -> "12.3k" (fits the icon)
local function ShortCount(n)
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

ammoButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local st = AmmoStatus(ammoOffer and ammoOffer.id)
    if not st then
        GameTooltip:AddLine(L["No bow, crossbow or gun equipped"], 1, 0.4, 0.4)
        GameTooltip:Show()
        return
    end
    local r, g, bl = 0.4, 1, 0.4
    if st.count < 200 or st.ratio < 0.15 then r, g, bl = 1, 0.4, 0.4 elseif st.ratio < 0.5 then r, g, bl = 1, 0.82, 0 end
    GameTooltip:AddLine((st.kind == "arrow" and L["Arrows: %d / %d"] or L["Bullets: %d / %d"]):format(st.count, st.capacity), r, g, bl)
    if st.main then
        local dps = AmmoDPS(st.main)
        GameTooltip:AddDoubleLine(ItemText(st.main), dps > 0 and L["%.1f damage per second"]:format(dps) or "", 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if st.quiverSlots > 0 then
        GameTooltip:AddLine(L["%s: %d slots"]:format(st.quiverName or (st.kind == "arrow" and L["Quiver"] or L["Ammo pouch"]),
            st.quiverSlots), 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(st.kind == "arrow" and L["No quiver: counting 2 stacks as full."]
            or L["No ammo pouch: counting 2 stacks as full."], 0.7, 0.7, 0.7, true)
    end
    -- better ammo already in the bags, but not the one you shoot
    local equipped = GetInventoryItemID("player", AMMO_SLOT)
    local bestOwned
    for id in pairs(st.counts) do
        if BetterAmmo(id, bestOwned) then bestOwned = id end
    end
    if equipped and bestOwned and bestOwned ~= equipped and BetterAmmo(bestOwned, equipped) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Better ammo in your bags:"], 1, 0.82, 0)
        GameTooltip:AddLine(ItemText(bestOwned))
        GameTooltip:AddLine(L["Right-click it in your bags to use it."], 0.7, 0.7, 0.7, true)
    end
    local best = BestKnownAmmo(st.kind)
    if best and st.main and best ~= st.main and BetterAmmo(best, st.main) and not st.counts[best] then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Better ammo for your level:"], 1, 0.82, 0)
        GameTooltip:AddLine(ItemText(best))
    end
    if merchantOpen then
        GameTooltip:AddLine(" ")
        if ammoOffer and ammoOffer.amount > 0 and ammoOffer.worse then
            GameTooltip:AddLine(L["This vendor only has weaker ammo than yours:"], 1, 0.82, 0, true)
            GameTooltip:AddLine(ItemText(ammoOffer.id))
            GameTooltip:AddLine(L["Left-click: buy anyway (asks first)"], 0.7, 0.7, 0.7)
        elseif ammoOffer and ammoOffer.amount > 0 then
            GameTooltip:AddLine(L["This vendor sells:"], 0.4, 1, 0.4)
            GameTooltip:AddLine(ItemText(ammoOffer.id))
            GameTooltip:AddLine(L["Left-click: buy %d for %s"]:format(ammoOffer.amount, MoneyText(ammoOffer.cost)), 0.4, 1, 0.4)
        elseif ammoOffer then
            GameTooltip:AddLine(L["Nothing to buy: your quiver is full or you need more gold."], 0.7, 0.7, 0.7, true)
        else
            GameTooltip:AddLine(L["This vendor has no ammo for you."], 0.7, 0.7, 0.7)
        end
    end
    GameTooltip:Show()
end)

petButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local state, text = PetStatus()
    local r, g, bl = 0.4, 1, 0.4
    if state == "warn" then r, g, bl = 1, 0.82, 0 elseif state == "missing" then r, g, bl = 1, 0.4, 0.4 end
    if UnitExists("pet") then GameTooltip:AddLine(UnitName("pet") or L["Pet"], 1, 1, 1) end
    GameTooltip:AddLine(text, r, g, bl)
    if state ~= "ok" and UnitExists("pet") and not UnitIsDead("pet") then
        GameTooltip:AddLine(L["Feed your pet to make it happy."], 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end)

local function SetState(b, state, iconId)
    b.icon:SetTexture((iconId and GetItemIconFn(iconId)) or b.fallback)
    b.status:SetTexture(state == "ok" and CHECK or state == "warn" and WARN or CROSS)
    b:SetAlpha(state == "ok" and 0.8 or 1)
end

local function Shown(key)
    return not (db.hidden and db.hidden[key])
end

local buttons = {
    { key = "food",  button = foodButton },
    { key = "kits",  button = kitButton },
    { key = "boost", button = boostButton },
    { key = "scrolls", button = scrollButton },
    { key = "ammo",  button = ammoButton },
    { key = "pet",   button = petButton, hunterOnly = true },
}

----------------------------------------------------------------------
-- Aspect reminder (hunters): flashing text in the middle of the screen
-- while no aspect is active. Works in and out of combat.
----------------------------------------------------------------------

local aspectNames

local function AspectNames()
    if not aspectNames then
        aspectNames = {}
        for _, id in ipairs(ns.ASPECT_SPELLS) do
            local name = SpellName(id)
            if name then aspectNames[name] = true end
        end
    end
    return aspectNames
end

-- Has the player learned at least one aspect?
local function KnowsAspect()
    local check = IsPlayerSpell or IsSpellKnown
    if not check then return true end
    for _, id in ipairs(ns.ASPECT_SPELLS) do
        if check(id) then return true end
    end
    return false
end

local function ActiveAspect()
    local names = AspectNames()
    return FindBuff(function(name)
        if not name then return false end
        if names[name] then return true end
        local lname = name:lower()
        return lname:find("^aspect of") or lname:find("^aspekt de")
    end)
end

local aspectAlert = CreateFrame("Frame", "SquaredAwayAspectAlert", UIParent)
aspectAlert:SetSize(500, 60)
aspectAlert:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
aspectAlert:SetFrameStrata("HIGH")
aspectAlert:Hide()

local aspectText = aspectAlert:CreateFontString(nil, "OVERLAY")
aspectText:SetFont(STANDARD_TEXT_FONT, 32, "THICKOUTLINE")
aspectText:SetPoint("CENTER")
aspectText:SetTextColor(1, 0.25, 0.1)
aspectText:SetText(L["No aspect active!"])

local aspectFlash = aspectAlert:CreateAnimationGroup()
aspectFlash:SetLooping("BOUNCE")
local aspectFade = aspectFlash:CreateAnimation("Alpha")
aspectFade:SetFromAlpha(1)
aspectFade:SetToAlpha(0.15)
aspectFade:SetDuration(0.6)

local function UpdateAspect()
    local show = false
    if db and isHunter and Shown("aspect") and not UnitIsDeadOrGhost("player")
        and not (UnitOnTaxi and UnitOnTaxi("player")) and KnowsAspect() then
        show = not ActiveAspect()
    end
    if show then
        aspectAlert:Show()
        if not aspectFlash:IsPlaying() then aspectFlash:Play() end
    else
        aspectFlash:Stop()
        aspectAlert:Hide()
    end
end

local RefreshDB -- database window refresh, set further down

local function Update()
    if not db then return end
    UpdateAspect()
    if RefreshDB then RefreshDB() end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        for _, e in ipairs(buttons) do e.button:Hide() end
        return
    end

    -- food
    local fed, fedExpires = IsWellFed()
    foodButton.expires = fed and fedExpires or nil
    SetState(foodButton, fed and "ok" or "missing", Best("food"))
    UpdateTimer(foodButton)

    -- kits
    local missing, weaker = KitStatus()
    SetState(kitButton, #missing > 0 and "missing" or #weaker > 0 and "warn" or "ok", Best("kit"))

    -- elixir / scroll
    local active, boostExpires = ActiveBoost()
    boostButton.expires = active and boostExpires or nil
    SetState(boostButton, active and "ok" or "missing", BestBoost())
    UpdateTimer(boostButton)

    -- other scrolls: count in the icon, hidden while no scroll is known
    local scrollList, scrollActive = ScrollStatus()
    scrollButton.empty = #scrollList == 0
    if not scrollButton.empty then
        local firstMissing
        for _, e in ipairs(scrollList) do
            if e.state == "missing" and not firstMissing then firstMissing = e.best end
        end
        SetState(scrollButton, scrollActive == #scrollList and "ok" or scrollActive > 0 and "warn" or "missing",
            firstMissing)
        scrollButton:SetTimer(scrollActive .. "/" .. #scrollList)
        scrollButton.timer:SetTextColor(1, 1, 1)
    end

    -- ammo: count in the icon; at a vendor "+N" and a click buys
    local ammo = AmmoStatus(ammoOffer and ammoOffer.id)
    ammoButton.empty = ammo == nil
    if ammo then
        if merchantOpen and ammoOffer and ammoOffer.amount > 0 then
            SetState(ammoButton, "warn", ammoOffer.id)
            ammoButton:SetTimer("+" .. ShortCount(ammoOffer.amount))
            if ammoOffer.worse then ammoButton.timer:SetTextColor(0.6, 0.6, 0.6)
            else ammoButton.timer:SetTextColor(0.4, 1, 0.4) end
        else
            local state = (ammo.count < 200 or ammo.ratio < 0.15) and "missing" or ammo.ratio < 0.5 and "warn" or "ok"
            SetState(ammoButton, state, ammo.main)
            ammoButton:SetTimer(ShortCount(ammo.count))
            if state == "missing" then ammoButton.timer:SetTextColor(1, 0.3, 0.3)
            elseif state == "warn" then ammoButton.timer:SetTextColor(1, 0.82, 0)
            else ammoButton.timer:SetTextColor(1, 1, 1) end
        end
    end

    -- pet
    SetState(petButton, (PetStatus()))

    -- layout: visible icons side by side
    local x = 0
    for _, e in ipairs(buttons) do
        if Shown(e.key) and (not e.hunterOnly or isHunter) and not e.button.empty then
            e.button:ClearAllPoints()
            e.button:SetPoint("LEFT", frame, "LEFT", x, 0)
            e.button:Show()
            x = x + ICON_SIZE + GAP
        else
            e.button:Hide()
        end
    end
    frame:SetWidth(math.max(ICON_SIZE, x - GAP))
end

local updateQueued = false
function QueueUpdate()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.3, function()
        updateQueued = false
        Update()
    end)
end

----------------------------------------------------------------------
-- Settings window (right-click an icon, or /sqa config)
----------------------------------------------------------------------

local settings = CreateFrame("Frame", "SquaredAwaySettings", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
settings:SetSize(330, 386)
settings:SetPoint("CENTER")
settings:SetFrameStrata("DIALOG")
settings:SetMovable(true)
settings:EnableMouse(true)
settings:RegisterForDrag("LeftButton")
settings:SetScript("OnDragStart", settings.StartMoving)
settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
settings:SetClampedToScreen(true)
if settings.SetBackdrop then
    settings:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end
settings:Hide()
tinsert(UISpecialFrames, "SquaredAwaySettings") -- Escape closes it

local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -18)
title:SetText("Squared Away")

local close = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -6, -6)

local checks = {}

local function AddCheck(label, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 22, y)
    local text = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        Update()
    end)
    cb.getter = getter
    cb.label = text
    checks[#checks + 1] = cb
    return cb
end

local function ShowToggle(key)
    return function() return Shown(key) end,
           function(on) db.hidden[key] = (not on) or nil end
end

AddCheck(L["Show food"], -50, ShowToggle("food"))
AddCheck(L["Show armor kits"], -76, ShowToggle("kits"))
AddCheck(L["Show agility elixir / scroll"], -102, ShowToggle("boost"))
AddCheck(L["Show stat scrolls"], -128, ShowToggle("scrolls"))
AddCheck(L["Show ammo"], -154, ShowToggle("ammo"))
local petCheck = AddCheck(L["Show pet"], -180, ShowToggle("pet"))
local aspectCheck = AddCheck(L["Aspect reminder"], -206, ShowToggle("aspect"))
AddCheck(L["Lock bar"], -238,
    function() return db.locked end,
    function(on) db.locked = on or nil end)

local resetBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("BOTTOM", 0, 44)
resetBtn:SetText(L["Reset position"])
resetBtn:SetScript("OnClick", function()
    db.pos = nil
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
end)

settings:SetScript("OnShow", function()
    for _, cb in ipairs(checks) do cb:SetChecked(cb.getter() and true or false) end
    petCheck:SetShown(isHunter)
    petCheck.label:SetShown(isHunter)
    aspectCheck:SetShown(isHunter)
    aspectCheck.label:SetShown(isHunter)
end)

local function ToggleSettings()
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

----------------------------------------------------------------------
-- Database window (/sqa db, settings button, shift + right-click an icon)
-- Lists all known food, kits and elixirs/scrolls sorted by level.
----------------------------------------------------------------------

local DB_TABS = {
    { key = "food",  label = L["Food"],        noun = L["food"] },
    { key = "kit",   label = L["Armor kits"],  noun = L["armor kits"] },
    { key = "boost", label = L["Agility"],     noun = L["agility elixirs or scrolls"] },
    { key = "scroll", label = L["Stat scrolls"], noun = L["stat scrolls"] },
}
local DB_SEEDS = { food = "SEED_FOOD", kit = "SEED_KITS", boost = "SEED_BOOSTS", scroll = "SEED_SCROLLS" }
local ICON_TAB = { food = "food", kits = "kit", kit = "kit", boost = "boost",
    scrolls = "scroll", scroll = "scroll" }
local ROW_H = 36
local LIST_W = 384
local QualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor

local dbTab = "food"

local dbWin = CreateFrame("Frame", "SquaredAwayDatabase", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
dbWin:SetSize(440, 500)
dbWin:SetPoint("CENTER")
dbWin:SetFrameStrata("DIALOG")
dbWin:SetMovable(true)
dbWin:EnableMouse(true)
dbWin:RegisterForDrag("LeftButton")
dbWin:SetScript("OnDragStart", dbWin.StartMoving)
dbWin:SetScript("OnDragStop", dbWin.StopMovingOrSizing)
dbWin:SetClampedToScreen(true)
if dbWin.SetBackdrop then
    dbWin:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end
dbWin:Hide()
tinsert(UISpecialFrames, "SquaredAwayDatabase") -- Escape closes it

local dbTitle = dbWin:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dbTitle:SetPoint("TOP", 0, -18)
dbTitle:SetText(L["Squared Away: Database"])

local dbClose = CreateFrame("Button", nil, dbWin, "UIPanelCloseButton")
dbClose:SetPoint("TOPRIGHT", -6, -6)

local tabButtons = {}
local tabX = 18
for i, t in ipairs(DB_TABS) do
    local b = CreateFrame("Button", nil, dbWin, "UIPanelButtonTemplate")
    b:SetText(t.label)
    -- width follows the text, so longer translations fit
    local fs = b.GetFontString and b:GetFontString()
    local w = math.max(70, math.min(110, ((fs and fs:GetStringWidth()) or 70) + 18))
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", tabX, -44)
    tabX = tabX + w + 3
    b.key = t.key
    b:SetScript("OnClick", function()
        dbTab = t.key
        RefreshDB()
    end)
    tabButtons[i] = b
end

local scroll = CreateFrame("ScrollFrame", "SquaredAwayDatabaseScroll", dbWin, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 18, -74)
scroll:SetPoint("BOTTOMRIGHT", -38, 112)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(LIST_W, 1)
scroll:SetScrollChild(content)

local footer = dbWin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
footer:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
footer:SetWidth(404)
footer:SetJustifyH("LEFT")
footer:SetJustifyV("TOP")

local dbCredit = dbWin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dbCredit:SetPoint("BOTTOMLEFT", 18, 16)
dbCredit:SetWidth(404)
dbCredit:SetJustifyH("LEFT")
dbCredit:SetText(CREDIT .. (ns.DATA_BUILD and (", " .. L["game build %s"]:format(ns.DATA_BUILD)) or ""))

local rows = {}

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 0.82, 0, 0.12)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 2, 0)

    row.mark = row:CreateTexture(nil, "OVERLAY")
    row.mark:SetSize(16, 16)
    row.mark:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -4)
    row.mark:SetTexture(CHECK)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetWidth(LIST_W - 150)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.detail:SetWidth(LIST_W - 120)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("TOPRIGHT", -6, -5)
    row.level:SetJustifyH("RIGHT")

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("BOTTOMRIGHT", -6, 5)
    row.count:SetJustifyH("RIGHT")
    row.count:SetTextColor(0.5, 1, 0.5)

    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.id)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if IsShiftKeyDown() then
            local _, link = GetItemInfoFn(self.id)
            if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
        end
    end)

    rows[i] = row
    return row
end

local function ReqLevel(id, info)
    local _, _, _, _, minLevel = GetItemInfoFn(id)
    return minLevel or info.lvl or 0
end

local FOOD_WORDS = {
    [3] = L["agility or attack power"],
    [2] = L["stamina or crit"],
    [1] = L["intellect or armor"],
    [0] = L["not useful for hunters"],
}

-- Short second line for a row, and whether the item is useful for you.
local function RowDetail(kind, id, info)
    if kind == "food" then
        local score = FoodScore(id)
        return FOOD_WORDS[score] or "", score > 0
    elseif kind == "kit" then
        if not KitUseful(id) then return L["spell power, not for hunters"], false end
        local parts = {}
        local armor = KitArmor(id)
        if armor then parts[#parts + 1] = L["+%d armor"]:format(armor) end
        local minIlvl = KitMinIlvl(id)
        if minIlvl > 0 then parts[#parts + 1] = L["items of level %d+"]:format(minIlvl) end
        return table.concat(parts, ", "), true
    elseif kind == "scroll" then
        local label = info.stat
        for _, s in ipairs(ns.SCROLL_STATS) do
            if s.key == info.stat then label = s.label:lower() end
        end
        local amount = ScrollAmount(id)
        return (amount > 0 and ("+" .. amount .. " ") or "") .. label .. ", " .. L["scroll"], true
    else
        local amount = BoostAmount(id)
        local sub = info.sub == "scroll" and L["scroll"] or L["elixir"]
        return (amount > 0 and (L["+%d agility"]:format(amount) .. ", " .. sub) or sub), true
    end
end

-- Items that are suggested right now (for kits: the best kit per slot).
local function SuggestedSet(kind)
    local set = {}
    if kind == "food" then
        local id = Best("food")
        if id then set[id] = true end
    elseif kind == "kit" then
        local _, _, perSlot = KitStatus()
        for key, v in pairs(perSlot) do
            if not key:find("#", 1, true) then set[v] = true end
        end
        if not next(set) then
            local id = Best("kit")
            if id then set[id] = true end
        end
    elseif kind == "scroll" then
        for _, s in ipairs(ns.SCROLL_STATS) do
            local id = BestScroll(s.key)
            if id then set[id] = true end
        end
    else
        local id = BestBoost()
        if id then set[id] = true end
    end
    return set
end

-- "No new food known for levels 21-30, 46-50." in steps of 5 levels.
local function GapText(levels, noun)
    local maxLevel = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
    local ranges, from, to = {}, nil, nil
    for start = 1, maxLevel, 5 do
        local stop = math.min(start + 4, maxLevel)
        local found = false
        for lvl = start, stop do
            if levels[lvl] then found = true break end
        end
        if found then
            if from then
                ranges[#ranges + 1] = from .. "-" .. to
                from = nil
            end
        else
            from = from or start
            to = stop
        end
    end
    if from then ranges[#ranges + 1] = from .. "-" .. to end
    if #ranges == 0 then return nil end
    return L["No new %s known for levels %s."]:format(noun, table.concat(ranges, ", "))
end

RefreshDB = function()
    if not db or not dbWin:IsShown() then return end

    local tab = DB_TABS[1]
    for _, t in ipairs(DB_TABS) do
        if t.key == dbTab then tab = t end
    end
    for _, b in ipairs(tabButtons) do
        if b.key == dbTab then b:LockHighlight() else b:UnlockHighlight() end
    end

    local list = {}
    for id, info in pairs(db.items) do
        if info and info.kind == dbTab then
            list[#list + 1] = {
                id = id, info = info, lvl = ReqLevel(id, info),
                name = (GetItemInfoFn(id)) or (L["item"] .. " " .. id),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.lvl ~= b.lvl then return a.lvl < b.lvl end
        return a.name < b.name
    end)

    local level = UnitLevel("player")
    local suggested = SuggestedSet(dbTab)
    local levels, later = {}, 0

    for i, e in ipairs(list) do
        local row = GetRow(i)
        row.id = e.id
        row.icon:SetTexture(GetItemIconFn(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(e.name)
        local _, _, quality = GetItemInfoFn(e.id)
        local r, g, bl = 1, 1, 1
        if quality and QualityColor then r, g, bl = QualityColor(quality) end
        row.name:SetTextColor(r or 1, g or 1, bl or 1)

        local detail, useful = RowDetail(dbTab, e.id, e.info)
        row.detail:SetText(detail)
        if useful then levels[math.max(1, e.lvl)] = true end

        if e.lvl > level then
            row.level:SetText(L["from level %d"]:format(e.lvl))
            later = later + 1
        elseif e.lvl <= 1 then
            row.level:SetText(L["any level"])
        else
            row.level:SetText(L["level %d"]:format(e.lvl))
        end

        local count = GetItemCountFn(e.id) or 0
        row.count:SetText(count > 0 and L["%d in bags"]:format(count) or "")

        local isSuggested = suggested[e.id] and true or false
        row.mark:SetShown(isSuggested)
        row.bg:SetShown(isSuggested)
        row:SetAlpha((e.lvl > level or not useful) and 0.45 or 1)
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_H))

    local notes = {}
    if #list == 0 then
        notes[#notes + 1] = L["Nothing known yet. Hover over items or visit a vendor."]
    else
        notes[#notes + 1] = L["%d known, %d usable at your level. Check mark = current suggestion."]:format(#list, #list - later)
    end
    local gap = GapText(levels, tab.noun)
    if gap then notes[#notes + 1] = gap end
    local notLoaded = 0
    for _, id in ipairs(ns[DB_SEEDS[dbTab]]) do
        if not GetItemInfoFn(id) then notLoaded = notLoaded + 1 end
    end
    if notLoaded > 0 then
        notes[#notes + 1] = L["%d items still loading from the game."]:format(notLoaded)
    end
    notes[#notes + 1] = L["Shift-click a row to link the item in chat."]
    footer:SetText(table.concat(notes, "\n"))
end

local function OpenDB(tab)
    if tab then dbTab = tab end
    -- ask the game again for items it has not sent yet
    for _, key in pairs(DB_SEEDS) do
        for _, id in ipairs(ns[key]) do
            if not GetItemInfoFn(id) and RequestLoad then RequestLoad(id) end
        end
    end
    dbWin:Show()
    RefreshDB()
end

local function ToggleDB(tab)
    if dbWin:IsShown() and (not tab or tab == dbTab) then
        dbWin:Hide()
    else
        OpenDB(tab)
    end
end

local settingsCredit = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
settingsCredit:SetPoint("BOTTOM", 0, 18)
settingsCredit:SetWidth(290)
settingsCredit:SetText(CREDIT .. (ns.DATA_BUILD and ("\n" .. L["Game build %s"]:format(ns.DATA_BUILD)) or ""))

local dbBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
dbBtn:SetSize(140, 22)
dbBtn:SetPoint("BOTTOM", resetBtn, "TOP", 0, 6)
dbBtn:SetText(L["Database"])
dbBtn:SetScript("OnClick", function()
    settings:Hide()
    OpenDB()
end)

-- Hint lines at the bottom of every icon tooltip. Right-click opens the
-- settings, shift + right-click the database at that icon's list.
for _, e in ipairs(buttons) do
    local b = e.button
    b:RegisterForClicks(e.key == "ammo" and "AnyUp" or "RightButtonUp")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" and e.key == "ammo" then
            BuyAmmo()
        elseif mouse == "RightButton" then
            if IsShiftKeyDown() then ToggleDB(ICON_TAB[e.key]) else ToggleSettings() end
        end
    end)
    b:HookScript("OnEnter", function()
        GameTooltip:AddLine(" ")
        if db and db.locked then
            GameTooltip:AddLine(L["Bar is locked"], 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(L["Left-click and hold to move the bar"], 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(L["Right-click for settings"], 0.6, 0.6, 0.6)
        GameTooltip:AddLine(L["Shift + right-click for the database"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
end

----------------------------------------------------------------------
-- Hover learning: any item tooltip you look at teaches the addon
----------------------------------------------------------------------

local function OnItemTooltip(tooltip)
    if tooltip == scanTip or not db then return end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id and db.items[id] == nil then
                C_Timer.After(0, function()
                    Classify(id)
                    QueueUpdate()
                end)
            end
        end
    end
end

local function HookTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
    else
        GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip) end
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local last = {}

local function AnnounceIfChanged()
    local checks = {
        { "food",  Best("food"),  L["best food for your level: %s"] },
        { "kit",   Best("kit"),   L["best armor kit for your level: %s"] },
        { "boost", BestBoost(),   L["best agility elixir or scroll for your level: %s"] },
    }
    for _, c in ipairs(checks) do
        if c[2] and c[2] ~= last[c[1]] then Print(c[3]:format(ItemText(c[2]))) end
        last[c[1]] = c[2]
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        SquaredAwayDB = SquaredAwayDB or {}
        db = SquaredAwayDB
        db.items = db.items or {}
        db.hidden = db.hidden or {}

        -- Items stored as "nothing" by an older version may now be elixirs
        -- or scrolls, so check those again once.
        if (db.dataVersion or 1) < 4 then
            for id, info in pairs(db.items) do
                if info == false then db.items[id] = nil end
            end
            db.dataVersion = 4
        end

        isHunter = select(2, UnitClass("player")) == "HUNTER"

        frame:ClearAllPoints()
        if db.pos then
            frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end

        -- Items from ItemData.lua: their kind and numbers come from the data,
        -- so no tooltip words are needed (works in every client language).
        for id, data in pairs(ns.ITEMS) do
            local info = {}
            for k, v in pairs(data) do info[k] = v end
            local old = db.items[id]
            if type(old) == "table" then info.spellName = old.spellName end
            db.items[id] = info
            if RequestLoad then RequestLoad(id) end
        end
        ScanBags()
        HookTooltips()

        self:RegisterEvent("UNIT_AURA")
        self:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("MERCHANT_SHOW")
        self:RegisterEvent("MERCHANT_CLOSED")
        self:RegisterEvent("MERCHANT_UPDATE")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("UNIT_PET")
        self:RegisterEvent("UNIT_HEALTH")
        self:RegisterEvent("PET_UI_UPDATE")
        pcall(self.RegisterEvent, self, "UNIT_HAPPINESS")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        self:RegisterEvent("PLAYER_CONTROL_LOST")
        self:RegisterEvent("PLAYER_CONTROL_GAINED")
        self:RegisterEvent("SPELLS_CHANGED")

        C_Timer.After(5, function()
            last.food, last.kit = Best("food"), Best("kit")
            last.boost = BestBoost()
            Update()
        end)
        Print(L["loaded. Type /sqa for options."])

    elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" or arg1 == "pet" then QueueUpdate() end

    elseif event == "UNIT_PET" then
        if arg1 == "player" then QueueUpdate() end

    elseif event == "UNIT_HEALTH" or event == "UNIT_HAPPINESS" then
        if arg1 == "pet" then QueueUpdate() end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id = tonumber(arg1)
        if id and pending[id] then
            Classify(id)
            QueueUpdate()
        elseif id and ns.ITEMS[id] then
            QueueUpdate() -- name and icon of a known item arrived
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        ScanBags()
        if merchantOpen and not buying then ScanMerchantAmmo() end
        QueueUpdate()

    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        ScanMerchant()
        ScanMerchantAmmo()
        QueueUpdate()

    elseif event == "MERCHANT_UPDATE" then
        if not buying then ScanMerchantAmmo() end
        QueueUpdate()

    elseif event == "MERCHANT_CLOSED" then
        merchantOpen, ammoOffer = false, nil
        QueueUpdate()

    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, function()
            AnnounceIfChanged()
            Update()
        end)

    else
        QueueUpdate()
    end
end)

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

local TOGGLE_KEYS = { food = true, kits = true, boost = true, scrolls = true, ammo = true, pet = true, aspect = true }

SLASH_SQUAREDAWAY1 = "/sqa"
SLASH_SQUAREDAWAY2 = "/squared"
SlashCmdList.SQUAREDAWAY = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")

    if cmd == "lock" then
        db.locked = true
        Print(L["icons locked."])
    elseif cmd == "unlock" then
        db.locked = false
        Print(L["icons unlocked. Drag an icon to move them."])
    elseif cmd == "reset" then
        db.pos = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        Print(L["position reset."])
    elseif cmd == "config" or cmd == "settings" then
        ToggleSettings()
    elseif cmd == "ammo" then
        local n = tonumber(arg)
        if n and n >= 0 then
            db.ammoStacks = n > 0 and math.floor(n) or nil
            Print(n > 0 and L["ammo: carry %d stacks."]:format(math.floor(n)) or L["ammo: fill the quiver."])
            if merchantOpen then ScanMerchantAmmo() end
            Update()
        else
            Print(L["use: /sqa ammo <stacks>  (0 = fill the quiver)"])
        end
    elseif cmd == "db" or cmd == "database" then
        ToggleDB(ICON_TAB[arg])
    elseif cmd == "hide" or cmd == "show" then
        if TOGGLE_KEYS[arg] then
            db.hidden[arg] = (cmd == "hide") or nil
            Print((cmd == "hide" and L["%s hidden."] or L["%s shown."]):format(arg))
            Update()
        else
            Print(L["use: /sqa %s food | kits | boost | scrolls | ammo | pet | aspect"]:format(cmd))
        end
    elseif cmd == "list" then
        local counts = { food = 0, kit = 0, boost = 0, scroll = 0 }
        for _, info in pairs(db.items) do
            if info and counts[info.kind] then counts[info.kind] = counts[info.kind] + 1 end
        end
        Print(L["known: %d Well Fed foods, %d armor kits, %d agility elixirs/scrolls, %d stat scrolls."]:format(
            counts.food, counts.kit, counts.boost, counts.scroll))
        local food, kit = Best("food"), Best("kit")
        local boost = BestBoost()
        Print(L["food: %s"]:format(food and ItemText(food) or L["none known yet"]))
        Print(L["armor kit: %s"]:format(kit and ItemText(kit) or L["none known yet"]))
        Print(L["agility elixir or scroll: %s"]:format(boost and ItemText(boost) or L["none known yet"]))
        local scrollList, scrollActive = ScrollStatus()
        local missingNames = {}
        for _, e in ipairs(scrollList) do
            if e.state == "missing" then missingNames[#missingNames + 1] = e.s.label end
        end
        Print(L["stat scrolls: %d/%d active"]:format(scrollActive, #scrollList)
            .. (#missingNames > 0 and (", " .. L["missing: %s"]:format(table.concat(missingNames, ", "))) or ""))
        local missing, weaker = KitStatus()
        Print(L["missing kits: %s"]:format(#missing > 0 and table.concat(missing, ", ") or L["none"]))
        Print(L["weaker kits: %s"]:format(#weaker > 0 and table.concat(weaker, ", ") or L["none"]))
        Print(L["Well Fed: %s, agility boost: %s"]:format(IsWellFed() and L["yes"] or L["no"], ActiveBoost() and L["yes"] or L["no"]))
        local ammo = AmmoStatus()
        if ammo then Print(L["ammo: %d / %d"]:format(ammo.count, ammo.capacity)) end
        if isHunter then
            Print(L["pet: %s"]:format(select(2, PetStatus())))
            Print(L["aspect: %s"]:format(ActiveAspect() and L["active"] or (KnowsAspect() and L["none active"] or L["none learned yet"])))
        end
    else
        Print(L["commands:"])
        Print(L["  /sqa config  open the settings (or right-click an icon)"])
        Print(L["  /sqa list    what I know and suggest"])
        Print(L["  /sqa db      database of known food, kits, elixirs and scrolls"])
        Print(L["               (/sqa db food | kits | boost | scrolls opens that list)"])
        Print(L["  /sqa hide | show food | kits | boost | scrolls | ammo | pet | aspect"])
        Print(L["  /sqa ammo N  carry N stacks of ammo (0 = fill the quiver)"])
        Print(L["  /sqa lock | unlock    stop or allow dragging"])
        Print(L["  /sqa reset   move icons back to the middle"])
    end
end
