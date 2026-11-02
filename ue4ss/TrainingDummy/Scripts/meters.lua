-- DPS / DTPS / HPS bookkeeping. Pure Lua: no game calls, so it can be
-- tested outside the game (see tests/meters_test.lua).
local M = {}
M.__index = M

-- Kinds: "damage" (dealt to a dummy), "taken" (by the party), "heal" (to a patient), "mp" (spent by the party).
function M.new(window_seconds)
    return setmetatable({window = window_seconds or 5, events = {}, totals = {}, by_source = {},
        biggest = {}, started = nil, last = nil}, M)
end

function M:reset()
    self.events, self.totals, self.by_source, self.biggest = {}, {}, {}, {}
    self.started, self.last = nil, nil
end

function M:add(kind, amount, now, source)
    if type(amount) ~= "number" or amount <= 0 or amount ~= amount then return end
    self.started = self.started or now
    self.last = now
    self.totals[kind] = (self.totals[kind] or 0) + amount
    if (self.biggest[kind] or 0) < amount then self.biggest[kind] = amount end
    if source then
        local per = self.by_source[kind] or {}
        per[source] = (per[source] or 0) + amount
        self.by_source[kind] = per
    end
    self.events[#self.events + 1] = {kind = kind, amount = amount, t = now}
end

-- Drops events older than the rolling window.
function M:prune(now)
    local keep, cutoff = {}, now - self.window
    for _, e in ipairs(self.events) do
        if e.t >= cutoff then keep[#keep + 1] = e end
    end
    self.events = keep
end

function M:elapsed(now)
    if not self.started then return 0 end
    return math.max(now - self.started, 1)
end

-- Average since the first event, and over the rolling window.
function M:rate(kind, now)
    local total = self.totals[kind] or 0
    local recent = 0
    for _, e in ipairs(self.events) do
        if e.kind == kind and e.t >= now - self.window then recent = recent + e.amount end
    end
    if not self.started then return 0, 0, total end
    local span = math.min(self.window, self:elapsed(now))
    return total / self:elapsed(now), recent / span, total
end

function M:snapshot(now)
    self:prune(now)
    local out = {elapsed = self.started and (now - self.started) or 0, kinds = {}}
    for _, kind in ipairs({"damage", "taken", "heal", "mp"}) do
        local avg, recent, total = self:rate(kind, now)
        out.kinds[kind] = {average = avg, recent = recent, total = total, biggest = self.biggest[kind] or 0,
            by_source = self.by_source[kind] or {}}
    end
    return out
end

return M
