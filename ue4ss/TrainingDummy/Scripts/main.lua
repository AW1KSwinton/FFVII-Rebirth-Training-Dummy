-- Training Dummy: runtime half of the Combat Simulator training courses.
--
-- The data pak adds three one-round courses (COL99_TrainingDummy_DPS / _Tank
-- / _Heal) whose only enemy is the dummy, an Ogre in one shared, repurposed
-- territory. In those battles this mod:
--   DPS   keeps the dummy alive (refills HP) and pins it with Stop;
--   Tank  keeps the dummy alive and lets it fight;
--   Heal  makes the dummy untouchable and pinned, and holds party members
--         ("patients") at 1 HP so every heal counts;
-- and measures damage dealt (DPS), damage taken (DTPS) and healing (HPS).
--
-- Rules learned on this game (see docs/HOW-IT-WORKS.md): only call functions
-- that exist in the UE4SS header dump, never ask an object for a member it
-- lacks (it leaks the Lua C stack even inside pcall), and keep no UObject
-- across ticks.
local config = require("config")
local Meters = require("meters")
local course_text = require("course_text")
local meter_view = require("meter_view")
local overlay_ok, overlay = pcall(require, "overlay")

local TAG = "[TrainingDummy] "
local MAX_ENEMIES, MAX_PARTY = 32, 8
local BATTLE_API = "/Script/EndGame.Default__EndBattleAPI"
local STOP_STATUS = "BSC_Stop"
local STATUS_TIME_INFINITY = 64 -- EEndBattleStatusChangeTimeType::Infinity
local MENU_API = "/Script/EndGame.Default__EndMenuBPAPI"
local PARTY_API = "/Script/EndGame.Default__EndPartyAPI"
local STATICS = "/Script/Engine.Default__GameplayStatics"
local ENEMY_AI_CLASS = "/Script/EndGame.EndAIControllerEnemyBase"
-- An unused battle-test territory the data pak repurposes for the dummy.
local TRAINING_TERRITORY = "terVR_COL30_SUMMON_Gilgamesh_010_BtlTest_Hard"

local meters = Meters.new(config.rolling_window_seconds)
local state = {active = false, mode = nil, battle_id = nil, dummy_hp = nil, party = {}, logged = {},
    hp_setter = nil, overlay_visible = config.overlay, last_json = 0}

local function log(message) print(TAG .. message .. "\n") end
local function log_once(key, message)
    if state.logged[key] then return end
    state.logged[key] = true
    log(message)
end
-- Debug trace: logs a line only when what it reports changes.
local last_trace = {}
local function trace(key, message)
    if not config.debug or last_trace[key] == message then return end
    last_trace[key] = message
    log("debug " .. key .. ": " .. message)
end
course_text.trace = trace

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function cdo(path)
    local object = safe(StaticFindObject, path)
    if valid(object) then return object end
    return nil
end
local function name_of(object)
    local name = safe(function() return object:GetFName():ToString() end)
    return type(name) == "string" and name or "?"
end
local function number(v)
    if type(v) == "number" and v == v then return v end
    return nil
end

-- GetEnemyMembersRef fills an out array; UE4SS hands it back either as the
-- out table, a table holding one TArray, or a TArray (seen on this game).
local function enemies(battle)
    local out = {}
    local returned = safe(function() return battle:GetEnemyMembersRef(out) end)
    local value = returned ~= nil and returned or out
    local list = {}
    local function add(item)
        local actor = item
        if type(item) == "userdata" then
            local kind = safe(function() return item:type() end)
            if kind == "RemoteUnrealParam" or kind == "LocalUnrealParam" then actor = safe(function() return item:get() end) end
        end
        if valid(actor) and #list < MAX_ENEMIES then list[#list + 1] = actor end
    end
    local function walk(array)
        safe(function() array:ForEach(function(_, element) add(element) end) end)
    end
    if type(value) == "table" then
        if #value == 1 and type(value[1]) == "userdata" and safe(function() return value[1]:type() end) == "TArray" then
            walk(value[1])
        else
            for _, item in ipairs(value) do add(item) end
        end
    elseif type(value) == "userdata" and safe(function() return value:type() end) == "TArray" then
        walk(value)
    end
    return list
end

