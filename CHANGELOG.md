# Changelog

## v1.2.2

- Sound at 5 stacks, chosen in the settings (`/mwt`) from a searchable list of every game sound, or None. A Play button previews it.
- The sound is triggered by the game's spell activation overlay (the 5-stack proc art and Lightning Bolt glow), which addons may read in combat.
- `/mwt events` logs the overlay events, to check what the game sends.

## v1.2.1

- Fixed: the stack count stopped counting up in combat in v1.2.0.
- Removed the 5-stack sound added in v1.2.0.

## v1.2.0

- Added a sound at 5 stacks. It broke the stack count in combat.

## v1.1.0

- Stacks are now drawn by the game's own aura display (Blizzard_AuraContainer), so the count, duration sweep and 5-stack glows are exact in combat.
- Removed the Lightning Bolt cast-time workaround, along with talent detection, calibration and `/mwt recalibrate`.
- The duration sweep now also shows in combat.
- No more polling.

## v1.0.0

- Initial release.
- Movable icon showing Maelstrom Weapon stacks, with a duration sweep out of combat.
- Glow ring that blinks slowly at 5 stacks, plus an optional screen edge glow.
- Tracks stacks in combat through Lightning Bolt's cast time, scaled by Maelstrom Weapon talent points and calibrated out of combat.
- Settings window (`/mwt`): visibility with no stacks, lock, opacity, scale, glow colors, and screen glow depth and strength.
