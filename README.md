# Squared Away [Forever]

A small reminder bar for **WoW Forever**. It shows at a glance whether you are ready for the next fight, and what would be good to have at your current level.

> Early version (alpha). Built and tested for a hunter. Other classes and races will follow.

## What it checks

| Icon | Green check | Yellow question mark | Red cross |
|---|---|---|---|
| Food | Well Fed, with minute countdown | | Not Well Fed |
| Armor kits | Kit on chest, legs, hands and feet | A slot has a weaker kit than you could use | A slot has no kit |
| Agility (elixir or scroll) | Agility elixir or scroll active, with countdown | | None active |
| Stat buffs | Stamina, Strength, Armor and Intellect all covered by a scroll or elixir (count in the icon, e.g. 4/4) | Some active | None active |
| Ammo (bow, crossbow, gun) | Quiver at least half full (count in the icon) | Under half full | Under 200, or under 15% |
| Pet (hunters) | Summoned and happy | Content | Unhappy, dead or not summoned |

**Aspect reminder (hunters):** while no aspect is active, a flashing "No aspect active!" appears in the middle of the screen, in and out of combat, until you choose one. It stays away while you are dead or on a flight path, and before you have learned your first aspect. Switch it off in the settings or with `/sqa hide aspect`.

**Ammo:** the icon shows how many arrows or bullets you carry and how full your quiver or ammo pouch is. Hover it for the ammo you use, its damage per second, and better ammo for your level. At a vendor that sells ammo for your weapon, the icon shows **+N**: left-click it to buy the best ammo the vendor has for your level, enough to fill the free quiver slots (whole stacks, never more than your gold allows). If the vendor only has weaker ammo than the ammo you shoot, a window explains it and lets you buy it anyway, so you do not run out in the wild. Without a quiver the icon turns yellow and switches every 2 seconds between the count and "No quiver"; two stacks in your bags then count as full. `/sqa ammo 4` carries 4 stacks instead, `/sqa ammo 0` fills the quiver again.

Agility scrolls and elixirs are not part of the stat buffs icon: they share the agility icon with agility elixirs, because the two do not stack.

Hover over an icon to see the best food, kit or elixir/scroll for your level and how many you carry. An agility elixir and an agility scroll do not stack, so only one of them is suggested.

**Stat buffs:** one slot each for Stamina, Strength, Armor and Intellect, filled by a scroll or an elixir (for example Scroll of Stamina or Elixir of Fortitude; health elixirs count as stamina, 10 health = 1 stamina). The icon counts how many are covered (for example 2/4), and the tooltip names each missing one and tells you whether you carry something for it. Elixirs that raise two stats, like Elixir of the Phalanx, count for both. A stat already covered by a class buff (Power Word: Fortitude, Arcane Intellect) counts as done.

**Sharpening stone (off by default):** for your melee weapon only. Shows whether a sharpening stone or weightstone is on your main hand weapon, with a countdown, and suggests the best one for your weapon and level. Switch it on in the settings or with `/sqa show stone`.

The icons hide in combat. Squared Away never buys or uses anything by itself. The only purchase happens when you left-click the ammo icon at a vendor.

## Languages

Squared Away shows its texts in English or German, depending on your client language. Item names, icons and tooltips always come from the game in your language.

Items and buffs are recognised by their item and spell IDs from ForeverDB, so the checks work in every client language. Only items the addon learns by itself (not in the ForeverDB lists) are read from their tooltip text, which works in English and German.

Want another language? Copy the German block in `Locales.lua`, translate the right side, and open a pull request or an issue.

## How it knows items

Squared Away starts with a list of item IDs from ForeverDB.net (food, armor kits, elixirs and scrolls). Names, icons and level requirements come from the game itself, in your client language. It also learns new food, kits and elixirs by itself whenever you hover over an item, visit a vendor or carry something in your bags.

## Installation

1. Download `SquaredAway.zip` from the [Releases](https://github.com/AndreasWagner-ux/SquaredAway/releases) page.
2. Unzip it into your WoW Forever addon folder, so you get `Interface\AddOns\SquaredAway\SquaredAway.toc`.
3. Start the game or type `/reload`.

## Usage

- **Move the bar:** left-click and hold an icon, then drag.
- **Settings:** right-click an icon (show or hide icons, lock the bar, reset the position).
- **Database:** shift + right-click an icon, the "Database" button in the settings, or `/sqa db`. Lists all known food, armor kits and elixirs/scrolls sorted by level. The current suggestion has a check mark, items for higher levels are greyed out, and your bag count is shown. Hover a row for the item tooltip, shift-click it to link the item in chat.

Commands:

| Command | What it does |
|---|---|
| `/sqa config` | Open the settings |
| `/sqa list` | Show what the addon knows and suggests |
| `/sqa db` | Open the database (`/sqa db food`, `kits`, `boost` or `scrolls` opens that list) |
| `/sqa hide food`, `kits`, `boost`, `scrolls`, `ammo`, `stone`, `pet`, `aspect` | Hide an icon or the aspect reminder (`/sqa show ...` brings it back) |
| `/sqa ammo N` | Carry N stacks of ammo (0 = fill the quiver) |
| `/sqa lock`, `/sqa unlock` | Stop or allow dragging |
| `/sqa reset` | Move the bar back to the middle |

## Known limits

- The weaker-kit check compares armor value only.
- Forever's +XP food is detected by the Well Fed buff name. If your client uses a different name, please open an issue.
- German client: the food check uses the word "satt" from the tooltip.

## Feedback

Found a bug or have an idea? Please open an [issue](https://github.com/AndreasWagner-ux/SquaredAway/issues).

## Credits

Item data from [ForeverDB.net](https://foreverdb.net). The item ID lists in `ItemData.lua` are generated with `tools/build_data.py` from the ForeverDB API. ForeverDB is not affiliated with Blizzard Entertainment.

## License

GPL-3.0-or-later. See `LICENSE`.
