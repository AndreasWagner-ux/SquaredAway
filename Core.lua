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

local PREFIX = "|cff7fd4ffSquared Away|r: "
local ICON_SIZE = 36
local GAP = 6

local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconFn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemSpellFn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WARN  = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local db
local pending = {}
local isHunter = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
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

-- Calls fn(name, icon, expirationTime) for each buff; stops and returns
-- true, expirationTime, name when fn returns true.
local function FindBuff(fn)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if fn(aura.name, aura.icon) then return true, aura.expirationTime, aura.name end
        end
    else
        for i = 1, 40 do
            local name, icon, _, _, _, expirationTime = UnitBuff("player", i)
            if not name then break end
            if fn(name, icon) then return true, expirationTime, name end
        end
    end
    return false
end

local function IsWellFed()
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
    return link or name or ("item " .. id)
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
local function ActiveBoost()
    local names = {}
    for id, info in pairs(db.items) do
        if info and info.kind == "boost" then
            if not info.spell then
                info.spell = GetItemSpellFn(id)
            end
            if info.spell then names[info.spell] = true end
        end
    end
    return FindBuff(function(name) return name and names[name] end)
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
-- Pet
----------------------------------------------------------------------

-- Returns "ok" / "warn" / "missing" and a short text.
local function PetStatus()
    if not UnitExists("pet") then return "missing", "No pet summoned" end
    if UnitIsDead("pet") then return "missing", "Your pet is dead" end
    local happiness = GetPetHappiness and GetPetHappiness()
    if happiness == 1 then return "missing", "Your pet is unhappy" end
    if happiness == 2 then return "warn", "Your pet is content" end
    return "ok", "Your pet is happy"
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
    b.status:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
    if withTimer then
        b.timer = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
        b.timer:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.timer:SetShadowOffset(1, -1)
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
        b.timer:SetText("")
        return
    end
    b.timer:SetText(text)
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
        GameTooltip:AddLine(text .. (left < 60 and " left" or " min left"), 1, 1, 1)
    end
end

local function AddSuggestion(id, label)
    if id then
        GameTooltip:AddLine(label or ("Good at level " .. UnitLevel("player") .. ":"), 1, 1, 1)
        GameTooltip:AddLine(ItemText(id))
        local count = GetItemCountFn(id) or 0
        if count > 0 then
            GameTooltip:AddLine("You have " .. count .. " in your bags.", 0.5, 1, 0.5)
        end
    elseif not label then
        GameTooltip:AddLine("No suggestion yet.", 1, 1, 1)
        GameTooltip:AddLine("Hover over items or visit a vendor so I can learn them.", 0.7, 0.7, 0.7, true)
    end
end

foodButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local fed, expires = IsWellFed()
    if fed then
        GameTooltip:AddLine("Well Fed", 0.4, 1, 0.4)
        AddTimeLine(expires)
    else
        GameTooltip:AddLine("Not Well Fed", 1, 0.4, 0.4)
    end
    AddSuggestion(Best("food"))
    GameTooltip:Show()
end)

kitButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local missing, weaker, perSlot = KitStatus()
    if #missing == 0 and #weaker == 0 then
        GameTooltip:AddLine("Armor kits applied", 0.4, 1, 0.4)
    end
    if #missing > 0 then
        GameTooltip:AddLine("Armor kit missing:", 1, 0.4, 0.4)
        for _, label in ipairs(missing) do
            local id = perSlot[label]
            GameTooltip:AddDoubleLine("  " .. label, id and ItemText(id) or "no kit known yet",
                1, 0.4, 0.4, 1, 1, 1)
        end
    end
    if #weaker > 0 then
        GameTooltip:AddLine("Weaker kit than you could use:", 1, 0.82, 0)
        for _, label in ipairs(weaker) do
            local id = perSlot[label]
            GameTooltip:AddDoubleLine("  " .. label .. " (+" .. perSlot[label .. "#current"] .. ")",
                ItemText(id) .. " (+" .. (KitArmor(id) or "?") .. ")", 1, 0.82, 0, 1, 1, 1)
        end
    end
    if #missing == 0 and #weaker == 0 then
        local best = Best("kit")
        AddSuggestion(best, best and "Best kit at your level:")
    end
    GameTooltip:AddLine("Some kits only fit items of a minimum item level.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)

boostButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local active, expires, name = ActiveBoost()
    if active then
        GameTooltip:AddLine(name or "Agility boost active", 0.4, 1, 0.4)
        AddTimeLine(expires)
    else
        GameTooltip:AddLine("No agility elixir or scroll", 1, 0.4, 0.4)
    end
    AddSuggestion(BestBoost())
    GameTooltip:AddLine("Elixir and scroll do not stack: use one.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

petButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    local state, text = PetStatus()
    local r, g, bl = 0.4, 1, 0.4
    if state == "warn" then r, g, bl = 1, 0.82, 0 elseif state == "missing" then r, g, bl = 1, 0.4, 0.4 end
    if UnitExists("pet") then GameTooltip:AddLine(UnitName("pet") or "Pet", 1, 1, 1) end
    GameTooltip:AddLine(text, r, g, bl)
    if state ~= "ok" and UnitExists("pet") and not UnitIsDead("pet") then
        GameTooltip:AddLine("Feed your pet to make it happy.", 0.7, 0.7, 0.7)
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
    { key = "pet",   button = petButton, hunterOnly = true },
}

local function Update()
    if not db then return end
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

    -- pet
    SetState(petButton, (PetStatus()))

    -- layout: visible icons side by side
    local x = 0
    for _, e in ipairs(buttons) do
        if Shown(e.key) and (not e.hunterOnly or isHunter) then
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
local function QueueUpdate()
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
settings:SetSize(240, 230)
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

AddCheck("Show food", -50, ShowToggle("food"))
AddCheck("Show armor kits", -76, ShowToggle("kits"))
AddCheck("Show elixir / scroll", -102, ShowToggle("boost"))
local petCheck = AddCheck("Show pet", -128, ShowToggle("pet"))
AddCheck("Lock bar", -160,
    function() return db.locked end,
    function(on) db.locked = on or nil end)

local resetBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("BOTTOM", 0, 20)
resetBtn:SetText("Reset position")
resetBtn:SetScript("OnClick", function()
    db.pos = nil
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
end)

settings:SetScript("OnShow", function()
    for _, cb in ipairs(checks) do cb:SetChecked(cb.getter() and true or false) end
    petCheck:SetShown(isHunter)
    petCheck.label:SetShown(isHunter)
end)

local function ToggleSettings()
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

-- Hint lines at the bottom of every icon tooltip, and right-click to open
-- the settings.
for _, e in ipairs(buttons) do
    local b = e.button
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ToggleSettings() end
    end)
    b:HookScript("OnEnter", function()
        GameTooltip:AddLine(" ")
        if db and db.locked then
            GameTooltip:AddLine("Bar is locked", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("Left-click and hold to move the bar", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("Right-click for settings", 0.6, 0.6, 0.6)
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
        { "food",  Best("food"),              "best food for your level: " },
        { "kit",   Best("kit"),               "best armor kit for your level: " },
        { "boost", BestBoost(),               "best agility elixir or scroll for your level: " },
    }
    for _, c in ipairs(checks) do
        if c[2] and c[2] ~= last[c[1]] then Print(c[3] .. ItemText(c[2])) end
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
        if (db.dataVersion or 1) < 2 then
            for id, info in pairs(db.items) do
                if info == false then db.items[id] = nil end
            end
            db.dataVersion = 2
        end

        isHunter = select(2, UnitClass("player")) == "HUNTER"

        frame:ClearAllPoints()
        if db.pos then
            frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end

        for _, id in ipairs(ns.SEED_KITS) do Classify(id) end
        for _, id in ipairs(ns.SEED_FOOD) do Classify(id) end
        for _, id in ipairs(ns.SEED_BOOSTS) do Classify(id) end
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
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("UNIT_PET")
        self:RegisterEvent("UNIT_HEALTH")
        self:RegisterEvent("PET_UI_UPDATE")
        pcall(self.RegisterEvent, self, "UNIT_HAPPINESS")

        C_Timer.After(5, function()
            last.food, last.kit = Best("food"), Best("kit")
            last.boost = BestBoost()
            Update()
        end)
        Print("loaded. Type /sqa for options.")

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
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        ScanBags()
        QueueUpdate()

    elseif event == "MERCHANT_SHOW" then
        ScanMerchant()
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

local TOGGLE_KEYS = { food = true, kits = true, boost = true, pet = true }

SLASH_SQUAREDAWAY1 = "/sqa"
SLASH_SQUAREDAWAY2 = "/squared"
SlashCmdList.SQUAREDAWAY = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")

    if cmd == "lock" then
        db.locked = true
        Print("icons locked.")
    elseif cmd == "unlock" then
        db.locked = false
        Print("icons unlocked. Drag an icon to move them.")
    elseif cmd == "reset" then
        db.pos = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        Print("position reset.")
    elseif cmd == "config" or cmd == "settings" then
        ToggleSettings()
    elseif cmd == "hide" or cmd == "show" then
        if TOGGLE_KEYS[arg] then
            db.hidden[arg] = (cmd == "hide") or nil
            Print(arg .. " icon " .. (cmd == "hide" and "hidden." or "shown."))
            Update()
        else
            Print("use: /sqa " .. cmd .. " food | kits | boost | pet")
        end
    elseif cmd == "list" then
        local counts = { food = 0, kit = 0, boost = 0 }
        for _, info in pairs(db.items) do
            if info and counts[info.kind] then counts[info.kind] = counts[info.kind] + 1 end
        end
        Print("known: " .. counts.food .. " Well Fed foods, " .. counts.kit .. " armor kits, "
            .. counts.boost .. " agility elixirs/scrolls.")
        local food, kit = Best("food"), Best("kit")
        local boost = BestBoost()
        Print("food: " .. (food and ItemText(food) or "none known yet"))
        Print("armor kit: " .. (kit and ItemText(kit) or "none known yet"))
        Print("elixir or scroll: " .. (boost and ItemText(boost) or "none known yet"))
        local missing, weaker = KitStatus()
        Print("missing kits: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
        Print("weaker kits: " .. (#weaker > 0 and table.concat(weaker, ", ") or "none"))
        Print("Well Fed: " .. (IsWellFed() and "yes" or "no")
            .. ", agility boost: " .. (ActiveBoost() and "yes" or "no"))
        if isHunter then Print("pet: " .. select(2, PetStatus())) end
    else
        Print("commands:")
        Print("  /sqa config  open the settings (or right-click an icon)")
        Print("  /sqa list    what I know and suggest")
        Print("  /sqa hide | show food | kits | boost | pet")
        Print("  /sqa lock | unlock    stop or allow dragging")
        Print("  /sqa reset   move icons back to the middle")
    end
end
