# Maelstrom Tracker

A small, lightweight tracker for the shaman Maelstrom Weapon buff in WoW Classic Forever, in the style of a WeakAura.

A movable icon shows your current Maelstrom Weapon stacks. At 5 stacks a glow ring around the icon blinks slowly, so you never miss an instant spell. You can also turn on a glow around the edges of the screen at 5 stacks.

WoW Forever hides buff information from addons during combat. Maelstrom Tracker works around this by letting the game draw the buff itself: the icon, stack count, duration sweep and 5-stack glows are handed to the game's own aura display, so they stay accurate in combat.

Available on [CurseForge](https://www.curseforge.com/projects/1795373).

## Features

- Shows your Maelstrom Weapon stack count, with a duration sweep
- Blinking glow ring at 5 stacks
- Optional glow around the edges of the screen at 5 stacks
- Drag the icon anywhere on screen, or lock it in place
- Adjustable scale and opacity
- Custom colors for the icon glow and the screen glow
- Adjustable screen glow depth and strength
- Option to hide the icon when you have no stacks
- Only loads on shaman characters

## Usage

Open the settings with `/mwt`.

- **Icon:** show with no stacks, lock position, glow on/off, glow color, opacity and scale.
- **Screen edge glow:** on/off, color, depth and strength.

Drag the icon with the left mouse button to move it, unless it's locked.

Other commands:

- `/mwt lock` / `/mwt unlock`
- `/mwt reset` moves the icon back to its default position.
- `/mwt debug` prints what the addon currently sees.

## Notes

- Only loads on shaman characters.
- `tools/make_glow.py` regenerates the glow texture (`MaelstromTracker/Media/glow.tga`).
