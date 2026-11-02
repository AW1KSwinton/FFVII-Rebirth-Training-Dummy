-- The on-screen meter: plain UMG widgets built at runtime, so the mod needs no Blueprint assets, drawn with the
-- game's own HUD sprites and colours so it sits with the party panels. Text uses the engine's Roboto: the game's
-- EndTextBlock and EndImage draw nothing when created at runtime, and its bitmap fonts only work with them.
-- Draws a plain view table (see meter_view.lua). Called on the game thread.
local M = {}

local WIDTH, PAD = 404, 18
local LABEL = {R = 0.68, G = 0.84, B = 0.95, A = 1}   -- a brighter take on the party panel's "HP" label, for this smaller text
local WHITE = {R = 1, G = 1, B = 1, A = 1}
local DIM = {R = 0.62, G = 0.70, B = 0.76, A = 1}
local BAR = {R = 0.45, G = 0.90, B = 1.00, A = 1}     -- the ATB gauge's teal, brightened against the blue panel
local SHADOW = {R = 0, G = 0, B = 0, A = 0.6}
local SPRITES = "/Game/Menu/Resident/Texture/"
local VISIBLE, COLLAPSED = 3, 1                       -- ESlateVisibility: HitTestInvisible, Collapsed
local RIGHT = 2                                       -- ETextJustify
local BLOCKS, STATS, BARS = 2, 8, 3                   -- two blocks on the Tank course; five stats at most on Healing; a party of three
local GAUGE_BACK = {R = 0.04, G = 0.09, B = 0.14, A = 0.9}

