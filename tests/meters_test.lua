-- Plain Lua 5.4 checks for meters.lua (run with tests/run_tests.py).
local Meters = require("meters")

local function near(a, b) return math.abs(a - b) < 1e-6 end

local m = Meters.new(5)
m:add("damage", 1000, 10.0, "party")
m:add("damage", 500, 12.0, "party")
m:add("damage", -50, 12.5, "party")   -- ignored: not an amount
m:add("heal", 300, 13.0, "Cloud")
local snap = m:snapshot(14.0)
local d = snap.kinds.damage
assert(near(d.total, 1500), "total damage")
assert(near(d.average, 1500 / 4), "average over the 4 s since the first hit")
assert(near(d.recent, 1500 / 4), "rolling window shorter than 5 s uses the elapsed time")
assert(near(d.biggest, 1000), "biggest hit")
assert(near(snap.kinds.heal.by_source.Cloud, 300), "heal attributed to its patient")

-- After the window, only recent hits count towards the rolling rate.
m:add("damage", 200, 30.0, "party")
snap = m:snapshot(31.0)
assert(near(snap.kinds.damage.recent, 200 / 5), "rolling rate over 5 s")
assert(near(snap.kinds.damage.average, 1700 / 21), "average since the first hit")

-- The first event of a session starts the clock; a 1 s floor avoids huge rates.
local fresh = Meters.new(5)
fresh:add("taken", 90, 100.0, "Tifa")
assert(near(fresh:snapshot(100.2).kinds.taken.average, 90), "1 s floor")

m:reset()
assert(m:snapshot(40.0).kinds.damage.total == 0, "reset clears totals")
-- Before the first event every rate is 0, never NaN (it reached the overlay live).
local idle = Meters.new(5):snapshot(12.0).kinds.heal
assert(idle.average == 0 and idle.recent == 0, "no NaN before the first event")
print("meters_test: ok")
