-- Squared Away: settings data (hand-written)
-- The item ID lists (food, kits, elixirs, scrolls) are in ItemData.lua, which
-- tools/build_data.py generates from ForeverDB.net. Every ID is checked in
-- game: an ID that turns out not to be what we need is ignored. New items are
-- also learned automatically when you hover over them, see them at a vendor
-- or carry them in your bags.

local ADDON, ns = ...

-- Which scroll stats count for the scroll icon, the tooltip words that
-- identify them (English, German), and class buffs that already cover the
-- stat (a scroll would not stack with them).
ns.SCROLL_STATS = {
    { key = "stamina",   label = "Stamina",    words = { "stamina", "ausdauer" },
      coveredBy = { 1243, 21562 } },  -- Power Word: Fortitude, Prayer of Fortitude
    { key = "strength",  label = "Strength",   words = { "strength", "stärke" } },
    { key = "armor",     label = "Protection", words = { "armor", "rüstung" } },
    { key = "intellect", label = "Intellect",  words = { "intellect", "intelligenz" },
      coveredBy = { 1459, 23028 } },  -- Arcane Intellect, Arcane Brilliance
}

-- Names of the Well Fed buff (English, German).
ns.WELL_FED_NAMES = {
    ["Well Fed"] = true,
    ["Satt"] = true,
}

-- Icon of the Well Fed buff (file ID and path), as a second way to spot it.
ns.WELL_FED_ICONS = {
    [136000] = true,
    ["interface\\icons\\spell_misc_food"] = true,
}

-- Hunter aspects (rank 1 spell IDs). Their names come from the game in your
-- client language. Any buff starting with "Aspect of" / "Aspekt de" also
-- counts, so new Forever aspects are caught too.
ns.ASPECT_SPELLS = {
    13163, -- Aspect of the Monkey
    13165, -- Aspect of the Hawk
    5118,  -- Aspect of the Cheetah
    13159, -- Aspect of the Pack
    13161, -- Aspect of the Beast
    20043, -- Aspect of the Wild
}

-- Equipment slots that take an armor kit.
ns.KIT_SLOTS = {
    { slot = 5,  label = INVTYPE_CHEST or "Chest" },
    { slot = 7,  label = INVTYPE_LEGS  or "Legs"  },
    { slot = 10, label = INVTYPE_HAND  or "Hands" },
    { slot = 8,  label = INVTYPE_FEET  or "Feet"  },
}
