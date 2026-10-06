# SNRN Tally

**Free bag slots and ammo on WoW: Forever's gamepad HUD.**

In gamepad mode the crossbar replaces the bag bar and the Shoot button, so nothing on screen tells you your bags are full or you are about to run out of arrows. Tally puts both numbers in the bottom-right corner, in the same round-slot style as the crossbar.

## What's new

- **0.3.1**: Fixed a soul bag counting as free bag space.
- **0.3.0**: A disenchant counter for enchanters. Click to disenchant soulbound gear you can never wear, shift-click for gear you could; upgrades are never touched, and with full bags it only offers disenchants that free a slot. Herb, enchanting, soul and other profession bags get a counter of their own.
- **0.2.0**: Click the bag counter to delete your cheapest grey item, confirmed in the tooltip. Reagent bags can get their own counter. Fixed a phantom "?" ammo counter with no ammo equipped.
- **0.1.1**: Clicking the bag counter no longer freezes the game in gamepad mode. The counters are hover-only now.
- **0.1.0**: First release.

Full history on the Changelog tab of each file.

![The bag and ammo counters with the bag tooltip: free slots per bag, quiver and herb pouch left out](https://media.forgecdn.net/attachments/1997/349/bags-tooltip-png.png)

## What you get

| Counter | Shows |
| --- | --- |
| Bags | Free slots in your backpack and normal bags |
| Profession bag | Free slots in a herb, enchanting, soul or other profession bag, with its icon |
| Disenchant | Soulbound gear you can disenchant, when you know Enchanting |
| Ammo | Every arrow or bullet of the equipped type in your bags |

- Yellow when low, red at zero. Both thresholds are yours to set.
- Quivers, ammo pouches and other special bags don't count as free space, because loot can't go there. Profession bags show their own free slots instead, so you can see your herb bag still has room when your bags are full.
- The ammo counter only appears for characters who use ammo: a bow, gun or crossbow, a quiver or ammo pouch, or ammo equipped.
- Hover for free slots per bag, quiver slots and any other ammo you carry.
- Reagent bags are counted with your bags, or get a counter of their own.

## Delete greys

The bag tooltip names your cheapest grey item. Click the bag counter and the tooltip asks to delete it; click again to delete it, or move away to cancel. No bags or popups open, so it is safe in gamepad mode.

- Optionally include white items, with trade goods, consumables, reagents and recipes kept by default.
- Quest items, ammo, keys and anything a vendor won't buy are never offered.
- Right-click to always keep an item; `/tally keep` manages the list.
- With Auctionator, TradeSkillMaster or Auctioneer installed, greys that sell well on the auction house are not the ones offered.

## Disenchant

With Enchanting learned, a counter shows the soulbound green, blue and purple weapons and armor you can disenchant. Hover it to see what a click would do.

- **Click** disenchants gear you can never wear: another class's item, or an armor or weapon type your class never learns.
- **Shift-click** disenchants gear you could wear, now or after leveling or training. The modifier keeps it from happening by accident.
- **Upgrades are never offered**: Pawn's upgrade arrow when Pawn is installed, otherwise item level against what you wear.
- Bind-on-equip, account-bound and "Cannot be disenchanted" items are never offered. Right-click to always keep an item.
- When your bags are nearly full, only disenchants whose every possible material stacks with yours (or fits in an enchanting bag) are offered, so each one frees a slot.

## Setup

Nothing to do. Switch to gamepad mode and the counters appear in the bottom-right corner. Move them in Edit Mode, or with `/tally unlock`.

![The ammo tooltip: arrows left in your bags and free quiver slots](https://media.forgecdn.net/attachments/1997/351/ammo-tooltip-png.png)

## Settings

**Settings > AddOns > Tally** (or `/tally`): what to show, how to show bag slots (free, free / total, used / total), when to turn yellow, gamepad-only or always, side by side or stacked, and size.

![The Tally settings page](https://media.forgecdn.net/attachments/1997/350/settings-png.png)

## Works with a controller

The counters only show in gamepad mode by default. The Settings page is built so WoW: Forever's gamepad cursor never touches it, which avoids the client freezing when Settings is closed with the controller.

## Slash commands

```
/tally           open the settings page
/tally status    bag slots per bag and ammo, in chat
/tally unlock    move the counters outside Edit Mode
/tally lock      lock them again
/tally reset     back to the bottom-right corner
/tally keep      list, add or remove items never offered for deletion or disenchanting
```

## Notes

- Built for **World of Warcraft: Forever**. It only uses standard bag and inventory APIs, so it should also work on other clients that have them.

## Part of the SNRN family

- **[SNRN Rummage](https://www.curseforge.com/wow/addons/snrn-rummage)**: one action slot per item type that always uses the best food, drink, potion, bandage or quest item in your bags. Tally tells you when your bags are full; Rummage makes sure the right stack gets used.
- **[SNRN Backhand](https://www.curseforge.com/wow/addons/snrn-backhand)**: four extra action slots for your controller's rear paddles (Xbox Elite, DualSense Edge, Steam Input back buttons), built into Forever's native crossbar.
- **[SNRN Valet](https://www.curseforge.com/wow/addons/snrn-valet)**: sells greys and repairs at merchants, collects your mail, and declines duels, guild invites and charters. Greys you keep with Tally are not sold.
- **[SNRN Grimoire](https://www.curseforge.com/wow/addons/snrn-grimoire)**: one command lays out an Affliction Warlock on Forever's gamepad crossbar and Backhand's paddles.

## Reporting problems

Run `/tally status` and include the output with your report.
