-- On-screen meter text: a plain UMG UserWidget built at runtime (canvas +
-- text block), so the mod needs no Blueprint assets. Called on the game thread.
local M = {}
local widget, text_block = nil, nil

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

local function create(config, world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    if not (statics and library and widget_class) then return nil, "UMG classes not found" end
    local controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    if not valid(controller) then return nil, "no player controller" end

    local new_widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(new_widget) then return nil, "Create failed" end
    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), new_widget, FName("TrainingDummyTree"))
    new_widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("TrainingDummyCanvas"))
    tree.RootWidget = canvas
    local text = StaticConstructObject(find("/Script/UMG.TextBlock"), tree, FName("TrainingDummyText"))
    local slot = canvas:AddChildToCanvas(text)
    slot:SetAutoSize(true)
    slot:SetPosition({X = config.overlay_x, Y = config.overlay_y})
    text:SetShadowOffset({X = 2, Y = 2})
    text:SetShadowColorAndOpacity({R = 0, G = 0, B = 0, A = 0.85})
    new_widget:AddToViewport(1000)
    return new_widget, text
end

function M.show(text, config, world_object)
    if not (valid(widget) and valid(text_block)) then
        local made, block_or_error = create(config, world_object)
        if not made then
            if M.last_error ~= block_or_error then print("[TrainingDummy] overlay: " .. tostring(block_or_error) .. "\n") end
            M.last_error = block_or_error
            return
        end
        widget, text_block = made, block_or_error
        print("[TrainingDummy] overlay created\n")
    end
    text_block:SetText(FText(text))
end

function M.hide()
    if valid(widget) then safe(function() widget:RemoveFromParent() end) end
    widget, text_block = nil, nil
end

return M
