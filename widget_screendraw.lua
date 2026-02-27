------------------------------------------------------------
-- GET INFO
------------------------------------------------------------
function widget:GetInfo()
    return {
        name      = "ScreenDraw",
        desc      = "Local drawing tool with palette, arrows, curved arrows, undo/redo, fullscreen color picker",
        author    = "Kerwin + Copilot",
        date      = "2026",
        license   = "GPLv2",
        layer     = 0,
        enabled   = true,
    }
end

------------------------------------------------------------
-- SAVED STATE (PERSISTENCE)
------------------------------------------------------------
local savedPanelX     = nil
local savedPanelY     = nil
local savedBrushSize  = nil
local savedArrowSize  = nil

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------
local minBrush     = 5
local maxBrush     = 40
local minArrowSize = 50
local maxArrowSize = 240

local brushSize    = 3
local arrowSize    = 30
local drawing      = false

local drawMode       = "free"      -- "free", "arrow", "curved"
local arrowHeadStyle = "lines"     -- "lines" or "triangle"
local snapAngle      = false
local curveFlip      = false       -- manual curve direction toggle

------------------------------------------------------------
-- STROKES + UNDO/REDO
------------------------------------------------------------
local strokes    = {}
local redoStack  = {}

------------------------------------------------------------
-- PANEL / UI LAYOUT
------------------------------------------------------------
local panelX, panelY   = 40, 180
local panelW, panelH   = 380, 300

local draggingPanel    = false
local dragOffsetX      = 0
local dragOffsetY      = 0

local draggingBrush    = false
local draggingArrowSz  = false

local COLOR_BTN_Y      = 225
local sliderY          = 185
local sliderW          = 190
local sliderH          = 10
local arrowSliderY     = 145

local clearY           = 95
local clearW           = 80
local clearH           = 25

local btnW             = 100
local btnH             = 25


local pickerX, pickerY = 0, 0
local pickerW, pickerH = 300, 240
local draggingPicker   = false
local pickerOffsetX    = 0
local pickerOffsetY    = 0


------------------------------------------------------------
-- COLOR PICKER OVERLAY
------------------------------------------------------------
local showColorPicker = false
local currentColor    = {1,0,0,1}

local basicColors = {
    {name="AMBER",   color={1.0, 0.75, 0.0, 1}},
    {name="BROWN",   color={0.6, 0.3, 0.1, 1}},
    {name="COBALT",  color={0.0, 0.28, 0.67, 1}},
    {name="CRIMSON", color={0.86, 0.08, 0.24, 1}},
    {name="CYAN",    color={0.0, 1.0, 1.0, 1}},
    {name="MAGENTA", color={1.0, 0.0, 1.0, 1}},
    {name="LIME",    color={0.75, 1.0, 0.0, 1}},
    {name="INDIGO",  color={0.29, 0.0, 0.51, 1}},
    {name="GREEN",   color={0.0, 0.6, 0.0, 1}},
    {name="EMERALD", color={0.31, 0.78, 0.47, 1}},
    {name="MAUVE",   color={0.88, 0.69, 1.0, 1}},
    {name="OLIVE",   color={0.5, 0.5, 0.0, 1}},
    {name="ORANGE",  color={1.0, 0.5, 0.0, 1}},
    {name="PINK",    color={1.0, 0.75, 0.8, 1}},
    {name="RED",     color={1.0, 0.0, 0.0, 1}},
    {name="SIENNA",  color={0.53, 0.18, 0.09, 1}},
    {name="STEEL",   color={0.27, 0.51, 0.71, 1}},
    {name="TEAL",    color={0.0, 0.5, 0.5, 1}},
    {name="VIOLET",  color={0.56, 0.0, 1.0, 1}},
    {name="YELLOW",  color={1.0, 1.0, 0.0, 1}},
}

function widget:DrawWorld()

