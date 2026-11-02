-- Readable names for the three courses in the simulator menu.
--
-- The courses use their own text keys
-- ($menu_Colosseum_CourseTitle_COL99_TrainingDummy_<Mode>, ..._CourseFlavor_...),
-- which are not in the game's text table, so the menu would show them blank.
-- Rather than edit Text/US/Resident_TxtRes (other mods replace that whole
-- file), this swaps the keys for plain text in the menu's text blocks, which
-- render plain strings as they are.
local M = {}

M.NAMES = {
    DPS = {
        title = "Training Dummy: DPS",
        flavor = "A dummy that cannot be defeated, stays still and never fights back. "
            .. "Practise your damage rotation and watch your DPS on screen. F7 resets the meter.",
    },
    Tank = {
        title = "Training Dummy: Tank",
        flavor = "A dummy that cannot be defeated but fights back, and your HP refills. "
            .. "Practise guarding and evading and watch the damage you take (DTPS). F7 resets the meter.",
    },
    Heal = {
        title = "Training Dummy: Healing",
        flavor = "A dummy that can't be defeated and can't hurt you. Your whole party is held at 1 HP: "
            .. "attack it to build ATB, heal them and watch your healing per second (HPS). F7 resets the meter.",
    },
}

-- Set by main.lua to its debug trace (key, message).
M.trace = function() end

local TITLE = "^%$menu_Colosseum_CourseTitle_COL99_TrainingDummy_(%a+)$"
local FLAVOR = "^%$menu_Colosseum_CourseFlavor_COL99_TrainingDummy_(%a+)$"

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end

-- The mode a title key or a replaced title names, for telling courses apart.
function M.mode_of(text)
    if type(text) ~= "string" then return nil end
    local mode = text:match(TITLE)
    if M.NAMES[mode] then return mode end
    for key, names in pairs(M.NAMES) do
        if text == names.title then return key end
    end
    return nil
end

-- Widgets the menu's hooks reported, kept only for the next few passes:
-- the hooks run before the game fills the text, and transient widgets can't
-- be found again by path.
local PASSES = 8 -- about 1.6 s at the default tick
local pending = {menu = nil, passes = 0}

-- Called from the simulator menu's hooks with the menu.
function M.remember(menu)
    if valid(menu) then pending.menu = menu end
    pending.passes = PASSES
end

local function replace(block)
    if not valid(block) then return end
    local text = safe(function() return block:GetText():ToString() end)
    if type(text) ~= "string" then return end
    local mode, field = text:match(TITLE), "title"
    if not M.NAMES[mode] then mode, field = text:match(FLAVOR), "flavor" end
    if M.NAMES[mode] then
        local wanted = M.NAMES[mode][field]
        -- EndTextBlock:SetText takes a string; a plain TextBlock takes FText.
        local ok, err = pcall(function() block:SetText(wanted) end)
        if not ok then
            M.trace("text_set_string", tostring(err))
            ok, err = pcall(function() block:SetText(FText(wanted)) end)
            if not ok then M.trace("text_set_ftext", tostring(err)) end
        end
        return 1
    end
    return 0
end

-- The list rows (VR_ListItem.Txt_Name) and the description
-- (InfoWindow.Txt_Info) are Blueprint widgets with no reflected path to them
-- (UUserWidget:GetWidgetFromName is not exposed in this game), so they are
-- found by scanning the text blocks, at most every SCAN_GAP passes while the
-- menu is reporting events. Only blocks showing one of our keys change.
local SCAN_GAP = 3
local since_scan = SCAN_GAP

local function scan()
    local replaced = 0
    for _, block in ipairs(safe(FindAllOf, "EndTextBlock") or {}) do
        replaced = replaced + (replace(block) or 0)
    end
    return replaced
end

-- One pass over the menu's own title fields, plus a throttled scan; the
-- references are dropped after the last pass.
-- True while the simulator menu has text waiting to be replaced.
function M.has_work()
    return pending.passes > 0
end

function M.apply()
    since_scan = since_scan + 1
    if pending.passes <= 0 then return end
    pending.passes = pending.passes - 1
    local menu, replaced = pending.menu, 0
    if valid(menu) then
        local info = safe(function() return menu.InfoWindow end)
        replaced = (replace(safe(function() return info.Txt_CourseTitle end)) or 0)
            + (replace(safe(function() return menu.Txt_TitleCourse end)) or 0)
    end
    if since_scan >= SCAN_GAP then
        since_scan = 0
        replaced = replaced + scan()
    end
    if replaced > 0 then M.trace("text_apply", "replaced " .. replaced) end
    if pending.passes == 0 then pending.menu = nil end
end

return M
