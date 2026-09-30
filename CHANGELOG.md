# Tally changelog

## 0.1.1

- Fixed: clicking the bag counter could freeze the game in gamepad mode. Opening the bags from Tally set off an endless "Tally has been blocked from an action only available to the Blizzard UI" loop in Forever. The counters are now hover-only; open your bags with the controller as usual.

## 0.1.0 — First release

Tally is part of the SNRN addon family.

- **Bag counter** in the bottom-right corner: free slots in bags that hold anything. Quivers, ammo pouches, soul bags and profession bags are listed in the tooltip but not counted. Shown as free, free / total or used / total.
- **Ammo counter**: all ammo of the equipped type in your bags, with its icon. Appears with a bow, gun or crossbow, a quiver or ammo pouch, or ammo equipped; can also be set to always or never. The tooltip shows quiver slots and any other ammo you carry.
- Counts turn yellow when low (configurable) and red at zero.
- Only shown in gamepad mode by default, where Forever's HUD has no bag bar or Shoot button count.
- Crossbar-style round slots. Movable in Edit Mode or when unlocked, side by side or stacked, with a size setting.
- **Settings > AddOns > Tally**, built as a plain canvas with click-to-cycle buttons and no dropdown menus, so Forever's gamepad cursor never touches it.
- Commands under `/tally` for status, unlock, lock, reset and debug output.
