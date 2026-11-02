local View = require("meter_view")

local config = {clear_stagger_key = "F6", reset_key = "F7", toggle_overlay_key = "F8", rolling_window_seconds = 5}
local function kind(average, recent, total, biggest, by_source)
    return {average = average, recent = recent, total = total, biggest = biggest, by_source = by_source or {}}
end
local snapshot = {elapsed = 67.4, kinds = {
    damage = kind(4210.4, 3988, 282070, 9999, {Cloud = 100}),
    taken = kind(312, 287, 20904, 1290, {Tifa = 6404, Cloud = 14500}),
    heal = kind(0, 0, 0, 0),
}}

assert(View.format_number(0) == "0")
assert(View.format_number(999) == "999")
assert(View.format_number(1000) == "1,000")
assert(View.format_number(1234567.6) == "1,234,568")
assert(View.format_number(nil) == "0")
assert(View.format_time(0) == "0:00")
assert(View.format_time(67.4) == "1:07")
assert(View.format_time(600) == "10:00")

local tank = View.build(snapshot, "Tank", config)
assert(tank.title == "Training Dummy: Tank")
assert(tank.timer == "1:07")
assert(tank.hint == "F6  Clear stagger      F7  Reset      F8  Hide")
assert(#tank.blocks == 2)
assert(tank.blocks[1].label == "Damage taken per second" and tank.blocks[1].value == "312")
assert(tank.blocks[1].stats[1][1] == "Last 5 seconds" and tank.blocks[1].stats[1][2] == "287")
assert(tank.blocks[1].stats[3][1] == "Biggest hit taken" and tank.blocks[1].stats[3][2] == "1,290")

-- Party members come biggest first, with shares of the total; damage dealt lists nobody.
local members = tank.blocks[1].members
assert(#members == 2 and members[1].name == "Cloud" and members[2].name == "Tifa")
assert(members[1].value == "14,500")
assert(math.abs(members[1].share + members[2].share - 1) < 1e-9)
assert(tank.blocks[2].label == "Damage per second" and tank.blocks[2].value == "4,210")
assert(#tank.blocks[2].members == 0)

local dps = View.build(snapshot, "DPS", config)
assert(dps.title == "Training Dummy: DPS" and #dps.blocks == 1)

-- A course nobody has healed on yet shows zeros, never a division by zero.
local heal = View.build({elapsed = 0, kinds = {heal = kind(0, 0, 0, 0, {Tifa = 0})}}, "Heal", config)
assert(heal.title == "Training Dummy: Healing" and heal.timer == "0:00")
assert(heal.blocks[1].value == "0" and heal.blocks[1].members[1].share == 0)
-- The healing block counts MP, and copes with none spent yet.
local spending = View.build({elapsed = 10, kinds = {heal = kind(10, 10, 794, 397, {}), mp = kind(0, 0, 10, 5)}}, "Heal", config)
assert(spending.blocks[1].stats[4][1] == "MP spent" and spending.blocks[1].stats[4][2] == "10")
assert(spending.blocks[1].stats[5][1] == "Healing per MP" and spending.blocks[1].stats[5][2] == "79")
assert(heal.blocks[1].stats[5][2] == "-")
print("meter_view ok")
