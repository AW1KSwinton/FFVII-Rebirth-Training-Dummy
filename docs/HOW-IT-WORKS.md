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

## 2. Reading and writing a DataObject table

`tools/DataBuilder` is our own reader and writer, with no third-party
dependencies. It re-saves 1,725 of the game's DataObject tables byte for byte,
and the other 5 with identical rows (`roundtrip`).

**The package.** Each table is an IoStore ("zen") package with one export:
- A 0x40-byte summary of section offsets.
- The name map: each name is a 2-byte big-endian length header, then the
  characters.
- The CityHash64 name hashes, 8-aligned.
- The import, export, bundle and graph tables.
- The export.

Adding a name appends it and its hash. The later offsets and the export's size
change; nothing else does.

**The export:**
- Its tagged-property prefix ends in `None`, and holds the frozen image's size
  at +0x0c.
- The frozen memory image starts at +0x20.
- After the image come 8 bytes, the name patch table, and 4 trailing bytes.

**The frozen image.** Pointers are int64 `(relative offset << 1) | 1`.
- A 0x58-byte header:
  - the row keys, a `TSet<TPair<FName,int32>>` (key elements, allocation bits
    and a bucket array);
  - the property records (an FName and a type code, 12 bytes each);
  - the entries, one struct per row.
- The key elements: name, entry index, next key in the bucket, and bucket.
- The bits, the buckets, the records and the entries, which are 8-aligned.
- Finally, array and string contents, depth first. The image is padded to 16
  bytes.

**Rows.**
- A row's fields follow the record order at natural alignment.
- A property whose name ends in `_Array` is a `TArray` of its type.
- Type codes: 1, 2 and 3 are 1 byte, 4 is 2 bytes, 6 and 7 are 4 bytes, 8 is
  8 bytes, 9 is a float, 10 is a string (UTF-16, terminator counted) and 11 is
  an FName.
- Every FName is stored as zero and named by the patch table
  `{name index, number, offsets}`.

**Sharing.** The game's writer shares identical content: strings with the same
characters, and arrays with the same bytes and names. String arrays are never
shared, because their pointers make their bytes unique. The builder does the
same.

**New rows.** A new row needs a key, an entry and a bucket link. The bucket is
UE4's FName hash: **CityHash64 of the lowercase name, plus the FName number,
masked to the bucket count** (RoundUpToPowerOfTwo(Num / 2 + 8) buckets, rehashed
when that count grows). Every build reloads its output and checks three things:
each new row has the requested values, every vanilla row is unchanged, and every
key is reachable from its bucket.

The first version used LordGregory's FF7R2 DataObject parser. Its writer laid
out rows by absolute address. After one new key pushed EnemyTerritoryLevel's
entries off 8-byte alignment, that table's 1-byte fields landed 4 bytes from
where the game's own layout puts them. The builder replaced it from v1.1.0.

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
the writer isn't to blame. The game appears to expect fixed row counts in those
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
   - DPS: refill (`SetHPPercent(100)` below 90%) and an endless `BSC_Stop` status
     (`AddStatusChangeID`, time type Infinity), which keeps it still and stops it attacking.
     Stop also freezes stagger: up to v1.1.0 stagger never ended, and each one left its
     screen effect running, so the centre of the screen blurred more with each stagger.
     So while `IsBurst` is true the mod lifts Stop (`RemoveStatusChangeID`), and it puts
     Stop back when stagger ends by itself. `SetForceActionRestriction` was tried and
     doesn't stop the dummy attacking.
   - F6: `dummy.Controller:EndBurstInstant()` ends a stagger early and resets the gauge.
   - Tank: refill only; it fights back.
   - Heal: the same hold and refill as DPS, so attacks land and build ATB. (`SetDisableDamageHit`
     on a party member also blocks heals, so it can't protect patients.) By default the whole party is set to 1%
     HP (`heal_patients = "others"` spares the leader, from `EndPartyAPI:GetPartyLeaderType`) (`DebugSetHP` is compiled out of the retail game) and dropped back
     1.5 s after each heal.
5. **Course names.** The courses use their own text keys, which aren't in the
   game's text table (`Text/US/Resident_TxtRes`, a file other mods replace
   wholesale). So the mod writes readable names into the simulator menu's
   text blocks: the info panel and party screen titles through the menu's
   reflected `InfoWindow.Txt_CourseTitle` / `Txt_TitleCourse`, and the list
   rows and description through a throttled `FindAllOf("EndTextBlock")` that
   only touches blocks showing one of our keys
   (`UUserWidget:GetWidgetFromName` isn't exposed in this game).
6. **Tank HP.** Below `tank_refill_below_percent` a member is refilled with `SetHPPercent(100)`, so nobody
   dies while practising guarding. The refill isn't counted as healing or damage.
7. **MP.** `EndMenuBPAPI:BPGetPlayerMP` shows what each member just spent, which is counted, and
   `BPSetPlayerMP` fills it back up, so MP never runs out on any course.
8. **Meters.** HP deltas: dummy HP lost = damage dealt, party HP lost = damage
   taken, patient HP gained = healing. Average since the first event and a
   5 s rolling rate; written to `meters.json` and drawn in-game by a UMG
   widget built at runtime (CanvasPanel + TextBlock, `AddToViewport`).

## 5. Measured live

| Course | Party | Result |
| --- | --- | --- |
| DPS | Cloud | dummy spawns with 1,000,000 HP; Cloud's hits land at the same 38–39 as at level 50; staggers and recovers by itself (12 to 25 s measured) |
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

## The meter panel

The panel is plain UMG (`Image` and `TextBlock`) built at runtime, using the game's own sprites from
`/Game/Menu/Resident/Texture/`. The text is the engine's Roboto. The game's `EndTextBlock` and `EndImage`
draw nothing when created at runtime, even inside the game's own widget templates, and its bitmap fonts
only work with those. `meter_view.lua` turns the meters into a plain table, tested offline, and
`overlay.lua` draws it, touching a widget only when something changed.

## A UE4SS crash to avoid

UE4SS adds a process-event callback on each mod's first `ExecuteInGameThread`. If that happens during
play, the callback list can move in memory under a callback that is still running, and the game crashes
(`EXCEPTION_ACCESS_VIOLATION`). So this mod makes that first call while it loads. It also ticks at full rate
only during a course or while the menu has text to replace, because each `ExecuteInGameThread` allocates a
Lua thread that UE4SS never forgets.

## Credits

- LordGregory's FF7R2 DataObject parser and Yoraiz0r's FF7 Rebirth Data Object Editor, used to build v1.0.0
- CityHash64 — Google (MIT, ported)
- UE4SS, UnrealReZen, retoc, CUE4Parse and the OpenFF7R community
- NSK01's VR Simulator Overhaul, for showing that the simulator is data-driven
