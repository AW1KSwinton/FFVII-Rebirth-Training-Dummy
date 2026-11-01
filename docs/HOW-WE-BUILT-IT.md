# How we built the Training Dummy mod

This is the story of the build, step by step, including the dead ends, so you
can follow the same path for your own simulator or DataObject mods. For the
finished design in reference form, see [HOW-IT-WORKS.md](HOW-IT-WORKS.md); to
install and play, see [GUIDE.md](GUIDE.md).

The mod was built in Claude Code (Claude Opus 5.5), with the channel owner
setting the goals and checking the results. Claude drove the game itself
through our test harness to try each build.

## Why

In one of our gameplay videos, some combat commands didn't go through. Testing
that meant finding a fight, playing it and hoping the same situation came up
again. We wanted a fight we could replay instantly, as often as we liked, with
numbers on screen: a training dummy, like the ones in MMOs.

The brief had three courses:

- **DPS:** can't be killed, does no damage.
- **Tank:** can't be killed, does damage.
- **Healing:** does no damage, takes no damage, sits at 1 HP and can be healed.

Plus DPS / HPS meters, and ideally dummies that don't move.

## Tools

| Tool | Used for |
| --- | --- |
| [FModel](https://fmodel.app) | Exporting the game's DataObject tables |
| LordGregory's FF7R2 DataObject parser, Yoraiz0r's Data Object Editor | Reading and writing those tables in v1.0.0 (replaced in v1.1.0, see step 10) |
| UnrealReZen | Packing the IoStore pak (`.pak`/`.ucas`/`.utoc`) |
| [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) v3 | Running Lua inside the game |
| .NET 8, PowerShell, Python | The builder, the install script and the tests |

## Step 1: see what's already possible

We started on Nexus Mods. NSK01's **VR Simulator Overhaul** showed the most
useful fact: the Combat Simulator is driven by data, not code. Its courses are
rows in a table, so new courses shouldn't need any Blueprint work. It also
repurposes existing rows instead of adding new ones, which turned out to
matter later.

## Step 2: read how a course is defined

We exported `DataObject/Resident/Colosseum` and its neighbours with FModel. One
course is one `Colosseum` row, which points at:

- an **enemy territory** per round (`EnemyTerritory`, `EnemyTerritoryLevel`):
  which mob templates spawn, at what level, with which field AI (`Stay` keeps
  them in place);
- **spawn positions** (`ColosseumPositionData`);
- its tab, party size, unlock flags, rewards, music and title text.

So the plan was simple: clone a course row, point it at a dummy territory,
and repeat three times.

## Step 3: teach the parser to add rows

The parser could change values but not add rows: new rows silently vanished on
save. DataObject tables are UE4 "frozen" memory images, and the rows sit in a
frozen hash map (`TMap<FName, int32>`): a key array, a bucket array, then the
row data. A new row needs a key, its data and a link in the right bucket.

The hard part was the bucket. We worked it out from the shipped tables:

> bucket = (CityHash64 of the **lowercase** row name + the FName number),
> masked to the bucket count

That rule matched all 1,010 keys we checked across three tables, so we ported
CityHash64 and wrote `tools/DataBuilder`. One more catch: the parser keeps the
original offsets of the bucket, data and entry arrays, so after adding rows
those pointers are wrong and the game can't reload the file. The builder now
saves twice: once to lay the file out, then again with the three pointers
fixed. Every build reloads its own output and checks that each new row has the
requested values and that every vanilla row is unchanged.

## Step 4: find out which tables accept new rows

New rows loaded fine in the editor. The game was less forgiving:

| Table | What happened |
| --- | --- |
| Colosseum | fine: the three courses appeared at the end of the list |
| EnemyTerritoryLevel, ColosseumPositionData | fine |
| EnemyTerritory | **every** simulator battle, vanilla ones too, hung on the white intro fade |
| BattleCharaSpec | the game crashed while loading a save |
| EnemyTerritoryMob | rows loaded, but nothing spawned |

To pin down EnemyTerritory we bisected: a single exact clone of a vanilla
territory still hung every battle, while re-saving the table with no new rows
was fine. So the parser wasn't at fault: the game expects that table's row
count. The fix was VR Simulator Overhaul's trick. One territory,
`terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard`, is a leftover battle test
that nothing uses. We repurposed it as the dummy's territory, shared by all
three courses, with the simulator's own Ogre as the dummy and `Stay` AI so it
doesn't wander.

Sharing one territory meant the game data can't tell the courses apart. The
runtime half handles that (step 6).

## Step 5: make the dummy unkillable

An enemy's max HP is the `EnemyParameter` row for its level times its spec's
HP percentage (the Ogre is 200%). At level 50 that's 4,558 HP, and our first
build simply refilled the dummy from the Lua side whenever it dropped below
90%. In testing it took 4,811 damage and stayed standing.

Then the channel owner pointed out that a single hit in this game can reach
99,999. A 4,558 HP dummy can be one-shot between refills. We tried a
max-HP multiplier status first: it applied to the dummy but its max HP didn't
change. What worked was another repurpose. No vanilla territory uses a level
above 70, so the mod rewrites the unused `Enemy_99` row with level 50's
stats (hits land exactly as on a level 50 enemy) and 500,000 HP, and spawns
the dummy at level 99: **1,000,000 HP**. With the refill at 90%, there's
always more than 99,999 HP of headroom.

## Step 6: the runtime half (UE4SS Lua)

The data pak puts a dummy in a fight. Everything else is a Lua mod that runs
five times a second:

- **Don't touch the game too early.** Our first version called battle
  functions from the title screen and crashed the game. Now it waits until a
  party character has been possessed before calling anything.
- **Which course is this?** The mod hooks the simulator menu's course and
  Yes buttons and reads the chosen course's title.
- **Find the dummy.** It walks the enemy list and checks each enemy's AI
  territory against the repurposed one.
- **DPS and Healing:** an endless Stop status pins the dummy in place. It
  still staggers.
- **Healing:** the dummy is also made immune to damage. Every party member
  except the leader is set to 1% HP and dropped back 1.5 seconds after each
  heal. (The game's own debug HP setter is compiled out of the retail build,
  so the mod uses HP percentages.)
- **Meters** come from HP changes: dummy HP lost is damage dealt, party HP
  lost is damage taken, and a patient's HP gained is healing. The overlay is a
  UMG widget the mod builds at runtime, and the numbers are also written to
  `meters.json`.

## Step 7: course names

Course titles are text keys, and the readable text lives in the game's text
table, a file other mods replace wholesale. Rather than ship a conflicting
copy, the Lua mod finds the simulator menu's text blocks that show our keys
and writes the names in: "Training Dummy: DPS", "Training Dummy: Tank" and
"Training Dummy: Healing", plus their descriptions.

## Step 8: test it live

Each build was installed and tried in the real game:

| Course | Result |
| --- | --- |
| DPS | 1,000,000 HP; Cloud's hits land at the same 38–39 as on a level 50 enemy; the dummy staggers while stopped |
| Tank | the dummy attacks; damage taken shows per party member |
| Healing | patients at 1 HP; Cure healed Tifa for 397, shown on the HPS meter, then she dropped back |
| Vanilla | Combat Training: Beginner's Hall still plays normally with the pak installed |

Lessons from testing:

- UE4SS hot reload (Ctrl+R) crashed this game. Restart after editing Lua.
- During battle the player controller possesses no pawn, so the "is the game
  ready" check had to remember that it had seen one.
- Screens can mislead: a "3,811" damage number turned out to be a 38 and an
  11 overlapping. The meters, not screenshots, are the evidence.

## Step 9: package it

The builder writes the changed tables, UnrealReZen packs them into
`TrainingDummy_P.pak/.ucas/.utoc`, and the install script copies them to
`~mods` along with the UE4SS folder, keeping backups. Rebirth's `.ucas` needs
a 10-byte header that UnrealReZen doesn't write, so the build copies it from
one of the game's own containers.

## Step 10: replace the parser with our own

v1.0.0 used LordGregory's parser, which is licensed for non-commercial use only. To let the mod (and
the channel) earn anything, we replaced it with our own reader and writer, worked out from the
game's files rather than from the parser's code:

