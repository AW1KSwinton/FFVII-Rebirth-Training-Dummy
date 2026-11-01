# How the Training Dummy mod works

Three new Combat Simulator courses (DPS, Tank, Heal) with a dummy enemy and
live DPS / DTPS / HPS meters. The mod has two halves:

| Half | What it changes | Where |
| --- | --- | --- |
| Data pak `TrainingDummy_P` | Adds the courses to the simulator's tables | `data/training-dummy.json`, built by `tools/` |
| UE4SS Lua mod `TrainingDummy` | Makes the dummy behave and draws the meters | `ue4ss/TrainingDummy/Scripts/` |

Everything below was found or confirmed live (Steam release, UE4SS v3.0.1,
October–November 2026).

## 1. How the Combat Simulator defines a battle

A simulator course is one row of `DataObject/Resident/Colosseum`. It names:

- `EnemyTerritoryID_Array`: one territory per round (`EnemyTerritory` +
  `EnemyTerritoryLevel` rows), and each territory lists mob templates
  (`EnemyTerritoryMob`), their level and their field AI (`Stay` keeps them put);
- `BattleScenePosDataID_Array`: spawn positions (`ColosseumPositionData`);
- `TabCategory` (7 = the Combat Training tab), `PartyMax`, `EntryMember_Array`,
  unlock flags, rewards, music and the title/description text keys.

The courses are data, so new ones need no Blueprint work.

## 2. Adding rows to a DataObject table

DataObject tables are UE4 "frozen" memory images, read and written with
LordGregory's FF7R2 DataObject parser (the library behind Yoraiz0r's Data
Object Editor). The parser can change values but not add rows. Our builder
(`tools/DataBuilder`) adds them:

- Rows live in a frozen `TMap<FName, int32>`: a dense array of keys
  `{name, entry index, next key in bucket, bucket}`, a bucket array, then the
  entries. A new row needs a key, an entry and a bucket link.
- The bucket is UE4's FName hash: **CityHash64 of the lowercase name, plus the
  FName number, masked to the bucket count**. This matched all 1,010 keys of
  Colosseum, EnemyTerritory and BattleCharaSpec.
- The parser keeps the original pointers to the bucket, property and entry
  arrays, so the builder saves twice: once to lay the file out, then again
  with those three pointers corrected.
- Every build reloads the output and checks that each new row has the
  requested values and every vanilla row is unchanged.

## 3. Which tables tolerate new rows (tested live)

| Table | New rows | Result |
| --- | --- | --- |
| Colosseum | 3 courses | fine — they appear at the end of the list |
| EnemyTerritoryLevel | 1 | fine |
| ColosseumPositionData | 1 | fine |
| EnemyTerritory | even 1 exact clone | **every** simulator battle hangs on the white intro fade |
| BattleCharaSpec | 3 | game crashes while loading a save |
| EnemyTerritoryMob | 3 | rows load, but nothing spawns: a template must name an actor placed in the VR level |

Re-saving EnemyTerritory or BattleCharaSpec without new rows is fine, so
the parser isn't to blame. The game appears to expect fixed row counts in those
two tables. So the mod:

- **repurposes** the one unused territory, `terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard`
  (a leftover battle test that nothing references), shared by all three
  courses — the same trick the VR Simulator Overhaul mod uses;
- uses the simulator's own Ogre template (`mobcolvr_EN2211_01_Ogre_OrcEnd2_00`)
  as the dummy, with `Stay` field AI;
- gives it 1,000,000 HP. An enemy's max HP is the `EnemyParameter` row for
  its level ("Enemy_<level>" HPMax) times its spec's HP% (the Ogre is 200%).
  No vanilla territory uses a level above 70, so the mod repurposes
  `Enemy_99`: level 50's stats (so hits land as they do on a level 50 enemy)
  with HPMax 500,000, and spawns the dummy at level 99. In this game a single
  hit can reach 99,999, so the 90% refill always leaves enough headroom.
  (Special status type 77, `HPMaxCoefficient`, was tried first: it applies to
  the dummy but leaves its max HP unchanged.)

## 4. The runtime half (UE4SS Lua)

Every 200 ms, on the game thread:

