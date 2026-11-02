-- What the on-screen meter shows, as a plain table. Pure Lua: no game calls, so it can be tested outside the
-- game (see tests/meter_view_test.lua). overlay.lua draws the result.
local M = {}

local TITLES = {DPS = "Training Dummy: DPS", Tank = "Training Dummy: Tank", Heal = "Training Dummy: Healing"}
local SHOWN = {DPS = {"damage"}, Tank = {"taken", "damage"}, Heal = {"heal"}}
local LABELS = {damage = "Damage per second", taken = "Damage taken per second", heal = "Healing per second"}
local BIGGEST = {damage = "Biggest hit", taken = "Biggest hit taken", heal = "Biggest heal"}

function M.format_number(value)
    local text = tostring(math.floor((value or 0) + 0.5))
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

function M.format_time(seconds)
    local whole = math.floor(seconds or 0)
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

-- Party members, biggest first, with their share of the total for the bar.
local function members_of(kind, k)
    if kind == "damage" then return {} end
    local list = {}
    for name, amount in pairs(k.by_source) do
        list[#list + 1] = {name = name, amount = amount, value = M.format_number(amount),
            share = k.total > 0 and amount / k.total or 0}
    end
    table.sort(list, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.name < b.name
    end)
    return list
end

function M.build(snapshot, mode, config)
    local view = {title = TITLES[mode] or "Training Dummy", timer = M.format_time(snapshot.elapsed), blocks = {},
        hint = string.format("%s  Clear stagger      %s  Reset      %s  Hide", config.clear_stagger_key, config.reset_key, config.toggle_overlay_key)}
    for _, kind in ipairs(SHOWN[mode] or {}) do
        local k = snapshot.kinds[kind]
        local stats = {{string.format("Last %d seconds", config.rolling_window_seconds), M.format_number(k.recent)},
            {"Total", M.format_number(k.total)}, {BIGGEST[kind], M.format_number(k.biggest)}}
        if kind == "heal" then
            local mp = snapshot.kinds.mp and snapshot.kinds.mp.total or 0
            stats[#stats + 1] = {"MP spent", M.format_number(mp)}
            stats[#stats + 1] = {"Healing per MP", mp > 0 and M.format_number(k.total / mp) or "-"}
        end
        view.blocks[#view.blocks + 1] = {label = LABELS[kind], value = M.format_number(k.average), stats = stats,
            members = members_of(kind, k)}
    end
    return view
end

return M
