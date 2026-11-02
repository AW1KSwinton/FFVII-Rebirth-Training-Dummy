# Training Dummy — FF7 Rebirth Combat Simulator mod

Adds three courses to Chadley's Combat Simulator, at the end of the list
(Combat Training tab), with live meters on screen:

- **Training Dummy: DPS**: a dummy that can't be defeated, stands still and
  never fights back. Shows your damage per second.
- **Training Dummy: Tank**: a dummy that can't be defeated and fights back.
  Shows damage taken per second (DTPS) and DPS.
- **Training Dummy: Healing**: a harmless dummy you can't hurt; your other
  party members are held at 1 HP and dropped back after each heal. Shows
  healing per second (HPS) per party member.

The dummy has 1,000,000 HP and refills, so even a 99,999 hit can't defeat it.
F7 resets the meters and F8 hides them. Settings are in `ue4ss/TrainingDummy/Scripts/config.lua`.

- Download it: [Nexus Mods](https://www.nexusmods.com/finalfantasy7rebirth/mods/2474).
- See it working, then how it was built: [the video](https://www.youtube.com/watch?v=ErkKRa1Sr4g).
- How to install and use it: [docs/GUIDE.md](docs/GUIDE.md).
- How we built it, step by step: [docs/HOW-WE-BUILT-IT.md](docs/HOW-WE-BUILT-IT.md).
- The design in reference form, what was tested and the limits:
  [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## Install

Needs UE4SS v3 for FF7 Rebirth.

1. Copy `TrainingDummy_P.pak`, `.ucas` and `.utoc` into `End/Content/Paks/~mods/`.
2. Copy the `TrainingDummy` folder into `End/Binaries/Win64/ue4ss/Mods/` and
   add `TrainingDummy : 1` to `mods.txt` (above `Keybinds`).

The courses appear once Chadley's Combat Simulator is open (from Chapter 2).
Items can't be used in simulator fights, so heal with spells.

Conflicts with mods that replace `Colosseum`, `ColosseumPositionData`,
`EnemyTerritory`, `EnemyTerritoryLevel` or `EnemyParameter`
(VR Simulator Overhaul among them).

## Build from your own game files

The pak is built from your own copy of the game; this repository contains no
game files.

1. Export these vanilla DataObjects with FModel (raw `.uasset`):
   `DataObject/Resident/{Colosseum, ColosseumPositionData, EnemyTerritory,
   EnemyTerritoryLevel, EnemyParameter}`.
2. Copy `tools/build-config.example.json` to `tools/build-config.local.json`
   and set your paths.
3. `tools/Build-TrainingDummy.ps1 -Mode Build`, then `-Mode Install`
   (`-Mode Uninstall` and `-Mode Status` also exist). Needs the .NET 8 SDK
   and UnrealReZen.

The courses are described in `data/training-dummy.json`. The builder
(`tools/DataBuilder`) is our own reader and writer for DataObject tables, with no
third-party dependencies. It can add rows to any table and repurpose existing
rows. `roundtrip <folder>` re-saves every table under a folder and checks the
bytes: it reproduces 1,725 of the game's DataObject tables byte for byte, and
the other 5 with identical rows. `compare <a> <b>` compares two tables row by
row.

Tests: `python -m pip install lupa`, then `python tests/run_tests.py`.

## Credits

- CityHash64 — Google (MIT, ported)
- LordGregory's FF7R2 DataObject parser and Yoraiz0r's FF7 Rebirth Data Object
  Editor, which the first version was built with
- UE4SS, UnrealReZen, FModel and the OpenFF7R community
- NSK01's VR Simulator Overhaul, for showing the simulator is data-driven

## Licence

MIT (see `LICENSE`). The ported CityHash64 keeps Google's MIT notice.
