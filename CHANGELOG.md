# Changelog

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
