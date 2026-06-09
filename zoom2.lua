-- zoomto keybind will zoom into the mouse position, unless the mouse button movement is activated
-- Example:
-- bind  Any+sc_;  zoomto 300
-- bind  Any+sc_'  zoomto 10000

function widget:GetInfo()
    return {
        name    = "Zoom Keybinds (Mouse4/5)",
        desc    = "Zoom using mouse4/mouse5 inside BAR",
        author  = "lov (modified by Armis71)",
        date    = "2025",
        license = "GNU GPL v2 or later",
        layer   = 0,
        enabled = true,
        handler = true,
    }
end

---------------------------------------------------------------
-- ⭐ USER‑EDITABLE ZOOM SETTINGS (edit these only)
---------------------------------------------------------------
local ZOOM_IN_DIST        = 1500     -- Normal zoom in
local ZOOM_OUT_DIST       = 6000     -- Normal zoom out
local CTRL_ZOOM_IN_DIST   = 750      -- CTRL + zoom in
local CTRL_ZOOM_OUT_DIST  = 20000    -- CTRL + zoom out (max height)
---------------------------------------------------------------

local smoothnessBoost = 1

----------------------------------------------------------------
-- ZOOM FUNCTION
----------------------------------------------------------------
local function DoZoom(distance, alwaysCenter)
    local newState = {dist = distance, height = distance}

    local cs = Spring.GetCameraState()
    local height = cs.height or cs.dist

    if height > distance then
        local mx, my = Spring.GetMouseState()
        if not alwaysCenter then
            local _, pos = Spring.TraceScreenRay(mx, my, true)
            if pos and pos[1] then
                newState.px = pos[1]
                newState.py = pos[2]
                newState.pz = pos[3]
            end
        end
    end

    local transitionTime = 0.1
    if WG['options'] and WG['options'].getCameraSmoothness then
        transitionTime = WG['options'].getCameraSmoothness() * smoothnessBoost
    end

    Spring.SetCameraState(newState, transitionTime)

    ----------------------------------------------------------------
    -- RECENTER MOUSE AFTER ZOOM
    -- Works best with Hardware Cursor OFF
    ----------------------------------------------------------------
    local vsx, vsy = Spring.GetViewGeometry()
    Spring.WarpMouse(vsx * 0.5, vsy * 0.5)

    ----------------------------------------------------------------
    -- HARDWARE CURSOR FIX (double MMB)
    ----------------------------------------------------------------
    if distance > height then
        Spring.SendCommands("mousepress 2")
        Spring.SendCommands("mouserelease 2")
        Spring.SendCommands("mousepress 2")
        Spring.SendCommands("mouserelease 2")
    end
end

----------------------------------------------------------------
-- MOUSE HANDLING (Mouse4 = button 4, Mouse5 = button 5)
----------------------------------------------------------------
function widget:MousePress(x, y, button)
    local alt, ctrl, meta, shift = Spring.GetModKeyState()

    if button == 4 then
        -- Zoom IN
        if ctrl then
            DoZoom(CTRL_ZOOM_IN_DIST)
        else
            DoZoom(ZOOM_IN_DIST)
        end
        return true
    end

    if button == 5 then
        -- Zoom OUT
        if ctrl then
            DoZoom(CTRL_ZOOM_OUT_DIST)
        else
            DoZoom(ZOOM_OUT_DIST)
        end
        return true
    end
end

----------------------------------------------------------------
-- OPTIONAL: still support zoomto/zoomtocenter actions
----------------------------------------------------------------
local function zoomTo(_, _, args)
    local dist = args and tonumber(args[1])
    if dist then
        DoZoom(dist)
    end
end

local function zoomToCenter(_, _, args)
    local dist = args and tonumber(args[1])
    if dist then
        DoZoom(dist, true)
    end
end

----------------------------------------------------------------
-- INITIALIZE
----------------------------------------------------------------
function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "zoomto", zoomTo, nil, "pmb")
    widgetHandler.actionHandler:AddAction(self, "zoomtocenter", zoomToCenter, nil, "pmb")
end
