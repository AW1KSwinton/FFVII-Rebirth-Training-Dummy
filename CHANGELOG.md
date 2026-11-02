# Changelog

## 1.2.0 (2026-11-02)

- **New look:** the meters are now a panel in the top left corner, drawn with the game's own HUD art, with
  party bars and readable labels.
- **Fix:** staggering the DPS dummy no longer leaves a growing blur in the centre of the screen, and stagger now
  ends by itself. The Stop status holding the dummy is lifted while it's staggered, and returns afterwards.
- **New:** F6 clears the dummy's stagger.
- **New:** on the Tank course your HP refills, so you can keep practising guarding.
- **New:** unlimited MP on all three courses, and the Healing panel shows MP spent and healing per MP.
- **Fix:** the Healing dummy can be attacked, so attacks build ATB for your spells. It still can't be defeated.
- **Change:** the whole party is now held at 1 HP on the Healing course, including the character you control, so
  you can test healing yourself. `heal_patients = "others"` in `config.lua` gives the old behaviour.
- **Fix:** the mod no longer risks a crash by setting up its game-thread callback during play.
- The data pak is unchanged from 1.1.0.

## 1.1.0 (2026-11-01)

- **Fix:** EnemyTerritoryLevel rows now keep the game's own layout. The 1.0.0 build pushed every row's
  1-byte flags (such as UnableBattleEscape and ForceBattleInAllEnemies) 4 bytes away from where the game's
  layout puts them, because adding a row moved the rows off 8-byte alignment. This table is used by
  encounters across the game, not just the simulator.
- The data builder is now our own reader and writer for DataObject tables, with no third-party
  dependencies. It re-saves 1,725 of the game's DataObject tables byte for byte (`roundtrip`) and can
  compare two tables row by row (`compare`). The whole project is MIT.
- The dummy, courses, meters and names are unchanged.

## 1.0.0 (2026-11-01)

- Training Dummy: DPS, Tank and Healing courses for Chadley's Combat Simulator, with live DPS, DTPS and
  HPS meters, a 1,000,000 HP dummy and course names.
