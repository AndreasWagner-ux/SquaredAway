-- Squared Away: starter data
-- Only item IDs live here. Names, icons and level requirements come from the
-- game itself (in your client language), so nothing here goes out of date.
-- Every ID is checked in game: an ID that turns out not to be Well Fed food,
-- an armor kit or an agility elixir/scroll is ignored. New items are learned automatically when you
-- hover over them, see them at a vendor or carry them in your bags.

local ADDON, ns = ...

-- Armor kits (leatherworking). Forever adds new ones; those are learned in game.
ns.SEED_KITS = {
    2304,   -- Light Armor Kit
    2313,   -- Medium Armor Kit
    4265,   -- Heavy Armor Kit
    8173,   -- Thick Armor Kit
    15564,  -- Rugged Armor Kit
}

-- Cooked food that may give Well Fed (classic IDs, checked in game).
ns.SEED_FOOD = {
    2680,   -- Spiced Wolf Meat
    2684,   -- Coyote Steak
    6888,   -- Herb Baked Egg
    724,    -- Goretusk Liver Pie
    733,    -- Westfall Stew
    12224,  -- Crispy Bat Wing
    1017,   -- Seasoned Wolf Kabob
    1082,   -- Redridge Goulash
    3662,   -- Crocolisk Steak
    3663,   -- Murloc Fin Soup
    3726,   -- Big Bear Steak
    3727,   -- Hot Lion Chops
    3664,   -- Crocolisk Gumbo
    3665,   -- Curiously Tasty Omelet
    3666,   -- Gooey Spider Cake
    3728,   -- Tasty Lion Steak
    3729,   -- Soothing Turtle Bisque
    12209,  -- Lean Wolf Steak
    12210,  -- Roast Raptor
}

-- Agility elixirs and scrolls (for hunters; checked in game).
ns.SEED_BOOSTS = {
    2457,   -- Elixir of Minor Agility
    3390,   -- Elixir of Lesser Agility
    8949,   -- Elixir of Agility
    9187,   -- Elixir of Greater Agility
    3012,   -- Scroll of Agility
    1477,   -- Scroll of Agility II
    4425,   -- Scroll of Agility III
    10309,  -- Scroll of Agility IV
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

-- Equipment slots that take an armor kit.
ns.KIT_SLOTS = {
    { slot = 5,  label = INVTYPE_CHEST or "Chest" },
    { slot = 7,  label = INVTYPE_LEGS  or "Legs"  },
    { slot = 10, label = INVTYPE_HAND  or "Hands" },
    { slot = 8,  label = INVTYPE_FEET  or "Feet"  },
}
