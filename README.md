# Squared Away [Forever]

A small reminder bar for **WoW Forever**. It shows at a glance whether you are ready for the next fight, and what would be good to have at your current level.

> Early version (alpha). Built and tested for a hunter. Other classes and races will follow.

## What it checks

| Icon | Green check | Yellow question mark | Red cross |
|---|---|---|---|
| Food | Well Fed, with minute countdown | | Not Well Fed |
| Armor kits | Kit on chest, legs, hands and feet | A slot has a weaker kit than you could use | A slot has no kit |
| Elixir / scroll | Agility elixir or scroll active, with countdown | | None active |
| Other scrolls | All stat scrolls active (count in the icon, e.g. 4/4) | Some active | None active |
| Pet (hunters) | Summoned and happy | Content | Unhappy, dead or not summoned |

**Aspect reminder (hunters):** while no aspect is active, a flashing "No aspect active!" appears in the middle of the screen, in and out of combat, until you choose one. It stays away while you are dead or on a flight path, and before you have learned your first aspect. Switch it off in the settings or with `/sqa hide aspect`.

Hover over an icon to see the best food, kit or elixir/scroll for your level and how many you carry. An agility elixir and an agility scroll do not stack, so only one of them is suggested.

**Other scrolls:** Stamina, Strength, Protection and Intellect scrolls each give their own buff. The icon counts how many of them are active (for example 2/4), and the tooltip names each missing one and tells you whether you carry a scroll for it. A stat already covered by a class buff (Power Word: Fortitude, Arcane Intellect) counts as done. The icon only appears once you know at least one such scroll.

The icons hide in combat. Squared Away never buys or uses anything. It only reminds you.

## How it knows items

Squared Away starts with a small list of item IDs. Names, icons and level requirements come from the game itself, in your client language. It also learns new food, kits and elixirs by itself whenever you hover over an item, visit a vendor or carry something in your bags.

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
| `/sqa hide food`, `kits`, `boost`, `scrolls`, `pet`, `aspect` | Hide an icon or the aspect reminder (`/sqa show ...` brings it back) |
| `/sqa lock`, `/sqa unlock` | Stop or allow dragging |
| `/sqa reset` | Move the bar back to the middle |

## Known limits

- The weaker-kit check compares armor value only.
- Forever's +XP food is detected by the Well Fed buff name. If your client uses a different name, please open an issue.
- German client: the food check uses the word "satt" from the tooltip.

## Feedback

Found a bug or have an idea? Please open an [issue](https://github.com/AndreasWagner-ux/SquaredAway/issues).

## License

GPL-3.0-or-later. See `LICENSE`.
