# Tally

Free bag slots and ammo count in the bottom-right corner, for **WoW: Forever**'s gamepad HUD. The gamepad crossbar replaces the bag bar and the Shoot button, so in gamepad mode nothing on screen tells you how full your bags are or how many arrows you have left. Tally puts both numbers back.

Tally is part of the SNRN addon family, next to [Rummage](https://github.com/snrn-Pontus/Rummage), [Backhand](https://github.com/snrn-Pontus/Backhand), [Valet](https://github.com/snrn-Pontus/Valet) and [Grimoire](https://github.com/snrn-Pontus/Grimoire).

<!-- Screenshot: the counters in the bottom-right corner. -->

Built for **World of Warcraft: Forever** (Interface 16001). It only uses standard bag and inventory APIs, so it should also work on other clients that have them.

## The counters

Each counter is a round slot in the style of the crossbar with the number beside it.

| Counter | Shows |
| --- | --- |
| Bags | Free slots in bags that hold anything (backpack and normal bags) |
| Reagent bag | Free slots in one reagent bag, when **Reagent bags** is set to **Own counter per bag** |
| Profession bag | Free slots in one herb, enchanting, soul or other profession bag, with the bag's icon |
| Disenchant | Soulbound items you can disenchant, when you know Disenchant |
| Ammo | Every arrow or bullet of the equipped ammo type in your bags |

- The number turns **yellow** when it gets low (4 free slots, 200 ammo by default) and **red** at zero.
- Quivers, ammo pouches, soul bags and profession bags are not counted as free bag slots: loot cannot go there. The bag tooltip still lists them.
- Reagent bags are counted with your bags by default and marked "reagents" in the tooltip. Set **Reagent bags** to **Own counter per bag** to leave them out of the bag counter and give each reagent bag its own counter, with that bag's icon.
- Herb, enchanting, soul and other profession bags each get their own counter with the bag's icon, so you can see your herb bag still has room when your bags are full. Untick **Own counter for profession bags** to only list them in the bag tooltip.
- Empty bag slots are not listed.
- The ammo counter appears when you have a bow, gun or crossbow, a quiver or ammo pouch, or ammo equipped. It shows the equipped ammo's icon.
- Hover a counter for the details: free slots per bag, quiver slots, and any other ammo in your bags.

## Deleting greys

The bag tooltip also names your cheapest grey item: the one worth the least at a vendor (price times stack size). Click the bag counter and the tooltip asks whether to delete it; click again to delete it, or move the pointer away to cancel. The question is asked in the tooltip rather than a popup, because Tally never opens Blizzard windows from a click (see the gamepad note). Untick **Click the bag counter to delete greys** to turn it off.

Tick **Include white items** to let white items compete too: the cheapest grey or white item is offered. Whether grey or white, ammo, quest items (including grey quest starters), keys and anything a vendor will not buy (such as your Hearthstone) are never offered.

With white items included, more is kept for you to sell or use instead:

- **Keep trade goods, consumables, reagents and recipes**: one setting each, all on by default. Cloth, herbs, ore, food, drink, potions, class reagents and so on are never offered.
- **Keep whites worth**: never offer a white stack worth this much or more (1 silver to 5 gold, off by default), counting the auction price when it is known.

Any item, grey or white, can also be kept for good: right-click the bag counter and the item it offers is never offered again. `/tally keep` lists kept items, `/tally keep <item>` adds or removes one (shift-click it into chat), and `/tally keep clear` or the settings page forgets them all.

If **Auctionator**, **TradeSkillMaster** or **Auctioneer** is installed, a grey is worth the higher of its vendor and auction price, so a grey that sells well on the auction house is not the one offered. The tooltip names the addon when its price was used. None of them is required; set **Value greys by** to **Vendor price** to ignore them.

## Disenchanting

With Enchanting learned, a disenchant counter shows how many soulbound green, blue and purple weapons and armor are in your bags. Bind-on-equip and account-bound items are left alone, since they can still be sold or used by another character. Hover it to see what a click would disenchant:

- **Click** disenchants soulbound gear you can never wear: another class's item, or an armor or weapon type your class never learns (plate on a rogue, a wand on a warrior). It is only good for materials, so there is no confirmation.
- **Shift-click** disenchants gear you could wear, now or later: once you reach its level, or train its proficiency (mail or plate at 40, a weapon skill from a weapon master). The modifier keeps that from happening by accident.
- **Right-click** (or shift-right-click) always keeps that item instead, on the same keep list as greys.

Disenchanting frees the item's slot, but the materials need a slot too unless they stack with ones you already carry. Tally knows what Classic gear most likely disenchants into (dust for armor, essence for weapons, shards for rare items, by item level) and checks whether your stacks have room for it:

- **Bags not tight** (more free slots than **Yellow at free slots**): every soulbound item counts. Items that free a slot are offered first, then the one worth least at a vendor.
- **Bags getting full**: only items whose every possible result (dust, essence or shard for green gear; shard or Nexus Crystal for blue and purple) stacks with yours count, so every disenchant frees a slot. A free slot in an enchanting bag counts too, since the materials can go there.

Gear better than what you wear is never offered: with **Never disenchant upgrades** on (the default), an item counts as an upgrade when it has a higher item level than the weakest item in its slot (both rings, both trinkets), or that slot is empty. With **Pawn** installed, Pawn's upgrade arrow decides instead. Items you cannot wear (red text on the tooltip: wrong armor type, class or level) are never upgrades. The tooltip lists the items held back and why.

The tooltip says which material is likely and whether it frees a slot. Items past the Classic item levels have no known result and are only offered while space is no issue.

Casting a spell needs a secure button, so the counter has one laid over it out of combat. It is put away when combat starts (disenchanting waits until you leave combat), so the counters can still move in combat. Untick **Show disenchant counter** to turn it off.

## Gamepad mode only

By default the counters only show in gamepad mode, since mouse-and-keyboard mode already has the bag bar and the Shoot button count. Untick **Only show in gamepad mode** to always show them. They are also shown while you move them.

## Moving them

Open WoW's Edit Mode, or tick **Unlock counters outside Edit Mode** in the settings (`/tally unlock`), and drag. The position is saved from the bottom-right corner, so the counters grow leftward (side by side) or upward (stacked) from wherever you drop them. `/tally reset` puts them back in the corner.

## Settings page

**Settings > AddOns > Tally** (or `/tally`):

- Show free bag slots, and as: free (23), free / total (23/80) or used / total (57/80)
- Reagent bags: with your bags, or an own counter per bag
- Own counter for profession bags
- Yellow at free slots
- Click the bag counter to delete greys
- Include white items, and keep trade goods, consumables, reagents and recipes
- Keep whites worth
- Forget kept items
- Value greys by: auction price when known, or vendor price
- Show disenchant counter, and never disenchant upgrades
- Show ammo: with a ranged weapon or quiver, always or never
- Yellow at ammo
- Only show in gamepad mode
- Unlock counters outside Edit Mode
- Layout: side by side or stacked
- Size
- Back to bottom-right corner
- Debug output

Every choice is a click-to-cycle button (left-click next, right-click previous); see the gamepad note below.

## Commands

```
/tally           open the settings page
/tally status    print bag slots per bag and ammo in chat
/tally unlock    move the counters outside Edit Mode
/tally lock      lock them again
/tally reset     back to the bottom-right corner
/tally keep      list items never offered for deletion or disenchanting
/tally keep <item>  keep an item, or stop keeping it (shift-click it into chat)
/tally keep clear   forget all kept items
/tally debug     toggle debug output
```

## Gamepad note

Forever hangs when the Settings window is closed with the controller after the gamepad cursor has visited addon-created controls, and Blizzard's standard settings list triggers that by itself. The Tally settings page is therefore a canvas built once at login from plain checkboxes and buttons, never handed to the gamepad cursor, and it opens no dropdown menus. With a controller, use the mouse on that page.

## License

MIT.
