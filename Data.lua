-- Squared Away: starter data
-- Only item IDs live here. Names, icons and level requirements come from the
-- game itself (in your client language), so nothing here goes out of date.
-- Every ID is checked in game: an ID that turns out not to be Well Fed food,
-- an armor kit or an agility elixir/scroll is ignored. New items are learned
-- automatically when you hover over them, see them at a vendor or carry them
-- in your bags.

local ADDON, ns = ...

-- Armor kits (leatherworking).
ns.SEED_KITS = {
    -- Classic kits (some changed in Forever)
    2304,   -- Light Armor Kit
    2313,   -- Medium Armor Kit
    4265,   -- Heavy Armor Kit
    8173,   -- Thick Armor Kit
    15564,  -- Rugged Armor Kit
    18251,  -- Core Armor Kit
    -- New in Forever: Forceful (attack power) and Mystic (spell power)
    252437, -- Forceful Medium Armor Kit
    252436, -- Mystic Medium Armor Kit
    252453, -- Forceful Heavy Armor Kit
    252452, -- Mystic Heavy Armor Kit
    252463, -- Forceful Thick Armor Kit
    252462, -- Mystic Thick Armor Kit
    252488, -- Forceful Rugged Armor Kit
    252487, -- Mystic Rugged Armor Kit
    279258, -- Wild Leather Armor Kit
}

-- Minimum item level of the gear a kit can be put on (Forever kits).
-- Kits not listed here are read from their tooltip.
ns.KIT_MIN_ILVL = {
    [252453] = 15, [252452] = 15,  -- Heavy
    [252463] = 25, [252462] = 25,  -- Thick
    [252488] = 35, [252487] = 35,  -- Rugged
    [279258] = 45,                 -- Wild Leather
}

-- Cooked food that may give Well Fed (checked in game).
ns.SEED_FOOD = {
    -- Classic
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
    13928,  -- Grilled Squid (crit)
    13934,  -- Mightfish Steak (attack power)
    21023,  -- Dirge's Kickin' Chimaerok Chops (stamina)
    -- New in Forever
    263509, -- Skywall Souffle (stamina)
    250080, -- Breakfast Omelette (stamina)
    250078, -- Giant Scrambled Eggs (stamina)
    250068, -- Savory Turtle Stew (stamina)
    286152, -- Plated Armorfish (armor)
    250069, -- Flank au Poivre (agility)
    250072, -- Swiftstrike Steak (agility)
}

-- Agility elixirs and scrolls (for hunters; checked in game).
ns.SEED_BOOSTS = {
    2457,   -- Elixir of Minor Agility
    3390,   -- Elixir of Lesser Agility
    8949,   -- Elixir of Agility
    9187,   -- Elixir of Greater Agility
    13452,  -- Elixir of the Mongoose
    250328, -- Elixir of Cunning (new in Forever)
    3012,   -- Scroll of Agility
    1477,   -- Scroll of Agility II
    4425,   -- Scroll of Agility III
    10309,  -- Scroll of Agility IV
}

-- Other stat scrolls (checked in game). Agility scrolls are
-- in SEED_BOOSTS, because they do not stack with agility elixirs.
ns.SEED_SCROLLS = {
    1180, 1711, 4422, 10307,  -- Scroll of Stamina I-IV
    954,  2289, 4426, 10310,  -- Scroll of Strength I-IV (melee attack power)
    3013, 1478, 4421, 10305,  -- Scroll of Protection I-IV
    955,  2290, 4419, 10308,  -- Scroll of Intellect I-IV
}

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