--------------------------------------------------------
-- SHADOW PASS (draw first)
--------------------------------------------------------
for _, s in ipairs(strokes) do
    gl.Color(0, 0, 0, 0.35)
    gl.LineWidth(s.size + 1)

    gl.BeginEnd(GL.LINE_STRIP, function()
        for _, p in ipairs(s.points) do
            if p[1] and p[2] and p[3] then
                local gy = Spring.GetGroundHeight(p[1], p[3])
                gl.Vertex(p[1], gy + 1, p[3])
            end
        end
    end)

    if s.arrow then
        local tipX, tipY, tipZ = s.arrow.tipX, s.arrow.tipY, s.arrow.tipZ
        local gy = Spring.GetGroundHeight(tipX, tipZ)

        local dx, dy = s.arrow.dirX, s.arrow.dirY
        local size = arrowSize

        local angle = math.rad(30)
        local sinA, cosA = math.sin(angle), math.cos(angle)

        local lx = -dx*cosA - dy*sinA
        local lz = -dy*cosA + dx*sinA
        local rx = -dx*cosA + dy*sinA
        local rz = -dy*cosA - dx*sinA

        gl.BeginEnd(GL.LINES, function()
            gl.Vertex(tipX, gy + 1, tipZ)
            gl.Vertex(tipX + lx*size, gy + 1, tipZ + lz*size)

            gl.Vertex(tipX, gy + 1, tipZ)
            gl.Vertex(tipX + rx*size, gy + 1, tipZ + rz*size)
        end)
    end
end


    --------------------------------------------------------
    -- MAIN DRAW PASS (colored strokes)
    --------------------------------------------------------
    local lift = 16   -- raise drawing above ground so shadow is visible

    for _, s in ipairs(strokes) do
        gl.Color(s.color)
        gl.LineWidth(s.size)

        gl.BeginEnd(GL.LINE_STRIP, function()
            for _, p in ipairs(s.points) do
                if p[1] and p[2] and p[3] then
                    gl.Vertex(p[1], p[2] + lift, p[3])
                end
            end
        end)

        if s.arrow then
            local tipX, tipY, tipZ = s.arrow.tipX, s.arrow.tipY, s.arrow.tipZ
            local dx, dy = s.arrow.dirX, s.arrow.dirY
            local size = arrowSize

            local angle = math.rad(30)
            local sinA, cosA = math.sin(angle), math.cos(angle)

            local lx = -dx*cosA - dy*sinA
            local lz = -dy*cosA + dx*sinA
            local rx = -dx*cosA + dy*sinA
            local rz = -dy*cosA - dx*sinA

            gl.BeginEnd(GL.LINES, function()
                gl.Vertex(tipX, tipY + lift, tipZ)
                gl.Vertex(tipX + lx*size, tipY + lift, tipZ + lz*size)

                gl.Vertex(tipX, tipY + lift, tipZ)
                gl.Vertex(tipX + rx*size, tipY + lift, tipZ + rz*size)
            end)
        end
    end

    --------------------------------------------------------
    -- RESTORE GL STATE
    --------------------------------------------------------
    gl.Color(1,1,1,1)
    gl.LineWidth(1)
end


------------------------------------------------------------
-- VIEW GEOMETRY + INITIALIZE
------------------------------------------------------------
local vsx, vsy = 0, 0

function widget:ViewResize(vx, vy)
    vsx, vsy = vx, vy
end

 function widget:GetConfigData()
    return {
        panelX = savedPanelX,
        panelY = savedPanelY,
        brushSize = savedBrushSize,
        arrowSize = savedArrowSize,
    }
end

function widget:SetConfigData(data)
    if data.panelX then savedPanelX = data.panelX end
    if data.panelY then savedPanelY = data.panelY end
    if data.brushSize then savedBrushSize = data.brushSize end
    if data.arrowSize then savedArrowSize = data.arrowSize end
end



function widget:Initialize()
    vsx, vsy = Spring.GetViewGeometry()

    if savedPanelX then panelX = savedPanelX end
    if savedPanelY then panelY = savedPanelY end
    if savedBrushSize then brushSize = savedBrushSize end
    if savedArrowSize then arrowSize = savedArrowSize end
end

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function InRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx+rw and y >= ry and y <= ry+rh
end

local function normalize(dx, dy)
    local len = math.sqrt(dx*dx + dy*dy)
    if len == 0 then return 0, 0, 0 end
    return dx/len, dy/len, len
end

