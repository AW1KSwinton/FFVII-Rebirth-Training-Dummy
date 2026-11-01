# Changelog

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