-- Battle members with their EPlayerType, read by slot (the telemetry
-- exporter's proven route; GetPlayerType(actor) fails on this game).
local function party_members(party)
    local count = number(safe(function() return party:GetBattleMemberCount() end)) or 0
    local list = {}
    for i = 0, math.min(count, MAX_PARTY) - 1 do
        local member = safe(function() return party:GetBattleMember(i) end)
        local kind = number(safe(function() return party:GetBattleMemberType(i) end))
        if valid(member) then list[#list + 1] = {actor = member, kind = kind} end
    end
    return list
end

-- Whether an enemy is the dummy: it belongs to the territory the three
-- courses share. The class is checked before the call because naming a
-- function an object lacks breaks the Lua state.
local function is_dummy(actor)
    local controller = safe(function() return actor:GetController() end)
    local enemy_ai = cdo(ENEMY_AI_CLASS)
    if not (valid(controller) and enemy_ai and safe(function() return controller:IsA(enemy_ai) end) == true) then
        trace("enemy " .. name_of(actor), "controller " .. (valid(controller) and name_of(controller) or "none")
            .. " is not an enemy AI (class found: " .. tostring(enemy_ai ~= nil) .. ")")
        return false
    end
    local territory = safe(function() return controller:GetOwnerTerritoryIdBP():ToString() end)
    trace("enemy " .. name_of(actor), "territory " .. tostring(territory))
    return territory == TRAINING_TERRITORY
end

-- Which course was started: when a course is chosen or confirmed, the
-- simulator menu (EndColosseumMenu) shows its title key
-- ($menu_Colosseum_CourseTitle_COL99_TrainingDummy_<Mode>); other courses
-- clear the remembered mode.
-- (The title may already show the readable name course_text put there.)
local function remember_course(context)
    local menu = safe(function() return context:get() end)
    if not valid(menu) then return end
    course_text.remember(menu)
    local title = safe(function() return menu.InfoWindow.Txt_CourseTitle:GetText():ToString() end)
    if not course_text.mode_of(title) then
        title = safe(function() return menu.Txt_TitleCourse:GetText():ToString() end)
    end
    state.chosen_mode = course_text.mode_of(title)
    trace("course", tostring(title))
end
local function hook_menu(event, callback)
    local ok, err = pcall(RegisterHook, "/Script/EndGame.EndColosseumMenu:" .. event, callback)
    if not ok then log("menu hook unavailable: " .. event .. " (" .. tostring(err) .. ")") end
end
hook_menu("OnCourseMenuPressedItem", remember_course)
hook_menu("OnYesButtonPressed", remember_course)
-- The course list filling rows, for their names.
hook_menu("OnCourseMenuSetupItem", function(context)
    course_text.remember(safe(function() return context:get() end))
end)
hook_menu("OnCourseMenuSelectedIndexChanged", function(context)
    course_text.remember(safe(function() return context:get() end))
end)

-- The controlled pawn once a save is loaded: a party character (PC0000 Cloud,
-- PC0001 Barret...). Battle functions are not called before this; calling
-- them from the title screen has crashed the game.
local engine, controller = nil, nil
local function gameplay_pawn()
    local pawn
    if not valid(engine) then engine = safe(FindFirstOf, "GameEngine") end
    local viewport = valid(engine) and safe(function() return engine.GameViewport end)
    local statics = cdo(STATICS)
    if valid(viewport) and statics then pawn = safe(function() return statics:GetPlayerPawn(viewport, 0) end) end
    trace("engine_route", string.format("engine=%s viewport=%s pawn=%s", tostring(valid(engine)),
        tostring(valid(viewport)), valid(pawn) and name_of(pawn) or "none"))
    if not valid(pawn) then
        -- The player controller the telemetry exporter uses; looked up again
        -- only when the kept one is gone (FindFirstOf walks every object).
        if not valid(controller) then controller = safe(FindFirstOf, "EndPlayerControllerBP_C") end
        pawn = valid(controller) and safe(function() return controller.Pawn end) or nil
        trace("controller_route", string.format("controller=%s pawn=%s", tostring(valid(controller)),
            valid(pawn) and name_of(pawn) or "none"))
    end
    if not valid(pawn) then return nil end
    local class = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
    if class:match("^PC%d%d%d%d_") then return pawn end
    return nil
end

local function hp(battle, actor)
    return number(safe(function() return battle:GetCharaHP(actor) end)),
        number(safe(function() return battle:GetHPMax(actor) end))
end

-- DebugSetHP may be compiled out of the shipping game; fall back to the
-- percentage setter (1% of max) the first time it does nothing.
local function set_hp_low(battle, actor)
    if state.hp_setter ~= "percent" then
        safe(function() battle:DebugSetHP(actor, 1) end)
        local now_hp = hp(battle, actor)
        if now_hp == 1 then
            if not state.hp_setter then log("patients use DebugSetHP (exact 1 HP)") end
            state.hp_setter = "debug"; return
        end
        if not state.hp_setter then log("DebugSetHP had no effect; patients use SetHPPercent(1)") end
        state.hp_setter = "percent"
    end
    safe(function() battle:SetHPPercent(actor, 1) end)
end

-- A passive dummy is held with an endless Stop, which keeps it still and stops it attacking. Stop also freezes
-- stagger: it would never end, and each one would leave its screen effect running. So lift Stop for exactly as long
-- as the dummy is staggered (it doesn't attack then anyway), and put it back afterwards.
local function hold_passive(battle, dummy, passive)
    local stop = FName(STOP_STATUS)
    local staggered = safe(function() return battle:IsBurst(dummy) end) == true
    local stopped = safe(function() return battle:HasStatusChangeID(dummy, stop) end) == true
    if passive and not staggered and not stopped then
        safe(function() battle:AddStatusChangeID(dummy, stop, STATUS_TIME_INFINITY, true, nil, true) end)
    elseif stopped and (staggered or not passive) then
        safe(function() battle:RemoveStatusChangeID(dummy, stop, false) end)
    end
    -- The clear key ends a stagger early, so a rotation can be tried again straight away.
    if state.clear_stagger then
        state.clear_stagger = false
        if staggered then
            safe(function() dummy.Controller:EndBurstInstant() end)
            log("stagger cleared")
        end
    end
end

local function now_seconds(world_object)
    local statics = cdo(STATICS)
    -- Game time stops while the game is paused, so menus do not dilute the meters.
    return number(statics and safe(function() return statics:GetTimeSeconds(world_object) end)) or os.time()
end

local function begin(mode, battle, dummy)
    meters:reset()
    state.active, state.mode, state.party, state.dummy_hp = true, mode, {}, nil
    state.clear_stagger = false
    state.battle_id = safe(function() return dummy:GetFullName() end)
    local cur, max = hp(battle, dummy)
    log(string.format("training battle started: mode=%s dummy=%s chara=%s hp=%s/%s", mode, name_of(dummy),
        tostring(safe(function() return battle:GetCharaID(dummy):ToString() end)), tostring(cur), tostring(max)))
end

local function finish()
    if state.active then log("training battle ended") end
    state.active, state.mode, state.battle_id = false, nil, nil
    if overlay_ok and overlay then safe(overlay.hide) end
end

local function track_dummy(battle, dummy, now)
    local cur, max = hp(battle, dummy)
    if not cur or not max or max <= 0 then return end
    if state.dummy_hp and cur < state.dummy_hp then meters:add("damage", state.dummy_hp - cur, now, "party") end
    if cur < max * config.refill_below_percent / 100 then
        safe(function() battle:SetHPPercent(dummy, 100) end)
        cur = hp(battle, dummy) or cur
    end
    state.dummy_hp = cur
    hold_passive(battle, dummy, (state.mode == "DPS" and config.passive_dps_dummy)
        or (state.mode == "Heal" and config.passive_heal_dummy))
end

-- EPlayerType order (EndDataBase).
local PLAYER_NAMES = {[0] = "Cloud", "Barret", "Tifa", "Aerith", "Red XIII", "Yuffie", "Cait Sith", "Zack",
    "Sephiroth", "Vincent", "Cid"}

-- Count what the member just spent, then fill their MP back up so they never run out.
local function track_mp(member_id, kind, p, now)
    local menu = cdo(MENU_API)
    if not (menu and kind) then return end
    local mp = number(safe(function() return menu:BPGetPlayerMP(kind) end))
    local max = number(safe(function() return menu:BPGetPlayerMaxMP(kind) end))
    if not (mp and max) then return end
    if p.mp and mp < p.mp then meters:add("mp", p.mp - mp, now, member_id) end
    if config.unlimited_mp and mp < max then
        safe(function() menu:BPSetPlayerMP(kind, max) end)
        mp = max
    end
    p.mp = mp
end

local function track_party(battle, party, now)
    -- The character the player controls: switching characters changes the leader.
    local leader = number(safe(function() return party:GetPartyLeaderType() end))
    trace("leader", tostring(leader))
    local seen = {}
    for _, entry in ipairs(party_members(party)) do
        local member, kind = entry.actor, entry.kind
        local id = PLAYER_NAMES[kind] or name_of(member)
        seen[id] = true
        local cur, max = hp(battle, member)
        if cur and max and max > 0 then
            local p = state.party[id]
            local patient = state.mode == "Heal" and (config.heal_patients == "all" or kind ~= leader)
            if not p then
                p = {hp = cur}
                state.party[id] = p
                if patient then
                    set_hp_low(battle, member)
                    p.hp = hp(battle, member) or cur
                    p.low = p.hp
                end
            else
                if cur < p.hp then meters:add("taken", p.hp - cur, now, id)
                elseif cur > p.hp and patient then
                    meters:add("heal", cur - p.hp, now, id)
                    p.reset_at = p.reset_at or (now + config.heal_reset_seconds)
                end
                p.hp = cur
                track_mp(id, kind, p, now)
                -- The Tank course is for measuring damage, so nobody dies. This isn't counted as healing.
                if state.mode == "Tank" and cur < max * config.tank_refill_below_percent / 100 then
                    safe(function() battle:SetHPPercent(member, 100) end)
                    p.hp = hp(battle, member) or cur
                end
                -- Whoever you switch away from becomes a patient too.
                if patient and not p.reset_at and (not p.low or cur > p.low) then
                    p.reset_at = now + config.heal_reset_seconds
                end
                if patient and p.reset_at and now >= p.reset_at then
                    set_hp_low(battle, member)
                    p.hp, p.reset_at = hp(battle, member) or p.hp, nil
                    p.low = p.hp
                end
            end
        end
    end
    for id in pairs(state.party) do if not seen[id] then state.party[id] = nil end end
end

-- This mod's folder: UE4SS puts each mod's Scripts folder on package.path.
-- (UE4SS may spell the folder "scripts".)
local MOD_DIR = package.path:match("([^;]*[\\/]TrainingDummy[\\/])[Ss]cripts[\\/]%?%.lua")
    or (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]")) or ""
local function json_number(v) return string.format("%.3f", v or 0) end
local function write_json(snapshot)
    local parts = {}
    for kind, k in pairs(snapshot.kinds) do
        parts[#parts + 1] = string.format('"%s":{"average":%s,"recent":%s,"total":%s,"biggest":%s}', kind,
            json_number(k.average), json_number(k.recent), json_number(k.total), json_number(k.biggest))
    end
    local body = string.format('{"mode":"%s","elapsed":%s,"time":%d,"meters":{%s}}', state.mode or "",
        json_number(snapshot.elapsed), os.time(), table.concat(parts, ","))
    local path = MOD_DIR .. "meters.json"
    local f = io.open(path .. ".tmp", "wb")
    if not f then return end
    f:write(body); f:close()
    os.remove(path)
    os.rename(path .. ".tmp", path)
end

-- Battle functions are called only once a save has been loaded ("armed"):
-- calling them from boot and the title screen crashed the game. In battle
-- the controller possesses no pawn, so a missing pawn disarms only after
-- DISARM_SECONDS outside battle (the title screen, a long scene).
local DISARM_SECONDS = 120
local function tick()
    -- Menu text only touches widgets the simulator menu's hooks reported.
    course_text.apply()
    local pawn = gameplay_pawn()
    trace("pawn", pawn and name_of(pawn) or "none")
    if pawn then
        state.armed, state.pawnless_since = true, nil
    elseif not state.armed then
        return
    end
    local battle = cdo(BATTLE_API)
    if not battle then trace("battle_api", "missing"); return end
    local in_battle = safe(function() return battle:IsInBattle() end)
    trace("in_battle", tostring(in_battle))
    if in_battle ~= true then
        if state.active then finish() end
        state.scanned_battle = nil
        if not pawn then
            state.pawnless_since = state.pawnless_since or os.time()
            if os.time() - state.pawnless_since >= DISARM_SECONDS then
                state.armed, state.pawnless_since = false, nil
                trace("armed", "false (no pawn outside battle)")
            end
        end
        return
    end
    state.pawnless_since = nil
    local dummy
    local list = enemies(battle)
    trace("enemies", tostring(#list))
    for _, enemy in ipairs(list) do
        if is_dummy(enemy) then dummy = enemy; break end
    end
    if not dummy then
        if state.active then finish() end
        if not state.scanned_battle and #list > 0 then
            state.scanned_battle = true
            log(string.format("battle with %d enemies, none in a training territory", #list))
        end
        return
    end
    if not state.active or safe(function() return dummy:GetFullName() end) ~= state.battle_id then
        if not state.chosen_mode then log("course not recorded; using DPS") end
        begin(state.chosen_mode or "DPS", battle, dummy)
    end
    local now = now_seconds(dummy)
    track_dummy(battle, dummy, now)
    local party = cdo(PARTY_API)
    if party then track_party(battle, party, now) end

    local snapshot = meters:snapshot(now)
    if overlay_ok and overlay and state.overlay_visible then safe(overlay.show, meter_view.build(snapshot, state.mode, config), config, dummy) end
    if config.write_json and now - state.last_json >= 0.5 then
        state.last_json = now
        safe(write_json, snapshot)
    end
end

-- Per-hit events, for attribution once confirmed live. Logged only for now.
local function try_hook(path, describe)
    local ok, err = pcall(RegisterHook, path, function(...)
        log_once(path, "hook fired: " .. path .. " " .. describe(...))
    end)
    if not ok then log("hook unavailable: " .. path .. " (" .. tostring(err) .. ")") end
end
try_hook("/Script/EndGame.EndBattleSceneBlueprint:OnTakeDamage", function(_, damage, causer, damaged, ability, _, _, _, _, _, _, _, _, _, heal)
    return string.format("damage=%s causer=%s damaged=%s ability=%s heal=%s",
        tostring(safe(function() return damage:get() end)), tostring(safe(function() return causer:get():ToString() end)),
        tostring(safe(function() return damaged:get():ToString() end)), tostring(safe(function() return ability:get():ToString() end)),
        tostring(safe(function() return heal:get() end)))
end)
try_hook("/Script/EndGame.EndAIControllerBluePrintBase:OnTakeDamageInvoke", function(_, damage)
    return "damage=" .. tostring(safe(function() return damage:get() end))
end)

RegisterKeyBind(Key[config.clear_stagger_key], function()
    state.clear_stagger = true
end)
RegisterKeyBind(Key[config.reset_key], function()
    meters:reset()
    log("meters reset")
end)
RegisterKeyBind(Key[config.toggle_overlay_key], function()
    state.overlay_visible = not state.overlay_visible
    if not state.overlay_visible and overlay_ok and overlay then ExecuteInGameThread(function() safe(overlay.hide) end) end
end)

-- Register this mod's game-thread callback now, while mods load. UE4SS adds it to the process-event callback list
-- on a mod's first ExecuteInGameThread; doing that during play can move the list under a running callback and crash.
pcall(ExecuteInGameThread, function() end)

-- Each ExecuteInGameThread allocates a Lua thread that UE4SS never forgets, so tick at full rate only when it matters.
local IDLE_EVERY = 5
local idle = 0
LoopAsync(config.tick_ms, function()
    trace("scheduler", "async loop running")
    idle = idle + 1
    -- Picking a course means a fight is close: the dummy must be held from its first moment.
    if state.active or state.chosen_mode or course_text.has_work() or idle >= IDLE_EVERY then
        idle = 0
        ExecuteInGameThread(function()
            trace("game_thread", "game-thread callback running")
            local ok, err = pcall(tick)
            if not ok then log_once("tick:" .. tostring(err), "tick error: " .. tostring(err)) end
        end)
    end
    return false
end)

if not overlay_ok then log("overlay disabled: " .. tostring(overlay)) end
log("loaded")