- **Decode the format.** We dumped the smallest table byte by byte and decoded it in stages: the
  package summary and name map, the export's prefix, the frozen image's header, the key and
  property records, then the rows. Pointers are relative offsets shifted left one bit. Names are
  stored as zeros and filled in from a patch table at the end.
- **Prove it on everything.** We prototyped a reader and writer in Python, re-saved every
  DataObject table the game ships and compared the bytes. The first pass matched three tables.
  Fixing signed pointers, a 1-byte type we had as 2 bytes, 16-byte padding and the game's rule for
  sharing identical arrays and strings brought it to 1,689. The C# builder now re-saves 1,725
  tables byte for byte. The other 5 reuse bytes from inside the key table for tiny arrays and come
  back with identical rows.
- **Check the mod's build.** Built with the new code, four of the five tables match the old build
  row for row. The fifth, EnemyTerritoryLevel, showed that the old writer had pushed every row's
  1-byte flags 4 bytes away from where the game's own layout puts them, because adding a row moved
  the rows off 8-byte alignment. v1.1.0 fixes that.

The builder now has no third-party dependencies and is MIT throughout.

## Known limits and next steps

- **Tank stagger:** the Tank dummy can be pressured and staggered like any
  enemy, and while staggered it doesn't attack. Under constant pressure (a
  full party attacking, or Classic mode's auto-attacks) it may hardly fight
  back. Guard and dodge rather than attack to get the most out of it.
- **Overkill** isn't counted, though with 1,000,000 HP it can't happen.
- **Conflicts:** the pak replaces whole simulator tables, so it conflicts with
  other simulator mods unless they're merged.
- **Version 2:** an overlay styled like the game's own UI, and a Tank dummy
  that can't be locked down by stagger.

## Credits

- LordGregory's FF7R2 DataObject parser and Yoraiz0r's FF7 Rebirth Data Object Editor, which v1.0.0 was built with
- CityHash64: Google (MIT, ported)
- UE4SS, UnrealReZen, FModel, CUE4Parse and the OpenFF7R community
- NSK01's VR Simulator Overhaul, for showing the simulator is data-driven
