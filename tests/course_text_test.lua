-- Plain Lua 5.4 checks for course_text.lua's key/name matching.
local course_text = require("course_text")

assert(course_text.mode_of("$menu_Colosseum_CourseTitle_COL99_TrainingDummy_DPS") == "DPS", "title key")
assert(course_text.mode_of("$menu_Colosseum_CourseTitle_COL99_TrainingDummy_Heal") == "Heal", "heal key")
-- After the menu shows the readable name, the course is still recognised.
assert(course_text.mode_of(course_text.NAMES.Tank.title) == "Tank", "readable name")
assert(course_text.mode_of("$menu_Colosseum_CourseTitle_COL99_TrainingDummy_Boss") == nil, "unknown mode")
assert(course_text.mode_of("$menu_Colosseum_CourseTitle_COL30_SUMMON_Titan") == nil, "vanilla course")
assert(course_text.mode_of(nil) == nil, "no text")
print("course_text_test: ok")
