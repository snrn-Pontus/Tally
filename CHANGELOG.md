# Tally changelog

## Unreleased

- Fixed: a phantom ammo counter with a "?" icon, "item:0" and a count of 1 showed with no ammo equipped. Only arrows and bullets in the ammo slot count as equipped ammo now. Empty bag slots are no longer listed in the bag tooltip either.
- **Reagent bags can have their own counter.** Set **Reagent bags** to **Own counter per bag** and each reagent bag gets a counter with its icon, left out of the bag counter. The default still counts them with your bags; either way the tooltip marks them as reagent bags.

- **Delete your cheapest grey item from the bag counter.** The bag tooltip names the grey item worth the least at a vendor. Click the counter and the tooltip asks to delete it; click again to delete it, or move away to cancel. No bags or popups are opened, so the gamepad freeze from 0.1.0 cannot come back. Can be turned off in the settings.
- Optionally include white items: the cheapest grey or white item is offered. Ammo, quest items, keys and items a vendor will not buy are never offered.
- With white items included, trade goods, consumables, reagents and recipes are kept by default (one setting each), and white stacks worth at least a set amount can be kept too.
- Right-click the bag counter to always keep the item it offers. `/tally keep` lists, adds and removes kept items.
- Greys can be valued by auction price from Auctionator, TradeSkillMaster or Auctioneer when one is installed (the higher of vendor and auction price counts). Optional; set **Value greys by** to **Vendor price** to ignore them.

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
