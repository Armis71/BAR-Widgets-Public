function widget:GetInfo()
    return {
        name      = "Unified Toggle Menu",
        desc      = "Vertical ON/OFF menu for Top Bar, Eco Graph, and E-CONV",
        author    = "Kerwin + Copilot",
        date      = "2026",
        license   = "GPLv2",
        layer     = 999999,
        enabled   = true,
    }
end

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local vsx, vsy = Spring.GetViewGeometry()

local BUTTON_W = 120
local BUTTON_H = 100
local BUTTON_SPACING = 2

local bgColor = {0, 0, 0, 0.55}
local borderColor = {1, 1, 1, 0.35}

------------------------------------------------------------
-- FIRST-TIME CENTERING (correct logic)
------------------------------------------------------------
local savedX = Spring.GetConfigInt("unified_menu_x", nil, false)
local savedY = Spring.GetConfigInt("unified_menu_y", nil, false)

local posX, posY

if savedX == nil or savedY == nil then
    -- ⭐ Center horizontally
    posX = math.floor((vsx - BUTTON_W) * 0.5)

    -- ⭐ Center vertically (3 buttons + spacing)
    local totalH = BUTTON_H * 3 + BUTTON_SPACING * 2
    posY = math.floor((vsy - totalH) * 0.5)
else
    posX = savedX
    posY = savedY
end

------------------------------------------------------------
-- DRAG STATE
------------------------------------------------------------
local dragging = false
local dragMoved = false
local dragStartX = 0
local dragStartY = 0
local dragOffsetX = 0
local dragOffsetY = 0

local menuRect = nil

------------------------------------------------------------
-- TARGET WIDGET NAMES
------------------------------------------------------------
local WIDGET_TOPBAR = "Top Bar"
local WIDGET_ECO    = "Eco Graph"
local WIDGET_ECONV  = "Energy Conversion"

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local glColor = gl.Color
local glRect  = gl.Rect
local glText  = gl.Text

local function InRect(mx, my, r)
    return mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2
end

local function WidgetEnabled(name)
    return Spring.GetConfigInt("widget_" .. name, 1) == 1
end

local function ToggleWidget(name)
    if WidgetEnabled(name) then
        Spring.SendCommands("luaui disablewidget " .. name)
        Spring.SetConfigInt("widget_" .. name, 0)
    else
        Spring.SendCommands("luaui enablewidget " .. name)
        Spring.SetConfigInt("widget_" .. name, 1)
    end
end

------------------------------------------------------------
-- VIEW RESIZE
------------------------------------------------------------
function widget:ViewResize(x, y)
    vsx, vsy = x, y
end

------------------------------------------------------------
-- DRAW BUTTON
------------------------------------------------------------
local function DrawButton(x1, y1, label, enabled)
    local x2 = x1 + BUTTON_W
    local y2 = y1 + BUTTON_H

    -- Background
    glColor(bgColor)
    glRect(x1, y1, x2, y2)

    -- Separator border (top + bottom)
    glColor(borderColor)
    glRect(x1, y1, x2, y1 + 1)
    glRect(x1, y2 - 1, x2, y2)

    -- Text
    local cx = (x1 + x2) * 0.5
    local cy = (y1 + y2) * 0.5

    glColor(1, 1, 1, 1)
    glText(label, cx, cy + 10, 20, "oc")

    if enabled then
        glColor(0, 1, 0, 1)
        glText("ON", cx, cy - 20, 26, "oc")
    else
        glColor(1, 0, 0, 1)
        glText("OFF", cx, cy - 20, 26, "oc")
    end
end

------------------------------------------------------------
-- DRAW SCREEN
------------------------------------------------------------
function widget:DrawScreen()
    local x1 = posX
    local y1 = posY

    local totalH = BUTTON_H * 3 + BUTTON_SPACING * 2
    local x2 = x1 + BUTTON_W
    local y2 = y1 + totalH

    menuRect = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}

    --------------------------------------------------------
    -- BUTTON 1: TOP BAR
    --------------------------------------------------------
    DrawButton(
        x1,
        y1 + BUTTON_H * 2 + BUTTON_SPACING * 2,
        "Top Bar",
        WidgetEnabled(WIDGET_TOPBAR)
    )

    --------------------------------------------------------
    -- BUTTON 2: ECO GRAPH
    --------------------------------------------------------
    DrawButton(
        x1,
        y1 + BUTTON_H + BUTTON_SPACING,
        "Eco Graph",
        WidgetEnabled(WIDGET_ECO)
    )

    --------------------------------------------------------
    -- BUTTON 3: E-CONV
    --------------------------------------------------------
    DrawButton(
        x1,
        y1,
        "E-CONV",
        WidgetEnabled(WIDGET_ECONV)
    )
end

------------------------------------------------------------
-- MOUSE
------------------------------------------------------------
function widget:IsAbove(mx, my)
    return menuRect and InRect(mx, my, menuRect)
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end
    if not widget:IsAbove(mx, my) then return false end

    dragging = true
    dragMoved = false
    dragStartX = mx
    dragStartY = my

    dragOffsetX = mx - posX
    dragOffsetY = my - posY
    return true
end

function widget:MouseMove(mx, my, dx, dy, button)
    if dragging then
        if math.abs(mx - dragStartX) > 3 or math.abs(my - dragStartY) > 3 then
            dragMoved = true
        end

        posX = mx - dragOffsetX
        posY = my - dragOffsetY
        return true
    end
end

function widget:MouseRelease(mx, my, button)
    if dragging then
        dragging = false

        Spring.SetConfigInt("unified_menu_x", posX)
        Spring.SetConfigInt("unified_menu_y", posY)

        if not dragMoved and InRect(mx, my, menuRect) then
            local relY = my - posY

            if relY > BUTTON_H * 2 + BUTTON_SPACING * 2 then
                ToggleWidget(WIDGET_TOPBAR)
            elseif relY > BUTTON_H + BUTTON_SPACING then
                ToggleWidget(WIDGET_ECO)
            else
                ToggleWidget(WIDGET_ECONV)
            end
        end

        return true
    end

    return false
end