local function quantizeAngle(dx, dy)
    local ang = math.atan2(dy, dx)
    local step = math.rad(2)   -- 5° increments
    ang = math.floor((ang + step/2) / step) * step
    return math.cos(ang), math.sin(ang)
end


------------------------------------------------------------
-- MOUSE PRESS
------------------------------------------------------------
function widget:MousePress(x, y, button)
    if button ~= 1 then return false end

    --------------------------------------------------------
    -- COLOR PICKER OVERLAY (20‑color grid)
    --------------------------------------------------------
    if showColorPicker then
        local sw, sh = 80, 60
        local cols, rows = 5, 4
        local startX = (vsx - cols*sw) / 2
        local startY = (vsy - rows*sh) / 2

        for i, entry in ipairs(basicColors) do
            local cx = startX + ((i-1) % cols) * sw
            local cy = startY + math.floor((i-1)/cols) * sh

            if InRect(x, y, cx, cy, sw, sh) then
                currentColor = {
                    entry.color[1],
                    entry.color[2],
                    entry.color[3],
                    entry.color[4]
                }
                showColorPicker = false
                return true
            end
        end

        return true
    end

	--------------------------------------------------------
	-- UNDO / REDO (anchored to bottom)
	--------------------------------------------------------
	local bottomPadding = 12
	local undoY = panelY + bottomPadding

	local undoX = panelX + panelW - (btnW*2 + 20)
	if InRect(x, y, undoX, undoY, btnW, btnH) then
		if #strokes > 0 then
			redoStack[#redoStack+1] = strokes[#strokes]
			strokes[#strokes] = nil
		end
		return true
	end

	local redoX = panelX + panelW - (btnW + 10)
	if InRect(x, y, redoX, undoY, btnW, btnH) then
		if #redoStack > 0 then
			strokes[#strokes+1] = redoStack[#redoStack]
			redoStack[#redoStack] = nil
		end
		return true
	end

    --------------------------------------------------------
    -- PANEL INTERACTION
    --------------------------------------------------------
    if InRect(x, y, panelX, panelY, panelW, panelH) then
        local lx = x - panelX
        local ly = y - panelY

----------------------------------------------------
-- CLOSE BUTTON [X] — disable widget
----------------------------------------------------
local closeX = panelW - 24
local closeY = panelH - 24
if InRect(lx, ly, closeX, closeY, 20, 20) then
	savedPanelX = panelX
	savedPanelY = panelY
	savedBrushSize = brushSize
	savedArrowSize = arrowSize
	widgetHandler:RemoveWidget(self)
    return true
end


        ----------------------------------------------------
        -- COLOR BUTTON
        ----------------------------------------------------
-- Color button now at lower-left
local bottomPadding = 12
local colorBtnX = 10
local colorBtnY = bottomPadding
if InRect(lx, ly, colorBtnX, colorBtnY, btnW, btnH) then
            showColorPicker = true
            return true
        end

        ----------------------------------------------------
        -- BRUSH SLIDER
        ----------------------------------------------------
        if InRect(lx, ly, 10, sliderY, sliderW, sliderH) then
            local rel = math.max(0, math.min(1, (lx - 10) / sliderW))
            brushSize = minBrush + (maxBrush - minBrush) * rel
            draggingBrush = true
            return true
        end

        ----------------------------------------------------
        -- ARROW SIZE SLIDER
        ----------------------------------------------------
        if InRect(lx, ly, 10, arrowSliderY, sliderW, sliderH) then
            local rel = math.max(0, math.min(1, (lx - 10) / sliderW))
            arrowSize = minArrowSize + (maxArrowSize - minArrowSize) * rel
            draggingArrowSz = true
            return true
        end

        ----------------------------------------------------
        -- CLEAR BUTTON
        ----------------------------------------------------
        if InRect(lx, ly, 10, clearY, clearW, clearH) then
            strokes = {}
            redoStack = {}
            return true
        end

        ----------------------------------------------------
        -- MODE BUTTON (Free → Arrow → Curved → Free)
        ----------------------------------------------------
        local modeX = 10 + clearW + 10
        if InRect(lx, ly, modeX, clearY, btnW, btnH) then
            if drawMode == "free" then
                drawMode = "arrow"
            elseif drawMode == "arrow" then
                drawMode = "curved"
            else
                drawMode = "free"
            end
            return true
        end

        -- CURVE FLIP BUTTON
        if drawMode == "curved" then
            local flipX = modeX + btnW + 10
            local flipY = clearY
            if InRect(lx, ly, flipX, flipY, 30, btnH) then
                curveFlip = not curveFlip
                return true
            end
        end


        ----------------------------------------------------
        -- HEAD STYLE BUTTON
        ----------------------------------------------------
        local styleX = modeX + btnW + 10
        if InRect(lx, ly, styleX, clearY, btnW, btnH) then
            arrowHeadStyle = (arrowHeadStyle == "lines") and "triangle" or "lines"
            return true
        end

        ----------------------------------------------------
        -- SNAP BUTTON
        ----------------------------------------------------
        local snapY = clearY - (btnH + 8)
        if InRect(lx, ly, 10, snapY, btnW, btnH) then
            snapAngle = not snapAngle
            return true
        end

        ----------------------------------------------------
        -- DRAG PANEL
        ----------------------------------------------------
        draggingPanel = true
        dragOffsetX = x - panelX
        dragOffsetY = y - panelY
        return true
    end

    --------------------------------------------------------
    -- START DRAWING ON GAME SCREEN
    --------------------------------------------------------
    drawing = true
    local type, p = Spring.TraceScreenRay(x, y, true)
    if type ~= "ground" then return true end

    strokes[#strokes+1] = {
        mode  = drawMode,
        color = { currentColor[1], currentColor[2], currentColor[3], currentColor[4] },
        size  = brushSize,
        points = { {p[1], p[2], p[3]} }  -- world coords
    }

    return true
end

------------------------------------------------------------
-- KEYPRESS (Curve Flip Toggle)
------------------------------------------------------------
function widget:KeyPress(key, mods, isRepeat)
    if key == string.byte('f') or key == string.byte('F') then
        curveFlip = not curveFlip
        return true
    end
end

------------------------------------------------------------
-- MOUSE MOVE
------------------------------------------------------------
function widget:MouseMove(x, y, dx, dy, button)
    --------------------------------------------------------
    -- DRAG PANEL
    --------------------------------------------------------
    if draggingPanel then
        panelX = x - dragOffsetX
        panelY = y - dragOffsetY
        return
    end

    --------------------------------------------------------
    -- BRUSH SLIDER DRAG
    --------------------------------------------------------
    if draggingBrush then
        local lx = x - panelX
        local rel = math.max(0, math.min(1, (lx - 10) / sliderW))
        brushSize = minBrush + (maxBrush - minBrush) * rel
        return
    end

    --------------------------------------------------------
    -- ARROW SIZE SLIDER DRAG
    --------------------------------------------------------
    if draggingArrowSz then
        local lx = x - panelX
        local rel = math.max(0, math.min(1, (lx - 10) / sliderW))
        arrowSize = minArrowSize + (maxArrowSize - minArrowSize) * rel
        return
    end

    --------------------------------------------------------
    -- NORMAL DRAWING
    --------------------------------------------------------
    if drawing and strokes[#strokes] then
        local type, p = Spring.TraceScreenRay(x, y, true)
    if type == "ground" then
        strokes[#strokes].points[#strokes[#strokes].points+1] = {p[1], p[2], p[3]}
    end

        end
    end


------------------------------------------------------------
-- MOUSE RELEASE
------------------------------------------------------------
function widget:MouseRelease(x, y, button)

    --------------------------------------------------------
    -- STOP DRAGGING STATES + SAVE PERSISTENT VALUES
    --------------------------------------------------------
    draggingPanel   = false
    draggingBrush   = false
    draggingArrowSz = false

    savedPanelX = panelX
    savedPanelY = panelY
    savedBrushSize = brushSize
    savedArrowSize = arrowSize

    --------------------------------------------------------
    -- STOP DRAWING IF NOTHING ACTIVE
    --------------------------------------------------------
    if not drawing or not strokes[#strokes] then
        drawing = false
        return
    end

    --------------------------------------------------------
    -- FINALIZE STROKE
    --------------------------------------------------------
    local s = strokes[#strokes]
    drawing = false

    -- Only arrow + curved strokes need arrowhead processing
    if (s.mode ~= "arrow" and s.mode ~= "curved") or #s.points < 2 then
        return
    end

    local p1 = s.points[1]
    local p2 = s.points[#s.points]

    --------------------------------------------------------
    -- TRUE DRAG DIRECTION (before smoothing)
    --------------------------------------------------------
    local dragDx = p2[1] - p1[1]
    local dragDy = p2[3] - p1[3]   -- use XZ plane for direction
    local dx, dy, len = normalize(dragDx, dragDy)

    if len == 0 then return end

    if snapAngle then
        dx, dy = quantizeAngle(dx, dy)
    end

    --------------------------------------------------------
    -- CURVED ARROW PROCESSING
    --------------------------------------------------------
    if s.mode == "curved" then
    -- midpoint in XZ plane
    local midx = (p1[1] + p2[1]) * 0.5
    local midz = (p1[3] + p2[3]) * 0.5

    -- perpendicular in XZ plane
    local nx, nz = -dy, dx

    -- manual flip
    if curveFlip then
        nx = -nx
        nz = -nz
    end

    -- auto flip
    if dragDx < 0 then
        nx = -nx
        nz = -nz
    end

    -- control point in XZ plane
    local offset = len * 0.35
    local cx = midx + nx * offset
    local cz = midz + nz * offset


        -- generate bezier curve in WORLD XZ plane
    local pts = {}
    local steps = 32
    for i = 0, steps do
        local t = i / steps
        local u = 1 - t

        -- bezier in XZ plane
        local xq = u*u*p1[1] + 2*u*t*cx + t*t*p2[1]
        local zq = u*u*p1[3] + 2*u*t*cz + t*t*p2[3]

        -- sample terrain height
        local yq = Spring.GetGroundHeight(xq, zq)

        pts[#pts+1] = {xq, yq, zq}
    end

        s.points = pts

        -- recompute final direction for arrowhead
        local q1 = pts[#pts-1]
        local q2 = pts[#pts]

        -- direction in XZ plane
        dx, dy = normalize(q2[1] - q1[1], q2[3] - q1[3])

        if snapAngle then
            dx, dy = quantizeAngle(dx, dy)
        end
        p2 = q2

    end

    --------------------------------------------------------
    -- FINAL ARROWHEAD DATA (3D WORLD COORDS)
    --------------------------------------------------------
    s.arrow = {
        tipX = p2[1],
        tipY = p2[2],
        tipZ = p2[3],   -- REQUIRED or it will crash
        dirX = dx,
        dirY = dy,
    }

end

------------------------------------------------------------
-- DRAW SCREEN
------------------------------------------------------------
function widget:DrawScreen()
    gl.Texture(false)

    --------------------------------------------------------
    -- COLOR PICKER OVERLAY (20‑color grid)
    --------------------------------------------------------
    if showColorPicker then
        gl.Color(0,0,0,0.75)
        gl.Rect(0,0,vsx,vsy)

        local sw, sh = 80, 60
        local cols, rows = 5, 4
        local startX = (vsx - cols*sw) / 2
        local startY = (vsy - rows*sh) / 2

        for i, entry in ipairs(basicColors) do
            local cx = startX + ((i-1) % cols) * sw
            local cy = startY + math.floor((i-1)/cols) * sh

            gl.Color(entry.color)
            gl.Rect(cx, cy, cx+sw, cy+sh)

            gl.Color(1,1,1,1)
            gl.Text(entry.name, cx+10, cy+20, 14, "bo")
        end

        gl.Color(1,1,1,1)
        gl.LineWidth(1)
    end

    --------------------------------------------------------
    -- PANEL BACKGROUND
    --------------------------------------------------------
    gl.Color(0,0,0,0.55)
    gl.Rect(panelX, panelY, panelX+panelW, panelY+panelH)

    --------------------------------------------------------
    -- TITLE BAR
    --------------------------------------------------------
    gl.Color(1,1,1,0.15)
    gl.Rect(panelX, panelY+panelH-28, panelX+panelW, panelY+panelH)

    gl.Color(1,1,1,1)
    local title = "Armis71 Draw Tool"
    local tSize = 16
    local tw = gl.GetTextWidth(title) * tSize
    local tx = panelX + (panelW - tw) * 0.5
    local ty = panelY + panelH - 22
    gl.Text(title, tx, ty, tSize, "o")

	--------------------------------------------------------
	-- CLOSE BUTTON [X]
	--------------------------------------------------------
	local closeX = panelX + panelW - 24
	local closeY = panelY + panelH - 24

	gl.Color(0.3,0.1,0.1,1)
	gl.Rect(closeX, closeY, closeX+20, closeY+20)

	gl.Color(1,1,1,1)
	gl.Text("X", closeX+6, closeY+4, 16, "o")

	--------------------------------------------------------
	-- UNDO / REDO (anchored to bottom)
	--------------------------------------------------------
	local bottomPadding = 12
	local undoY = panelY + bottomPadding

	local undoX = panelX + panelW - (btnW*2 + 20)
	gl.Color(0.2,0.2,0.2,1)
	gl.Rect(undoX, undoY, undoX+btnW, undoY+btnH)
	gl.Color(1,1,1,1)
	gl.Text("Undo", undoX+8, undoY+7, 12, "o")

	local redoX = panelX + panelW - (btnW + 10)
	gl.Color(0.2,0.2,0.2,1)
	gl.Rect(redoX, undoY, redoX+btnW, undoY+btnH)
	gl.Color(1,1,1,1)
	gl.Text("Redo", redoX+8, undoY+7, 12, "o")

    --------------------------------------------------------
    -- COLOR BUTTON
    --------------------------------------------------------
	-- Move Color button to lower-left next to Undo
	local bottomPadding = 12
	local undoY = panelY + bottomPadding

	local colorBtnX = panelX + 10
	local colorBtnYScreen = undoY

    gl.Color(currentColor[1], currentColor[2], currentColor[3], 0.85)
    gl.Rect(colorBtnX, colorBtnYScreen, colorBtnX+btnW, colorBtnYScreen+btnH)

    gl.Color(1,1,1,1)
    gl.Text("Color...", colorBtnX+10, colorBtnYScreen+7, 14, "o")

    --------------------------------------------------------
    -- BRUSH SIZE SLIDER
    --------------------------------------------------------
    local sx, sy = panelX + 10, panelY + sliderY
    gl.Color(0.2,0.2,0.2,1)
    gl.Rect(sx, sy, sx+sliderW, sy+sliderH)

    local knobX = sx + (brushSize - minBrush)/(maxBrush-minBrush) * sliderW
    gl.Color(1,1,1,1)
    gl.Rect(knobX-6, sy-5, knobX+6, sy+sliderH+5)
    gl.Text("Brush Size", sx, sy+14, 12, "o")

    --------------------------------------------------------
    -- ARROW SIZE SLIDER
    --------------------------------------------------------
    local asx, asy = panelX + 10, panelY + arrowSliderY
    gl.Color(0.2,0.2,0.2,1)
    gl.Rect(asx, asy, asx+sliderW, asy+sliderH)

    local aknobX = asx + (arrowSize - minArrowSize)/(maxArrowSize-minArrowSize) * sliderW
    gl.Color(1,1,1,1)
    gl.Rect(aknobX-6, asy-5, aknobX+6, asy+sliderH+5)
    gl.Text("Arrow Size", asx, asy+14, 12, "o")

    --------------------------------------------------------
    -- BUTTONS (Clear, Mode, Head)
    --------------------------------------------------------
    local cx, cy = panelX + 10, panelY + clearY

    -- CLEAR
    gl.Color(0.3,0.1,0.1,1)
    gl.Rect(cx, cy, cx+clearW, cy+clearH)
    gl.Color(1,1,1,1)
    gl.Text("Clear", cx+12, cy+7, 14, "o")

    -- MODE
    local modeX = cx + clearW + 10
    gl.Color(0.2,0.2,0.2,1)
    gl.Rect(modeX, cy, modeX+btnW, cy+btnH)
    gl.Color(1,1,1,1)

    local modeLabel =
        (drawMode == "free")   and "Mode: Free"   or
        (drawMode == "arrow")  and "Mode: Arrow"  or
                                 "Mode: Curved"

    gl.Text(modeLabel, modeX+6, cy+7, 12, "o")

    --------------------------------------------------------
    -- CURVE FLIP INDICATOR (^ / v)
    --------------------------------------------------------
    if drawMode == "curved" then
        local flipX = modeX + btnW + 10
        local flipY = cy

        gl.Color(0.2,0.2,0.2,1)
        gl.Rect(flipX, flipY, flipX+30, flipY+btnH)

        gl.Color(1,1,1,1)
        local flipArrow = curveFlip and "^" or "v"
        gl.Text(flipArrow, flipX+12, flipY+7, 14, "o")
    end

    --------------------------------------------------------
    -- HEAD STYLE BUTTON
    --------------------------------------------------------
    local styleX = modeX + btnW + 10 + 30 + 10
    gl.Color(0.2,0.2,0.2,1)
    gl.Rect(styleX, cy, styleX+btnW, cy+btnH)
    gl.Color(1,1,1,1)
    local styleLabel = (arrowHeadStyle == "lines") and "Head: Lines" or "Head: Tri"
    gl.Text(styleLabel, styleX+6, cy+7, 12, "o")

    --------------------------------------------------------
    -- SNAP BUTTON
    --------------------------------------------------------
    local snapY = clearY - (btnH + 8)
    local snapX = panelX + 10
    local snapYScreen = panelY + snapY

    gl.Color(0.2,0.2,0.2,1)
    gl.Rect(snapX, snapYScreen, snapX+btnW, snapYScreen+btnH)
    gl.Color(1,1,1,1)
    local snapLabel = snapAngle and "Snap: On" or "Snap: Off"
    gl.Text(snapLabel, snapX+6, snapYScreen+7, 12, "o")

--[[     --------------------------------------------------------
    -- DRAW ALL STROKES
    --------------------------------------------------------
    for _, s in ipairs(strokes) do
        gl.Color(s.color)
        gl.LineWidth(s.size)

        gl.BeginEnd(GL.LINE_STRIP, function()
            for _, p in ipairs(s.points) do
                gl.Vertex(p[1], p[2])
            end
        end)

        if s.arrow then
            local tipX, tipY = s.arrow.tipX, s.arrow.tipY
            local dx, dy = s.arrow.dirX, s.arrow.dirY
            local size = arrowSize

            if arrowHeadStyle == "lines" then
                local angle = math.rad(30)
                local sinA, cosA = math.sin(angle), math.cos(angle)
                local lx = -dx*cosA - dy*sinA
                local ly = -dy*cosA + dx*sinA
                local rx = -dx*cosA + dy*sinA
                local ry = -dy*cosA - dx*sinA

                gl.BeginEnd(GL.LINES, function()
                    gl.Vertex(tipX, tipY)
                    gl.Vertex(tipX + lx*size, tipY + ly*size)
                    gl.Vertex(tipX, tipY)
                    gl.Vertex(tipX + rx*size, tipY + ry*size)
                end)
            else
                local angle = math.rad(30)
                local sinA, cosA = math.sin(angle), math.cos(angle)
                local lx = -dx*cosA - dy*sinA
                local ly = -dy*cosA + dx*sinA
                local rx = -dx*cosA + dy*sinA
                local ry = -dy*cosA - dx*sinA

                gl.BeginEnd(GL.TRIANGLES, function()
                    gl.Vertex(tipX, tipY)
                    gl.Vertex(tipX + lx*size*0.7, tipY + ly*size*0.7)
                    gl.Vertex(tipX + rx*size*0.7, tipY + ry*size*0.7)
                end)
            end
        end
    end ]]

    --------------------------------------------------------
    -- RESTORE GL STATE
    --------------------------------------------------------
    gl.Color(1,1,1,1)
    gl.LineWidth(1)
    gl.Texture(false)
	
	
	
end

------------------------------------------------------------
-- SHUTDOWN
------------------------------------------------------------
function widget:Shutdown()
    -- No OpenGL calls allowed here
end

