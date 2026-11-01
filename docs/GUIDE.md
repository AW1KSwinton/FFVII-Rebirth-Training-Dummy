# Training Dummy — player guide

Three practice courses for Chadley's Combat Simulator, with live meters. Use
them to test a build, compare ability rotations, practise blocking or check
that your healing lands, and repeat the same fight as often as you like.

## What you need

- FINAL FANTASY VII REBIRTH (PC).
- [UE4SS v3](https://github.com/UE4SS-RE/RE-UE4SS) set up for FF7 Rebirth.
  The data pak works without it, but the course names, the dummy's behaviour
  and the meters all come from the UE4SS half.
- A save that has reached Chadley's Combat Simulator (Chapter 2 onwards).

## Install

The game folder below is the one that holds `End/`, for example
`C:\Program Files (x86)\Steam\steamapps\common\FINAL FANTASY VII REBIRTH`.

1. Copy `TrainingDummy_P.pak`, `TrainingDummy_P.ucas` and
   `TrainingDummy_P.utoc` into `End\Content\Paks\~mods\`. Create the `~mods`
   folder if it isn't there.
2. Copy the `TrainingDummy` folder into `End\Binaries\Win64\ue4ss\Mods\`.
3. Open `End\Binaries\Win64\ue4ss\Mods\mods.txt` and add this line above
   `Keybinds : 1`:

   ```text
   TrainingDummy : 1
   ```

4. Start the game.

If you build from source instead, `tools\Build-TrainingDummy.ps1 -Mode Install`
does all of this and keeps a backup (see the README).

## Find the courses

1. Talk to Chadley and choose the Combat Simulator.
2. Open the **Combat Training** tab.
3. Scroll to the bottom of the list. The last three rows are:
   - **Training Dummy: DPS**
   - **Training Dummy: Tank**
   - **Training Dummy: Healing**
4. Pick one, choose your party and confirm **Begin challenge**.

The dummy appears in the middle of the arena and the meters appear at the top
left of the screen.

## The courses

| Course | The dummy | Meters |
| --- | --- | --- |
| DPS | can't be defeated, stands still, never attacks | DPS (damage per second) |
| Tank | can't be defeated, attacks you | DTPS (damage taken per second) per party member, and DPS |
| Healing | can't be hurt, stands still, never attacks | HPS (healing per second) per party member |

### DPS

The dummy has 1,000,000 HP and is topped up whenever it drops below 90%, so
even a 99,999 hit can't defeat it. It still staggers, so you can practise
building pressure and stagger damage. It takes hits like a level 50 enemy.

### Tank

The same unbeatable dummy, but it fights back. Use it to practise blocking,
dodging and Punisher counters, or to see how much damage a build soaks. The
DTPS line lists the damage each party member has taken. The Tank course can
still defeat your party.

The dummy can be pressured and staggered like any enemy, and while it's
staggered it doesn't attack. If your whole party keeps hitting it, or you play
in Classic mode (which attacks automatically), it may hardly fight back. To
practise defence, go in alone and guard or dodge instead of attacking.

### Healing

The dummy is harmless and can't be damaged. Every party member except the one
you control is held at 1 HP. Heal them: the HP bar fills, the HPS meter counts
the healing, and 1.5 seconds later the member drops back to 1 HP, ready for the
next heal. Items can't be used in simulator fights, so heal with spells and
abilities (Cure, Prayer, Chakra and so on).

## Reading the meters

```text
TRAINING DUMMY - Tank   42s   [F7 reset]
DTPS 31  (5s: 54)  total 1,302  biggest 220
   Cloud  870
   Tifa  432
DPS 405  (5s: 512)  total 17,010  biggest 2,377
```

- The first number is the average since the first hit, heal or damage taken.
- **5s** is the rate over the last 5 seconds.
- **total** is everything since the start or the last reset.
- **biggest** is the largest amount measured in one check. The mod checks
  five times a second, so this is usually one hit, but hits landing together
  are added up.
- The names below DTPS and HPS show each party member's share.

The timer starts at the first event, not when the battle loads, so the
averages aren't dragged down by the intro.

| Key | What it does |
| --- | --- |
| F7 | Reset the meters (start a fresh attempt without leaving the fight) |
| F8 | Hide or show the meters |

The meters are also written to `ue4ss\Mods\TrainingDummy\meters.json`
several times a second, for stream overlays or your own tools.

## Using it to test combat

- **Compare two rotations:** run one for 60 seconds, note the DPS, press F7,
  then run the other.
- **Check that a command goes through:** do it on the DPS dummy. The total
  rises when the hit lands; if nothing changes, the command didn't execute.
- **Check that a heal lands:** use the Healing course. Each heal shows on the
  HP bar and in HPS before the patient is dropped back to 1 HP.
- **Restart quickly:** pause, choose **Give Up**, then pick the course again.
  The dummy is never defeated, so this is the only way out of a fight.

## Settings

Edit `ue4ss\Mods\TrainingDummy\Scripts\config.lua`, then restart the game.
Don't use UE4SS hot reload (Ctrl+R): it crashes this game.

| Setting | Default | What it does |
| --- | --- | --- |
| `refill_below_percent` | 90 | Dummy HP percentage that triggers a refill to 100% |
| `stop_dps_dummy` | true | Pin the DPS dummy in place |
| `stop_heal_dummy` | true | Pin the Healing dummy in place |
| `heal_patients` | `"others"` | `"others"`: everyone except you is held at 1 HP; `"all"`: you too |
| `heal_reset_seconds` | 1.5 | How long a healed member keeps their HP before dropping back |
| `rolling_window_seconds` | 5 | Length of the "5s" rate |
| `overlay`, `overlay_x`, `overlay_y` | on, 40, 220 | Show the meters, and where |
| `reset_key`, `toggle_overlay_key` | F7, F8 | Keys |
| `write_json` | true | Write `meters.json` |
| `debug` | false | Log what the mod sees to `UE4SS.log` |

## Troubleshooting

| Problem | Cause and fix |
| --- | --- |
| The three rows at the bottom of the list are blank | The UE4SS half isn't running. Check the `TrainingDummy` folder location and the `mods.txt` line. |
| No courses at all | The pak isn't loaded: check the three files are in `~mods`. The simulator must also be unlocked. |
| Every simulator battle hangs on the white fade | Another mod replaces the same simulator tables. Remove one of them. |
| The dummy dies, or no meters appear | The UE4SS half isn't running (see the first row). |
| The game crashed after editing the config | Hot reload (Ctrl+R) crashes the game. Restart it instead. |

Other mods that replace `Colosseum`, `ColosseumPositionData`,
`EnemyTerritory`, `EnemyTerritoryLevel` or `EnemyParameter` conflict with this
one, VR Simulator Overhaul among them.

## Uninstall

Delete the three `TrainingDummy_P` files from `~mods`, delete the
`TrainingDummy` folder from `ue4ss\Mods`, and remove its line from
`mods.txt`. The mod doesn't touch your saves.

## Limits

- Overkill damage isn't counted: the meters measure HP lost, so damage beyond
  the dummy's remaining HP is missed. With 1,000,000 HP and a 90% refill this
  only matters for hits over 100,000, which the game doesn't allow.
- The dummy uses the simulator's Ogre model.
- How it was made: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
