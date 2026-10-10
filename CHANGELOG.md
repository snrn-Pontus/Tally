# Tally changelog

## 0.4.1

- Fixed: a soul bag in the fifth bag slot counted as free bag space. Tally took any bag past the fourth slot for a reagent bag; it now checks the bag itself. Soul bags are also recognised when the game reports them as plain bags.

## 0.4.0

- **The disenchant counter is always shown** with Enchanting learned, greyed out at 0, so it is there the moment loot comes in.
- **Shift-click disenchants bind-on-equip greens** once no soulbound gear is left, to free bag space quickly in a dungeon. They are counted on the counter and listed in the tooltip; a plain click never disenchants them. Bind-on-equip blue and purple items are still left alone.

## 0.3.1

- Fixed: a soul bag could count as free bag space when the game reported it as a bag that holds anything. Tally now also checks the bag item itself, so soul and other profession bags stay out of the bag counter.

## 0.3.0

- **Profession bags get their own counter.** Herb, enchanting, soul and other profession bags each show a counter with the bag's icon, so you can see your herb bag has room even when your bags are full. They are still left out of the bag counter. **Own counter for profession bags** turns it off.
- **Disenchant from a counter.** With Enchanting learned, a disenchant counter shows your soulbound green, blue and purple weapons and armor. Click it to disenchant soulbound gear you can never wear (another class's item, or an armor or weapon type your class never learns); gear you could wear, now or after leveling or training a proficiency, takes a shift-click. Right-click always keeps the item. Bind-on-equip and account-bound items are never offered.
- Tally works out whether a disenchant frees a bag slot: every material the item can give (by Classic item level) has to stack with what you carry, or fit in a free enchanting bag slot. With bags at or below the yellow warning only those items are offered; otherwise any soulbound item is, slot-freeing ones first.
- Upgrades are never disenchanted: items with a higher item level than what you wear in their slot (or for an empty slot), or Pawn's upgrade arrow when Pawn is installed. Items you cannot wear don't count. The tooltip lists what was held back; **Never disenchant upgrades** turns it off.
- The counter uses a secure button out of combat only, so the counters still move freely in combat. **Show disenchant counter** turns it off.

## 0.2.0

- Fixed: a phantom ammo counter with a "?" icon, "item:0" and a count of 1 showed with no ammo equipped. Only arrows and bullets in the ammo slot count as equipped ammo now. Empty bag slots are no longer listed in the bag tooltip either.
- **Reagent bags can have their own counter.** Set **Reagent bags** to **Own counter per bag** and each reagent bag gets a counter with its icon, left out of the bag counter. The default still counts them with your bags; either way the tooltip marks them as reagent bags.
- **Delete your cheapest grey item from the bag counter.** The bag tooltip names the grey item worth the least at a vendor. Click the counter and the tooltip asks to delete it; click again to delete it, or move away to cancel. No bags or popups are opened, so the gamepad freeze from 0.1.0 cannot come back. Can be turned off in the settings.
- Optionally include white items: the cheapest grey or white item is offered. Grey or white, ammo, quest items (including grey quest starters), keys and items a vendor will not buy are never offered.
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