1. **Arming.** Battle functions are only called after a party character has
   been possessed. Calling them from boot/the title screen crashed the game.
   During battles the controller possesses no pawn, so the mod stays armed
   until 2 minutes pass with no pawn and no battle.
2. **Finding the dummy.** `EndBattleAPI:GetEnemyMembersRef`, then for each
   enemy its AI controller (checked to be an `EndAIControllerEnemyBase` first)
   and `GetOwnerTerritoryIdBP()` = the repurposed territory.
3. **Which course.** A hook on `EndColosseumMenu:OnCourseMenuPressedItem` /
   `OnYesButtonPressed` reads the menu's `InfoWindow.Txt_CourseTitle`
   (`$menu_Colosseum_CourseTitle_COL99_TrainingDummy_<Mode>`).
4. **Behaviour.**
   - DPS: refill (`SetHPPercent(100)` below 90%) and an endless `BSC_Stop`
     status (`AddStatusChangeID`, time type Infinity) — it still staggers.
   - Tank: refill only; it fights back.
   - Heal: Stop + `SetDisableDamageHit`; party members other than the leader
     (`EndPartyAPI:GetPartyLeaderType` vs `GetBattleMemberType`) are set to 1%
     HP (`DebugSetHP` is compiled out of the retail game) and dropped back
     1.5 s after each heal.
5. **Course names.** The courses use their own text keys, which aren't in the
   game's text table (`Text/US/Resident_TxtRes`, a file other mods replace
   wholesale). So the mod writes readable names into the simulator menu's
   text blocks: the info panel and party screen titles through the menu's
   reflected `InfoWindow.Txt_CourseTitle` / `Txt_TitleCourse`, and the list
   rows and description through a throttled `FindAllOf("EndTextBlock")` that
   only touches blocks showing one of our keys
   (`UUserWidget:GetWidgetFromName` isn't exposed in this game).
6. **Meters.** HP deltas: dummy HP lost = damage dealt, party HP lost = damage
   taken, patient HP gained = healing. Average since the first event and a
   5 s rolling rate; written to `meters.json` and drawn in-game by a UMG
   widget built at runtime (CanvasPanel + TextBlock, `AddToViewport`).

## 5. Measured live

| Course | Party | Result |
| --- | --- | --- |
| DPS | Cloud | dummy spawns with 1,000,000 HP; Cloud's hits land at the same 38–39 as at level 50; staggers while stopped |
| DPS (earlier build, 4,558 HP) | Cloud | 4,811 damage dealt, still standing — the refill works |
| Heal | Cloud (leader), Red XIII, Tifa | patients at 11–13 HP; Cure healed Tifa 397, HPS shown, reset to 1% |
| Tank | Cloud | 218 damage taken (DTPS) and 1,491 dealt in 55 s; dummy attacks normally |

## 6. Known limits

- The Tank dummy can be pressured and staggered, and doesn't attack while
  staggered. With a full party attacking (2026-11-01, Cloud, Aerith and Tifa
  in Classic mode) it dealt no damage in 90 s; with Cloud alone it kept
  landing hits (527 damage taken over about four minutes).
- Overkill isn't measured (HP deltas stop at 0); per-hit hooks
  (`EndBattleSceneBlueprint:OnTakeDamage`) never fired in the simulator.
- Course names come from the Lua mod; without it the three rows are blank.
- Vanilla courses were rechecked with the full pak (Combat Training:
  Beginner's Hall plays normally).
- Items can't be used in simulator battles, so healing tests need spells.
- The pak replaces the whole Colosseum / EnemyTerritory / EnemyTerritoryLevel /
  ColosseumPositionData / EnemyParameter assets, like every simulator mod; it conflicts with
  VR Simulator Overhaul unless merged.
- UE4SS hot reload (Ctrl+R) crashed the game; restart after editing the Lua.

## Credits

- FF7R2 DataObject parser — LordGregory (CC BY-NC 4.0, used as a NuGet package)
- FF7 Rebirth Data Object Editor view models — Yoraiz0r (MIT, vendored)
- CityHash64 — Google (MIT, ported)
- UE4SS, UnrealReZen, retoc, CUE4Parse and the OpenFF7R community
- NSK01's VR Simulator Overhaul, for showing that the simulator is data-driven