local ui = nil

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function find(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end
local function sprite(name)
    return find(SPRITES .. name .. "." .. name)
end

local function new_name(self, prefix)
    self.count = self.count + 1
    return FName("TrainingDummy" .. prefix .. self.count)
end

local function add_image(self, resource, margin, tint)
    local image = StaticConstructObject(self.image_class, self.tree, new_name(self, "Image"))
    if resource then
        image:SetBrushResourceObject(resource)
        image.Brush.DrawAs = 1
        image.Brush.Margin = margin
    end
    image:SetColorAndOpacity(tint or WHITE)
    local slot = self.canvas:AddChildToCanvas(image)
    slot:SetAutoSize(false)
    return {widget = image, slot = slot}
end

local function add_text(self, size, color, justify)
    local text = StaticConstructObject(self.text_class, self.tree, new_name(self, "Text"))
    text.Font.Size = size
    text.Font.TypefaceFontName = FName("Regular")
    text:SetColorAndOpacity({SpecifiedColor = color, ColorUseRule = 0})
    text:SetShadowOffset({X = 2, Y = 1})
    text:SetShadowColorAndOpacity(SHADOW)
    if justify then text:SetJustification(justify) end
    local slot = self.canvas:AddChildToCanvas(text)
    slot:SetAutoSize(false)
    return {widget = text, slot = slot, shown = nil}
end

local function create(config, world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    local text_class, image_class = find("/Script/UMG.TextBlock"), find("/Script/UMG.Image")
    if not (statics and library and widget_class and text_class and image_class) then return nil, "UMG classes not found" end
    local controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    if not valid(controller) then return nil, "no player controller" end
    local widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(widget) then return nil, "Create failed" end

    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), widget, FName("TrainingDummyTree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("TrainingDummyCanvas"))
    tree.RootWidget = canvas
    local self = {widget = widget, tree = tree, canvas = canvas, text_class = text_class, image_class = image_class,
        x = config.overlay_x, y = config.overlay_y, count = 0, heads = {}, rows = {}, bars = {}, rules = {}}

    -- Everything is made up front; rows that aren't needed are collapsed. Drawn in this order, back to front.
    self.panel = add_image(self, sprite("U_Status_Base_01"), {Left = 0, Top = 0.3, Right = 0, Bottom = 0.3}, {R = 1, G = 1, B = 1, A = 0.95})
    for i = 1, BLOCKS do self.rules[i] = add_image(self, nil, nil, {R = 0.8, G = 0.92, B = 1, A = 0.45}) end
    self.header = add_text(self, 20, WHITE)
    self.timer = add_text(self, 16, DIM, RIGHT)
    self.hint = add_text(self, 13, DIM)
    local gauge = sprite("U_Gauge_BG_04")
    for i = 1, BARS do
        self.bars[i] = {back = add_image(self, gauge, {Left = 0.5, Top = 0.5, Right = 0.5, Bottom = 0.5}, GAUGE_BACK), fill = add_image(self, nil, nil, BAR)}
    end
    for i = 1, BLOCKS do
        self.heads[i] = {label = add_text(self, 16, WHITE), value = add_text(self, 24, WHITE, RIGHT)}
    end
    for i = 1, STATS + BARS do
        self.rows[i] = {label = add_text(self, 15, LABEL), value = add_text(self, 17, WHITE, RIGHT)}
    end
    widget:AddToViewport(1000)
    widget:SetVisibility(VISIBLE)
    return self
end

local function place(self, item, x, y, w, h)
    -- Each setter is a reflected call on the game thread, so only touch what changed.
    if item.x ~= x or item.y ~= y then
        item.slot:SetPosition({X = self.x + x, Y = self.y + y})
        item.x, item.y = x, y
    end
    if item.w ~= w or item.h ~= h then
        item.slot:SetSize({X = w, Y = h})
        item.w, item.h = w, h
    end
    if item.hidden ~= false then
        item.widget:SetVisibility(VISIBLE)
        item.hidden = false
    end
end

local function collapse(item)
    if item.hidden ~= true then
        item.widget:SetVisibility(COLLAPSED)
        item.hidden = true
    end
end

local function set_text(self, item, value, x, y, w, h)
    if item.shown ~= value then
        item.widget:SetText(FText(value))
        item.shown = value
    end
    place(self, item, x, y, w, h)
end

local function draw(self, view)
    local inner = WIDTH - PAD * 2
    local y = 10
    set_text(self, self.header, view.title, PAD, y, inner - 72, 28)
    set_text(self, self.timer, view.timer, WIDTH - PAD - 72, y + 3, 72, 24)
    y = y + 31
    y = y + 3

    local row, bar = 0, 0
    local function line(label, value)
        row = row + 1
        local pair = self.rows[row]
        if not pair then return end
        set_text(self, pair.label, label, PAD, y + 2, inner * 0.65, 24)
        set_text(self, pair.value, value, PAD + inner * 0.35, y, inner * 0.65, 24)
        y = y + 24
    end
    for index, block in ipairs(view.blocks) do
        if self.rules[index] then
            place(self, self.rules[index], PAD, y, inner, 1)
            y = y + 4
        end
        local head = self.heads[index]
        if head then
            set_text(self, head.label, block.label, PAD, y + 8, inner * 0.75, 26)
            set_text(self, head.value, block.value, PAD + inner * 0.5, y, inner * 0.5, 36)
            y = y + 36
        end
        for _, stat in ipairs(block.stats) do line(stat[1], stat[2]) end
        for _, member in ipairs(block.members) do
            line(member.name, member.value)
            bar = bar + 1
            local pair = self.bars[bar]
            if pair then
                place(self, pair.back, PAD, y, inner, 6)
                place(self, pair.fill, PAD + 1, y + 1, math.max((inner - 2) * member.share, 0), 4)
                y = y + 10
            end
        end
        y = y + 6
    end
    for i = #view.blocks + 1, BLOCKS do
        collapse(self.rules[i]); collapse(self.heads[i].label); collapse(self.heads[i].value)
    end
    for i = row + 1, STATS + BARS do collapse(self.rows[i].label); collapse(self.rows[i].value) end
    for i = bar + 1, BARS do collapse(self.bars[i].back); collapse(self.bars[i].fill) end
    set_text(self, self.hint, view.hint, PAD, y, inner, 20)
    place(self, self.panel, 0, 0, WIDTH, y + 28)
end

function M.show(view, config, world_object)
    if not (ui and valid(ui.widget)) then
        local made, problem = create(config, world_object)
        if not made then
            if M.last_error ~= problem then print("[TrainingDummy] overlay: " .. tostring(problem) .. "\n") end
            M.last_error = problem
            return
        end
        ui = made
        print("[TrainingDummy] overlay created\n")
    end
    draw(ui, view)
end

function M.hide()
    if ui and valid(ui.widget) then safe(function() ui.widget:RemoveFromParent() end) end
    ui = nil
end

return M
