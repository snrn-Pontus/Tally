# Tally

Free bag slots and ammo count in the bottom-right corner, for **WoW: Forever**'s gamepad HUD. The gamepad crossbar replaces the bag bar and the Shoot button, so in gamepad mode nothing on screen tells you how full your bags are or how many arrows you have left. Tally puts both numbers back.

Tally is part of the SNRN addon family, next to [Rummage](https://github.com/snrn-Pontus/Rummage) and [Backhand](https://github.com/snrn-Pontus/Backhand).

<!-- Screenshot: the counters in the bottom-right corner. -->

Built for **World of Warcraft: Forever** (Interface 16001). It only uses standard bag and inventory APIs, so it should also work on other clients that have them.

## The counters

Each counter is a round slot in the style of the crossbar with the number beside it.

| Counter | Shows |
| --- | --- |
| Bags | Free slots in bags that hold anything (backpack and normal bags) |
| Ammo | Every arrow or bullet of the equipped ammo type in your bags |

- The number turns **yellow** when it gets low (4 free slots, 200 ammo by default) and **red** at zero.
- Quivers, ammo pouches, soul bags and profession bags are not counted as free bag slots: loot cannot go there. The bag tooltip still lists them.
- The ammo counter appears when you have a bow, gun or crossbow, a quiver or ammo pouch, or ammo equipped. It shows the equipped ammo's icon.
- Hover a counter for the details: free slots per bag, quiver slots, and any other ammo in your bags.

## Gamepad mode only

By default the counters only show in gamepad mode, since mouse-and-keyboard mode already has the bag bar and the Shoot button count. Untick **Only show in gamepad mode** to always show them. They are also shown while you move them.

## Moving them

Open WoW's Edit Mode, or tick **Unlock counters outside Edit Mode** in the settings (`/tally unlock`), and drag. The position is saved from the bottom-right corner, so the counters grow leftward (side by side) or upward (stacked) from wherever you drop them. `/tally reset` puts them back in the corner.

## Settings page

**Settings > AddOns > Tally** (or `/tally`):

- Show free bag slots, and as: free (23), free / total (23/80) or used / total (57/80)
- Yellow at free slots
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
/tally debug     toggle debug output
```

## Gamepad note

Forever hangs when the Settings window is closed with the controller after the gamepad cursor has visited addon-created controls, and Blizzard's standard settings list triggers that by itself. The Tally settings page is therefore a canvas built once at login from plain checkboxes and buttons, never handed to the gamepad cursor, and it opens no dropdown menus. With a controller, use the mouse on that page.

## License

MIT.
