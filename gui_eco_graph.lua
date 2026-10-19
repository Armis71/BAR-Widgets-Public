function widget:GetInfo()
    return {
        name      = "Eco Graph",
        desc      = "Top Bar widget replacement. Tracks your Metal and Energy economy in real time, helping you monitor income, storage, and usage so you can make better macro decisions.",
        author    = "Copilot + Armis71",
        date      = "2026-06-05",
        version   = "v5.0",
        license   = "GPL v2 or later",
        layer     = -999999,
        enabled   = true,
    }
end



-- GLOBAL FONT SCALE (shrink everything proportionally)
local FONT_SCALE = 0.99  -- This will affect most of the text size in the widget. Try 0.95, 0.97, 0.995 or 0.999 for different levels of shrinking.

-- Get's Wind Average Information
local windFunctions = VFS.Include('common/wind_functions.lua')

-- Offset to move the Energy Storage BAR left or right
local energyOffset = 70
local metalOffset = -25

--Auto-Share Metal/Energy using the Metal and Energy Bars
local draggingShareIndicator = nil
local draggingShareIndicatorValue = { metal = nil, energy = nil }
local shareIndicatorArea = { metal = {}, energy = {} }

-- Conversion Slider
local draggingConversionIndicator = false
local draggingConversionIndicatorValue = nil
local conversionIndicatorArea = {}

-- Energy to Metal Slider
local convEnergy = 0
local convMetal  = 0
local convUtil   = 0

-- Close/Hide Dual-line Graph with CTRL+RMB or LMB
local hideGraphs = false

-- Toggle M:E Ratio Tooltip to be visible at all times
local meRatioPinned = false

-- Toggle [INTEL] Tooltip to be visible at all times
local intelPinned = false

-- Toggle [ -Xe +Xm X% ] Energy->Metal conversion stat tooltip
local convStatPinned = false

-- LOCAL STATE (Option A — single correct alias)
local spGetLocalAllyTeamID    = Spring.GetLocalAllyTeamID
local spGetMyTeamID           = Spring.GetMyTeamID
local spGetViewGeometry       = Spring.GetViewGeometry
local spGetTeamResources      = Spring.GetTeamResources
local spGetLocalTeamID        = Spring.GetLocalTeamID
local spGetPlayerList         = Spring.GetPlayerList
local spGetPlayerInfo         = Spring.GetPlayerInfo
local spGetTimer              = Spring.GetTimer
local spDiffTimers            = Spring.DiffTimers
local spIsGUIHidden           = Spring.IsGUIHidden
local spGetModKeyState        = Spring.GetModKeyState
local spGetTeamInfo           = Spring.GetTeamInfo
local spGetSpectatingState    = Spring.GetSpectatingState
local spGetTeamUnits          = Spring.GetTeamUnits
local spGetUnitDefID          = Spring.GetUnitDefID
local spGetTeamAllyTeamID     = Spring.GetTeamAllyTeamID

energyConversionPercent 	  = energyConversionPercent or 0

-- Tooltip on foreground of widget
local pendingTooltip = nil
local pendingTooltipX = 0
local pendingTooltipY = 0


-- REQUIRED FOR COMMANDER COUNT
local spGetTeamList           = Spring.GetTeamList
local spGetTeamUnitDefCount   = Spring.GetTeamUnitDefCount
local spGetTeamRulesParam     = Spring.GetTeamRulesParam
local spGetMyAllyTeamID       = Spring.GetMyAllyTeamID

-- To refresh Smoothing stats in Spectator mode for Metal and Energy Tooltips
local lastTeamID = Spring.GetMyTeamID()

-- HistorySecond Config
local historyButtons = {}
local historyOptions = {20, 30, 40, 50, 60}

-- Icons Metal and Energy
local metalIconPath  = "LuaUI/Images/BAR_metal.png"
local energyIconPath = "LuaUI/Images/BAR_energy.png"

-- Energy Share Button stuff
energyShareDropdown       = energyShareDropdown or false
energyShareOptions 		  = energyShareOptions or {"Disable", 10, 20, 30, 40, 50, 60, 70, 80, 90}
energyShareOptionRects    = energyShareOptionRects or {}
energySharePercent        = energySharePercent or 0
energyShareButton         = energyShareButton or {x1=0,y1=0,x2=0,y2=0}

-- ECO GRAPH STATUS TABLE
local statusTooltips = {

["METAL DRAIN"] = [[
METAL DRAIN
Metal is draining faster than you earn it, and metal is the worse resource.

Equation:
metalWorse == true
AND
mNet < -1
AND
mCur > 0.01
AND
mPercent < 0.50

How it works:
Metal has lower storage % than energy (or worse net in a tie),
AND metal net is negative,
AND metal storage is below 50% but not empty.

Player should know/do:
• Reduce buildpower (too many constructors)
• Expand to more metal spots
• Reclaim metal from wrecks
• Avoid expensive units until stabilized
]],


["ENERGY DRAIN"] = [[
ENERGY DRAIN
Energy is draining faster than you earn it, and energy is the worse resource.

Equation:
energyWorse == true
AND
eNet < -20
AND
eCur > 0.01
AND
ePercent < 0.50

How it works:
Energy has lower storage % than metal (or worse net in a tie),
AND energy net is strongly negative,
AND energy storage is below 50% but not empty.

Player should know/do:
• Build more solars, winds, or turbines
• Turn off radars, cloaks, shields, and energy-heavy units
• Reduce nano/factory spam
• Build a fusion if you have the metal
]],


["DEPLETED"] = [[
DEPLETED
Your economy has collapsed — one or both resources are empty.

Equation:
mCur <= 0.01 OR eCur <= 0.01

How it works:
A resource has hit zero storage. This is a critical fail state.

Player should know/do:
• Immediately rebuild basic income
• Stop all unnecessary spending
• Reclaim wrecks or expand to new spots
• Stabilize one resource at a time
]],


["OVERFLOWING"] = [[
OVERFLOWING
Both storages are basically full AND you are still gaining resources.

Equation:
(mPercent >= 0.95 OR ePercent >= 0.95)
AND
(mNet > 1 OR eNet > 1)
AND
mPercent >= 0.50
AND
ePercent >= 0.50

How it works:
Your storage is full and you are wasting income.

Player should know/do:
• Add more buildpower
• Spend resources faster
• Expand production
• Build more storage
]],


["SURGING"] = [[
SURGING
Your eco is booming — both metal and energy are strongly positive relative to income.

Equation:
mNet > 0 AND eNet > 0
AND
mRatio > 0.35 AND eRatio > 0.35

How it works:
Both resources are growing rapidly and efficiently.

Player should know/do:
• Increase buildpower
• Start teching
• Push aggression
• Spend before you overflow
]],


["BURNING"] = [[
BURNING
You are burning through storage quickly — negative nets but still some buffer.

Equation:
(mNet < 0 OR eNet < 0)
AND
(mPercent > 0.25 OR ePercent > 0.25)
AND
(mRatio < -0.25 OR eRatio < -0.25)

How it works:
Usage is significantly higher than income, but you still have storage to burn.

Player should know/do:
• Reduce buildpower
• Stop unnecessary factories
• Fix the resource draining hardest
• Prepare for DRAIN if not corrected
]],


["FLOATING"] = [[
FLOATING
You have comfortable storage and stable nets — eco is safe and steady.

Equation:
(mPercent > 0.80 OR ePercent > 0.80)
AND
mPercent >= 0.50
AND
ePercent >= 0.50
AND
(mNet >= 0 OR mRatio > -0.10)
AND
(eNet >= 0 OR eRatio > -0.10)

How it works:
Both storages are healthy, at least one is very high, and nets are stable.

Player should know/do:
• Spend more
• Add buildpower
• Start tech or upgrades
]],


["ECO WEAK"] = [[
ECO WEAK
Your eco is fragile — negative efficiency OR low storage.

Equation:
r < 0.0
OR
mPercent < 0.35
OR
ePercent < 0.35
r = min(mRatio, eRatio)

How it works:
ECO WEAK appears when efficiency is negative OR either storage is below 35%.
This prevents false weak states when nets are positive but storage is low.

Player should know/do:
• Add small income (mex, solar, wind)
• Avoid overbuilding factories or nanos
• Fix whichever resource is low first
• Expand carefully — don’t overextend
• Stabilize storage before scaling production
]],


["ECO STABLE"] = [[
ECO STABLE
Your eco is steady — mild efficiency and healthy storage.

Equation:
r >= 0.0 AND r < 0.35
AND
mPercent >= 0.35
AND
ePercent >= 0.35

How it works:
Efficiency is slightly positive and both storages are above 35%.
This is a safe, reliable eco state.

Player should know/do:
• Build normally
• Add moderate buildpower
• Expand steadily
]],


["ECO STRONG"] = [[
ECO STRONG
Your eco is performing very well — strong efficiency and healthy storage.

Equation:
r >= 0.35
AND
mPercent >= 0.50
AND
ePercent >= 0.50

How it works:
Efficiency is strong and both storages are above 50%.
Your eco can support aggressive scaling or teching.

Player should know/do:
• Add buildpower
• Tech up
• Push aggression
]],
}


WG.EcoGraph_UIVisible = true   -- master visibility flag

WG.EcoGraph_ToggleUI = function()
    WG.EcoGraph_UIVisible = not WG.EcoGraph_UIVisible

    showWidget = WG.EcoGraph_UIVisible
    fullyHidden = not WG.EcoGraph_UIVisible
    detachedWindowVisible = false
end


-- PINPOINTER TRACKING (embedded from PinPointer widget)
local isPinPointerDef = {}
local allyPinCount = {}
local myAllyTeamID = Spring.GetLocalAllyTeamID()

local PINPOINTER_DEFS = {
    armtarg = true,
    cortarg = true,
    legtarg = true,
}

local function GetCurrentViewedAllyTeamID()
    local isSpec, fullView, fullSelect, povTeam = Spring.GetSpectatingState()

    -- Replay or spectator POV
    if isSpec and povTeam and povTeam >= 0 then
        local _, _, _, _, _, allyTeamID = Spring.GetTeamInfo(povTeam)
        return allyTeamID
    end

    -- Live player
    return Spring.GetLocalAllyTeamID()
end

-- Compact number formatter with hysteresis (prevents jitter around 1000)
local lastCompactMode = "raw"   -- remembers last mode: "raw" or "k"

local function FormatCompact(n)
    -- hysteresis thresholds
    if lastCompactMode == "raw" and n >= 1050 then
        lastCompactMode = "k"
    elseif lastCompactMode == "k" and n <= 949 then
        lastCompactMode = "raw"
    end

    -- RAW MODE (1–999 or hysteresis)
    if lastCompactMode == "raw" then
        return string.format("%d", n)
    end

    -- K MODE (1000–999,999)
    if n < 1e6 then
        return string.format("%.2fK", n / 1000)
    end

    -- M MODE (1,000,000+)
    return string.format("%.2fM", n / 1e6)
end

local function FormatIncome(n)
    if n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.2fK", n / 1e3)
    else
        return string.format("%.2f", n)
    end
end

local function FormatShare(n)
    local abs = math.abs(n)
    if abs >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif abs >= 1e3 then
        return string.format("%.2fK", n / 1e3)
    else
        return string.format("%.2f", n)
    end
end

-- 1. Helper functions FIRST
local function FormatNumber(n)
    local abs = math.abs(n)
    if abs >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif abs >= 1e3 then
        return string.format("%.2fK", n / 1e3)
    else
        return string.format("%.2f", n)
    end
end


local function BuildPinPointerDefTable()
    for udid, ud in pairs(UnitDefs) do
        local name = ud.name:lower()
        if PINPOINTER_DEFS[name] then
            isPinPointerDef[udid] = true
        end
    end
end

local function ShortenPlayerName(name)
    if #name <= 10 then
        return name
    end
    return name:sub(1, 10) .. "..."
end

local function GetTotalBuildPower(teamID)
    local total = 0
    local units = Spring.GetTeamUnits(teamID)
    if not units then return 0 end

    for i = 1, #units do
        local udid = Spring.GetUnitDefID(units[i])
        if udid then
            local ud = UnitDefs[udid]
            if ud and ud.buildSpeed and ud.buildSpeed > 0 then
                total = total + ud.buildSpeed
            end
        end
    end

    return total
end

local function UpdateMyAllyTeamID()
    local spec, fullView, fullSelect, spectatedTeam = Spring.GetSpectatingState()

    if spec then
        if spectatedTeam and spectatedTeam >= 0 then
            myAllyTeamID = Spring.GetTeamAllyTeamID(spectatedTeam)
        end
    else
        myAllyTeamID = Spring.GetLocalAllyTeamID()
    end
end

local function InitAllyPinCounts()
    allyPinCount = {}
    local allUnits = Spring.GetAllUnits()

    for i = 1, #allUnits do
        local unitID = allUnits[i]
        local udid = Spring.GetUnitDefID(unitID)

        if udid and isPinPointerDef[udid] then
            local teamID = Spring.GetUnitTeam(unitID)
            local allyTeam = Spring.GetTeamAllyTeamID(teamID)

            allyPinCount[allyTeam] = (allyPinCount[allyTeam] or 0) + 1
        end
    end
end

local function AdjustTeamCount(teamID, udid, delta)
    if not teamID or not udid then return end
    if not isPinPointerDef[udid] then return end

    -- convert team → allyTeam
    local allyTeam = Spring.GetTeamAllyTeamID(teamID)

    local current = allyPinCount[allyTeam] or 0
    current = current + delta
    if current < 0 then current = 0 end

    allyPinCount[allyTeam] = current
end


--------------------------------------------------------------------------------
-- UNIFIED TOGGLE MENU (SELF-CONTAINED MODULE VERSION)
-- This behaves like its own widget but lives inside Eco Graph.
--------------------------------------------------------------------------------
local EcoToggleMenu = {}

do
    ------------------------------------------------------------------------
    -- CONFIG
    ------------------------------------------------------------------------
    local vsx, vsy = Spring.GetViewGeometry()

    local BUTTON_W = 120
    local BUTTON_H = 100

    local bgColor = {0, 0, 0, 0.55}
    local borderColor = {1, 1, 1, 0.35}

    ------------------------------------------------------------------------
    -- FIRST-TIME CENTERING
    ------------------------------------------------------------------------
    local savedX = Spring.GetConfigInt("unified_menu_x", nil, false)
    local savedY = Spring.GetConfigInt("unified_menu_y", nil, false)

    EcoToggleMenu.posX = savedX or math.floor((vsx - BUTTON_W) * 0.5)
    local totalH = BUTTON_H
    EcoToggleMenu.posY = savedY or math.floor((vsy - totalH) * 0.5)

    ------------------------------------------------------------------------
    -- DRAG STATE
    ------------------------------------------------------------------------
    EcoToggleMenu.dragging = false
    EcoToggleMenu.dragMoved = false
    EcoToggleMenu.dragStartX = 0
    EcoToggleMenu.dragStartY = 0
    EcoToggleMenu.dragOffsetX = 0
    EcoToggleMenu.dragOffsetY = 0

    EcoToggleMenu.menuRect = nil

    ------------------------------------------------------------------------
    -- TARGET WIDGET NAMES
    ------------------------------------------------------------------------
    local WIDGET_ECO    = "Eco Graph"

    ------------------------------------------------------------------------
    -- HELPERS
    ------------------------------------------------------------------------
    local glColor = gl.Color
    local glRect  = gl.Rect
    local glText  = gl.Text

    local function InRect(mx, my, r)
        return mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2
    end

    ------------------------------------------------------------------------
    -- VIEW RESIZE
    ------------------------------------------------------------------------
    function EcoToggleMenu.ViewResize(x, y)
        vsx, vsy = x, y
    end

    ------------------------------------------------------------------------
    -- DRAW BUTTON
    ------------------------------------------------------------------------
    local function DrawButton(x1, y1, label, enabled, locked)
        local x2 = x1 + BUTTON_W
        local y2 = y1 + BUTTON_H

        glColor(bgColor)
        glRect(x1, y1, x2, y2)

        glColor(borderColor)
        glRect(x1, y1, x2, y1 + 1)
        glRect(x1, y2 - 1, x2, y2)

        local cx = (x1 + x2) * 0.5
        local cy = (y1 + y2) * 0.5

        if locked then
            glColor(0.5, 0.5, 0.5, 0.85)
            glText(label, cx, cy + 10, 20, "oc")
            glColor(0.4, 0.4, 0.4, 1)
            glText("LOCKED", cx, cy - 20, 20, "oc")
            return
        end

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

    ------------------------------------------------------------------------
    -- DRAW
    ------------------------------------------------------------------------
    function EcoToggleMenu.Draw()
        local x1 = EcoToggleMenu.posX
        local y1 = EcoToggleMenu.posY

        local totalH = BUTTON_H
        local x2 = x1 + BUTTON_W
        local y2 = y1 + totalH

        EcoToggleMenu.menuRect = widget._setRect(EcoToggleMenu.menuRect, x1, y1, x2, y2)

        -- ECO GRAPH BUTTON
        DrawButton(
            x1,
            y1,
            "Eco Graph",
            WG.EcoGraph_UIVisible

        )
    end

    ------------------------------------------------------------------------
    -- MOUSE HANDLING
    ------------------------------------------------------------------------
    local function IsAbove(mx, my)
        local r = EcoToggleMenu.menuRect
        return r and InRect(mx, my, r)
    end

    function EcoToggleMenu.MousePress(mx, my, button)
        if button ~= 1 then return false end
        if not IsAbove(mx, my) then return false end

        EcoToggleMenu.dragging = true
        EcoToggleMenu.dragMoved = false
        EcoToggleMenu.dragStartX = mx
        EcoToggleMenu.dragStartY = my

        EcoToggleMenu.dragOffsetX = mx - EcoToggleMenu.posX
        EcoToggleMenu.dragOffsetY = my - EcoToggleMenu.posY
        return true
    end

    function EcoToggleMenu.MouseMove(mx, my)
        if EcoToggleMenu.dragging then
            if math.abs(mx - EcoToggleMenu.dragStartX) > 3 or math.abs(my - EcoToggleMenu.dragStartY) > 3 then
                EcoToggleMenu.dragMoved = true
            end

            EcoToggleMenu.posX = mx - EcoToggleMenu.dragOffsetX
            EcoToggleMenu.posY = my - EcoToggleMenu.dragOffsetY
            return true
        end
    end

    function EcoToggleMenu.MouseRelease(mx, my, button)
        if EcoToggleMenu.dragging then
            EcoToggleMenu.dragging = false

            Spring.SetConfigInt("unified_menu_x", EcoToggleMenu.posX)
            Spring.SetConfigInt("unified_menu_y", EcoToggleMenu.posY)

            if not EcoToggleMenu.dragMoved and IsAbove(mx, my) then
                WG.EcoGraph_ToggleUI()
            end

            return true
        end

        return false
    end

    -- Re-centers this panel on the CURRENT screen, using the same formula
    -- as first-time placement above. Exists for /ecographcenter -- a
    -- resolution lower than whatever screen this got dragged to last
    -- (e.g. downloading someone else's saved config, or moving from an
    -- ultrawide to a smaller monitor) can otherwise leave this panel
    -- sitting off-screen with no way to find it, since dragging requires
    -- being able to see it to click it in the first place.
    function EcoToggleMenu.Center()
        -- Fetched fresh rather than using this block's own `vsx, vsy` --
        -- nothing in the file actually calls EcoToggleMenu.ViewResize (it's
        -- defined but never wired up), so those would be stale from
        -- whatever the resolution was at widget load, not the CURRENT one.
        local curVsx, curVsy = Spring.GetViewGeometry()
        local totalH = BUTTON_H
        EcoToggleMenu.posX = math.floor((curVsx - BUTTON_W) * 0.5)
        EcoToggleMenu.posY = math.floor((curVsy - totalH) * 0.5)

        Spring.SetConfigInt("unified_menu_x", EcoToggleMenu.posX)
        Spring.SetConfigInt("unified_menu_y", EcoToggleMenu.posY)
    end
end

--------------------------------------------------------------------------------
-- END OF UNIFIED TOGGLE MENU MODULE
--------------------------------------------------------------------------------



-- initialize
BuildPinPointerDefTable()
InitAllyPinCounts()
UpdateMyAllyTeamID()


function widget:UnitFinished(unitID, unitDefID, teamID)
    AdjustTeamCount(teamID, unitDefID, 1)
end

function widget:UnitDestroyed(unitID, unitDefID, teamID)
    AdjustTeamCount(teamID, unitDefID, -1)
end

function widget:PlayerChanged(playerID)
    UpdateMyAllyTeamID()
end

function widget:GameFrame(f)
    if f % 10 == 0 then
        UpdateMyAllyTeamID()
    end
end

-- COMMANDER UNIT DEF IDS (STATIC LIST)
commanderUnitDefIDs = {}

local function add(name)
    if UnitDefNames[name] then
        commanderUnitDefIDs[#commanderUnitDefIDs+1] = UnitDefNames[name].id
    end
end

add("armcom")
add("corcom")
add("legcom")          -- only added if Legion is enabled
add("armcom_scav")
add("corcom_scav")
add("legcom_scav")     -- only added if Legion is enabled

-- CORE STATE
local showWidget  = true
local compactMode = false
local dragLocked  = false

-- Hide / Unhide system
local fullyHidden = false   -- true = widget invisible, only unhide button shows

-- STATUS SMOOTHING STATE (5-second stability window)
local currentStatus        = "ECO STABLE"
local pendingStatus        = nil
local pendingStartTime     = 0
local lastStatusChangeTime = 0
local STATUS_HOLD_TIME     = 2  -- seconds

-- GRAPH SMOOTHING STATE (EMA)
local smoothMetal  = nil
local smoothEnergy = nil

-- 0.10 = very smooth, 0.20 = balanced, 0.30 = responsive
local smoothingAlpha = 0.20

-- Extended smoothing for income + usage
local smoothMetalIncome  = nil
local smoothMetalUsage   = nil
local smoothEnergyIncome = nil
local smoothEnergyUsage  = nil

-- Smoothen Energy Storage BAR so it doesn't look erratic.
local smoothEnergyCur = nil
local smoothMetalCur  = nil

-- CONFIG
local cfg = {
    width  = 0.70,   -- original 0.46 -- Shrink height
    height = 0.10, -- original 0.16

    anchorX = 0.52,
    anchorY = 0.02,
 -- How long in the line graphs are kept, the longer the more resource it takes.
    historySeconds = 20,  -- this is in seconds
	historyOptions = {20, 30, 40, 50, 60},

    -- bgColor     = {0, 0, 0, 0.60},
	bgColor     = {0, 0, 0, 0.95},   -- Background Opacity for the whole widget ("Default" mode)
	bgColorTransparent = {0, 0, 0, 0},   -- "Transparent" mode: no background panel at all
    borderColor = {1, 1, 1, 0.5},

    metalIncomeColor = {0.2, 1.0, 1.0, 1.0},
    metalUsageColor  = {1.0, 0.5, 0.5, 1.0},

    energyIncomeColor = {1.0, 1.0, 0.2, 1.0},
    energyUsageColor  = {1.0, 0.3, 0.3, 1.0},

    netPosColor = {0.3, 1.0, 0.3, 1.0},
    netNegColor = {1.0, 0.3, 0.3, 1.0},

    gridColor   = {1, 1, 1, 0.09},
    titleColor  = {1, 1, 1, 0.95},

    innerMargin      = 0.08,
    yPaddingFraction = 0.10,
}

-- STATUS COLORS (Full Color-Theory Pass)
local statusColors = {
    -- CRITICAL / NEGATIVE STATES
    ["METAL DRAIN"]   = {1.0, 0.45, 0.0, 1.0},   -- warning orange
    ["ENERGY DRAIN"]  = {1.0, 0.45, 0.0, 1.0},   -- warning orange
  
    ["DEPLETED"]      = {1.0, 0.0, 0.0, 1.0},    -- pure red (critical)

    ["BURNING"]       = {1.0, 0.30, 0.0, 1.0},   -- flame orange-red

    -- POSITIVE / STORAGE STATES
    ["OVERFLOWING"]   = {0.70, 0.30, 1.0, 1.0},  -- purple (excess)
    ["SURGING"]       = {0.25, 0.55, 1.0, 1.0},  -- blue (growth)
    ["FLOATING"]      = {0.90, 0.90, 0.90, 1.0}, -- light gray (stable)

    -- ECO STRENGTH STATES
    ["ECO WEAK"]      = {1.0, 0.75, 0.15, 1.0},  -- amber (caution)
    ["ECO STABLE"]    = {0.45, 1.0, 0.25, 1.0},  -- soft lime green (between weak & strong)
    ["ECO STRONG"]    = {0.10, 1.0, 0.10, 1.0},  -- bright green (excellent)
}


local lastViewedTeam  = nil
local fadeAlpha       = 1
local fadeStartTime   = 0
local FADE_DURATION   = 0.6

local glColor      = gl.Color
local glRect       = gl.Rect
local glLineWidth  = gl.LineWidth
local glBeginEnd   = gl.BeginEnd
local glVertex     = gl.Vertex
local glCallList   = gl.CallList
local glCreateList = gl.CreateList
local glDeleteList = gl.DeleteList
local glText       = gl.Text

-- OPENGL BINDINGS (PATCH INSERTED HERE)
local glGetTextWidth = gl.GetTextWidth   -- REQUIRED FIX

--------------------------------------------------------------------------------
-- WIND METER (Dual‑Tone Highlight Bar)
--------------------------------------------------------------------------------
local function DrawWindMeter(x1, y1, x2, y2)
    -- Wind values from your existing sampling
    local avgWind = 0
    if windSamples > 0 then
        avgWind = windSum / windSamples
    end

    -- BAR COLORING (same style as storage bars)
    local baseColor      = {0.25, 0.25, 0.25, 0.85}
    local fillColor      = {0.70, 0.90, 1.00, 0.90}
    local highlightColor = {1.00, 1.00, 1.00, 0.25}

    -- Wind range (BA defaults)
    local minWind = Game.windMin or 0
    local maxWind = Game.windMax or 30
    local pct = (avgWind - minWind) / (maxWind - minWind)
    pct = math.max(0, math.min(1, pct))

    --------------------------------------------------------------------
    -- GEOMETRY (shortened + centered)
    --------------------------------------------------------------------
    local fullW = x2 - x1
    local w = fullW * 0.45      -- ← adjust this % to shorten/lengthen
    local h = y2 - y1

    local offset = (fullW - w) * 0.5
    local barX1 = x1 + offset
    local barX2 = barX1 + w

    local fillW = w * pct

    --------------------------------------------------------------------
    -- DRAWING (now using barX1 / barX2)
    --------------------------------------------------------------------

    -- BASE BAR
    glColor(baseColor)
    glRect(barX1, y1, barX2, y2)

    -- FILL BAR
    glColor(fillColor)
    glRect(barX1, y1, barX1 + fillW, y2)

    -- HIGHLIGHT OVERLAY
    glColor(highlightColor)
    glRect(barX1, y1 + h * 0.50, barX1 + fillW, y2)

    -- TEXT (centered over the shortened bar)
    local label = string.format("Wind: %.1f", avgWind)
    glColor(1,1,1,1)
    glText(label, (barX1 + barX2) * 0.5, y1 + h * 0.15, fontSize, "oc")
end

-- WIND AVERAGE STATE (PATCH INSERTED HERE)
local windSum     = 0
local windSamples = 0

local function UpdateFade()
    if fadeAlpha < 1 then
        local t = spDiffTimers(spGetTimer(), fadeStartTime)
        fadeAlpha = math.min(1, t / FADE_DURATION)
    end
end

-- FADE-AWARE COLOR OVERRIDE
local _glColor = glColor
glColor = function(r, g, b, a)
    if type(r) == "table" then
        local t  = r
        local rr = t[1] or 1
        local gg = t[2] or 1
        local bb = t[3] or 1
        local aa = (t[4] or 1) * fadeAlpha
        _glColor(rr, gg, bb, aa)
        return
    end

    _glColor(
        r or 1,
        g or 1,
        b or 1,
        (a or 1) * fadeAlpha
    )
end

local GL_LINES      = GL.LINES
local GL_LINE_STRIP = GL.LINE_STRIP

--------------------------------------------------------------------------------
-- SHARED CLOSURE-FREE VERTEX FUNCTIONS (named, not inline) -----------------
-- These replace per-frame `function() ... end` literals passed to
-- gl.BeginEnd(). Each `function() end` literal allocates a new Lua closure
-- every time it's evaluated; gl.BeginEnd(mode, fn, ...) forwards any extra
-- arguments straight into fn via lua_pcall, so a single persistent function
-- reused across call sites produces zero per-frame allocation instead of
-- one closure per call. Hung off the global `widget` table rather than a
-- new `local` because this file is already at Lua 5.1's 200-local-per-
-- chunk ceiling (see gui-eco-graph-notes.md) and a global field resolves
-- at call time, so it needs no particular lexical position in the file.
--------------------------------------------------------------------------------

function widget._rectBorderVerts(x1, y1, x2, y2)
    glVertex(x1,y1); glVertex(x2,y1)
    glVertex(x2,y1); glVertex(x2,y2)
    glVertex(x2,y2); glVertex(x1,y2)
    glVertex(x1,y2); glVertex(x1,y1)
end

function widget._zeroLineVerts(x1, y, x2)
    glVertex(x1, y)
    glVertex(x2, y)
end

function widget._curveVerts(data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, useIncome)
    for i = 1, #data, 2 do
        local s = data[i]
        local tf = (s.t - minT) / rangeT
        local v = useIncome and s.income or s.usage
        local vf = (v - minV) / rangeV
        glVertex(gx1 + gw * tf, gy1 + gh * vf)
    end
end

function widget._windBackplateFillVerts(bx1, bevel, by1, bx2, midY)
    glVertex(bx1 + bevel, by1)
    glVertex(bx2 - bevel, by1)
    glVertex(bx2, midY)
    glVertex(bx1, midY)
end

function widget._windBackplateBorderVerts(bx1, midY, bevel, by1, bx2)
    glVertex(bx1, midY)
    glVertex(bx1 + bevel, by1)
    glVertex(bx2 - bevel, by1)
    glVertex(bx2, midY)
end

--------------------------------------------------------------------------------
-- "TOP BAR"-STYLE PANEL SKIN -- chamfered-corner panel with a vertical
-- gradient fill, approximating the look of BAR's own top resource bar
-- (dark warm-brown panel, angle-cut outer corners, muted bronze border).
-- Toggled by /ecographbar -- ONLY the panel's background/border is
-- swapped; everything drawn on top (title, stats, graphs, tooltips) is
-- completely unchanged. `c` is the chamfer size in pixels.
--------------------------------------------------------------------------------
function widget._barSkinPanelVerts(x1, y1, x2, y2, c, tr, tg, tb, ta, br, bg, bb, ba)
    local h = y2 - y1
    local f = (h > 0) and (c / h) or 0

    -- Color at y1+c and at y2-c (symmetric chamfer, so these differ
    -- unless f == 0.5) and at the vertical center (fan origin).
    local m1r, m1g, m1b, m1a = tr + (br-tr)*f,     tg + (bg-tg)*f,     tb + (bb-tb)*f,     ta + (ba-ta)*f
    local m2r, m2g, m2b, m2a = tr + (br-tr)*(1-f), tg + (bg-tg)*(1-f), tb + (bb-tb)*(1-f), ta + (ba-ta)*(1-f)
    local cr, cg, cb, ca     = (tr+br)*0.5, (tg+bg)*0.5, (tb+bb)*0.5, (ta+ba)*0.5

    glColor(cr, cg, cb, ca);     glVertex((x1+x2)*0.5, (y1+y2)*0.5)  -- fan origin

    glColor(tr, tg, tb, ta);     glVertex(x1+c, y1)
    glColor(tr, tg, tb, ta);     glVertex(x2-c, y1)
    glColor(m1r, m1g, m1b, m1a); glVertex(x2,   y1+c)
    glColor(m2r, m2g, m2b, m2a); glVertex(x2,   y2-c)
    glColor(br, bg, bb, ba);     glVertex(x2-c, y2)
    glColor(br, bg, bb, ba);     glVertex(x1+c, y2)
    glColor(m2r, m2g, m2b, m2a); glVertex(x1,   y2-c)
    glColor(m1r, m1g, m1b, m1a); glVertex(x1,   y1+c)
    glColor(tr, tg, tb, ta);     glVertex(x1+c, y1)    -- close the fan
end

function widget._barSkinBorderVerts(x1, y1, x2, y2, c)
    glVertex(x1+c, y1);   glVertex(x2-c, y1)
    glVertex(x2-c, y1);   glVertex(x2,   y1+c)
    glVertex(x2,   y1+c); glVertex(x2,   y2-c)
    glVertex(x2,   y2-c); glVertex(x2-c, y2)
    glVertex(x2-c, y2);   glVertex(x1+c, y2)
    glVertex(x1+c, y2);   glVertex(x1,   y2-c)
    glVertex(x1,   y2-c); glVertex(x1,   y1+c)
    glVertex(x1,   y1+c); glVertex(x1+c, y1)
end

--------------------------------------------------------------------------------
-- RECT-MUTATION HELPER -- avoids reallocating a fresh {x1,y1,x2,y2} hitbox
-- table every single frame for UI elements whose POSITION is recomputed
-- every frame but whose IDENTITY (the table object other code holds a
-- reference to, e.g. for mouse hit-testing) doesn't need to change. Every
-- `someRect = { x1 = ..., y1 = ..., x2 = ..., y2 = ... }` in this file is a
-- real Lua table allocation each time it runs, even when the numbers end up
-- identical to last frame -- unlike short strings, table constructors are
-- never interned/deduplicated by Lua. Reusing the existing table and just
-- overwriting its fields removes that per-frame allocation entirely, with
-- no behavior change: everything that reads these rects only reads their
-- x1/y1/x2/y2 fields.
--------------------------------------------------------------------------------
function widget._setRect(t, x1, y1, x2, y2)
    if not t then
        t = {}
    end
    t.x1, t.y1, t.x2, t.y2 = x1, y1, x2, y2
    return t
end

--------------------------------------------------------------------------------
-- M:E TOOLTIP "METAL CONTEXT" HINT -- HOLD-BASED ANTI-FLICKER
--------------------------------------------------------------------------------
-- mNet (smoothed income - smoothed usage) can dip slightly negative for a
-- moment on an otherwise healthy economy -- e.g. a build queue briefly
-- outspending income right when a factory/nano starts a new order -- which
-- used to flip this hint straight to "Stalling metal" and back again a
-- frame or two later. Same fix as GetEcoStatus's own STATUS_HOLD_TIME
-- (2-second hold before the main "Status: X" label changes): require the
-- new tier to persist for METAL_HINT_HOLD_TIME before actually switching
-- the displayed hint, instead of reacting to every instantaneous value.
-- State is hung off `widget` for the same 200-local-ceiling reason as
-- everything else in this file -- including the hold-time constant
-- itself: a `local METAL_HINT_HOLD_TIME = 2` here would be one more
-- chunk-level local, and this file's main chunk is already AT the
-- 200-local ceiling (confirmed: adding one more fails to compile).
function widget._getMetalHint(mNet, mInc)
    local METAL_HINT_HOLD_TIME = 2  -- seconds, matches STATUS_HOLD_TIME's hold
    local raw
    if mNet < 0 then
        raw = "stalling"
    elseif mInc < 5 then
        raw = "verylow"
    elseif mInc < 12 then
        raw = "low"
    elseif mInc < 25 then
        raw = "normal"
    else
        raw = "high"
    end

    local current = widget._metalHintTier or raw

    if raw == current then
        widget._metalHintPending = nil
    elseif widget._metalHintPending ~= raw then
        widget._metalHintPending      = raw
        widget._metalHintPendingStart = spGetTimer()
    elseif spDiffTimers(spGetTimer(), widget._metalHintPendingStart) >= METAL_HINT_HOLD_TIME then
        current = raw
        widget._metalHintPending = nil
    end

    widget._metalHintTier = current

    if current == "stalling" then
        return "Stalling metal", {1, 0.2, 0.2, 1}, "⚠️ "
    elseif current == "verylow" then
        return "Metal income very low", {1, 0.2, 0.2, 1}, "⚠️ "
    elseif current == "low" then
        return "Metal income low.", {1, 0.7, 0.1, 1}, "⚠️ "
    elseif current == "normal" then
        return "Metal income normal.", {0, 0, 0, 1}, "✔️ "
    else
        return "Metal income high — strong eco potential.", {0.2, 1, 0.2, 1}, "⬆️ "
    end
end

local vsx, vsy = 0, 0
local box      = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 }

local history = {
    metal  = {},
    energy = {},
}

local historyMaxSamples = 0
local lastSampleTime    = 0

local graphList = nil
local paused    = false

local dragging      = false
local resizing      = false
local dragOffsetX   = 0
local dragOffsetY   = 0
local resizeStartX  = 0
local resizeStartY  = 0

local startTimer     = spGetTimer()
local fontSize       = 14 * FONT_SCALE
local titleSize      = 12 * FONT_SCALE
local resizeHandleSize = 14
local emptyColor     = {0.4, 0.4, 0.4, 0.9}


-- ENERGY SHARE STATE
local energyShareDropdown = false
local energySharePercent  = 0   -- 0–90
local energyShareButton   = {x1=0, y1=0, x2=0, y2=0}
local energyShareTicks    = {10,20,30,40,50,60,70,80,90}


-- METAL SHARE STATE (BUTTON + DROPDOWN)
local metalSharePercent       = 0.0      -- 0.0 = off, 0.3 = 30%
local metalShareButtonRect    = { x1 = 0, y1 = 0, x2 = 0, y2 = 0 }
local metalShareDropdownOpen  = false
local metalShareOptions = {
    "Disable",
    0.10,
    0.20,
    0.30,
    0.40,
    0.50,
    0.60,
    0.70,
    0.80,
    0.90,
}

local metalShareOptionRects   = {}      -- index → {x1,y1,x2,y2}

local spGetMouseState   = Spring.GetMouseState
local spShareResources  = Spring.ShareResources

local function PointInRect(mx, my, x1, y1, x2, y2)
    if not (mx and my and x1 and y1 and x2 and y2) then
        return false
    end
    return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end


local function GetMetalShareLabel()
    -- Disabled → always show 0 metal
    if not metalShareEnabled or metalSharePercent == 0 then
        return "[Share: 0%, 0]"
    end

    -- metalSharePercent is SHARE fraction (0.10 → 10%)
    local shareFraction = metalSharePercent
    local keepFraction  = 1 - shareFraction

    local cur, stor = spGetTeamResources(Spring.GetMyTeamID(), "metal")
    cur  = cur or 0
    stor = stor or 0

    -- Threshold based on TOTAL STORAGE
local _, realStorage = spGetTeamResources(Spring.GetMyTeamID(), "metal")
local keepAmount = realStorage * keepFraction


    -- Only show EXCESS above threshold
    local shareAmount = 0
    if cur > keepAmount then
        shareAmount = cur - keepAmount
    end

    local pct = math.floor(shareFraction * 100 + 0.5)

    return string.format(
        "[Share: %d%%, -%s]",
        pct,
        FormatNumber(shareAmount)
    )
end

local function IsMetalActuallySharing()
    if not metalShareEnabled or metalSharePercent == 0 then
        return false
    end

    local shareFraction = metalSharePercent
    local keepFraction  = 1 - shareFraction

    local cur, stor = spGetTeamResources(Spring.GetMyTeamID(), "metal")
    cur  = cur or 0
    stor = stor or 0

local _, realStorage = spGetTeamResources(Spring.GetMyTeamID(), "metal")
local keepAmount = realStorage * keepFraction


    return cur > keepAmount   -- true if sharing is happening
end

local function GetEnergyShareLabel()
    -- Disabled → always show 0 energy, no minus
    if not energyShareEnabled or energySharePercent == 0 then
        return "[Share: 0%, 0]"
    end

    local share = energySharePercent
    local shareFraction = share * 0.01

    local cur = select(1, spGetTeamResources(Spring.GetMyTeamID(), "energy")) or 0
    local shareAmount = math.floor(cur * shareFraction)

    -- Active → always show minus, formatted
    return string.format(
        "[Share: %d%%, -%s]",
        share,
        FormatNumber(shareAmount)
    )
end

-- TEAM VIEW HELPERS (ACTUAL VS SAFE)
-- Actual engine-reported viewed team (used for detecting switches)
local function GetActualViewedTeamID()
    return spGetLocalTeamID() or 0
end

-- Safe viewed team (restrictions in live games, full freedom in replay/spec)
local function GetSafeViewedTeamID()
    local myTeam = spGetLocalTeamID()
    local myAlly = spGetLocalAllyTeamID()
    local isSpec, fullView = spGetSpectatingState()

    -- Replay or spectator with full view → allow all teams
    if isSpec and fullView then
        return lastViewedTeam or myTeam
    end

    -- Live game: allow only self + allies
    if lastViewedTeam then
        local _, _, _, _, _, allyTeam = spGetTeamInfo(lastViewedTeam)
        if allyTeam == myAlly then
            return lastViewedTeam
        end
    end

    -- Fallback: always yourself
    return myTeam
end

-- FACTION DETECTION (COMMANDER-BASED, WORKS FOR AI & EVOLVED COMS)
local factionByTeam = {}

local function DetectFaction(teamID)
    if factionByTeam[teamID] then
        return factionByTeam[teamID]
    end

    local units = spGetTeamUnits(teamID)
    if units then
        for _, unitID in ipairs(units) do
            local udid = spGetUnitDefID(unitID)
            local ud   = udid and UnitDefs[udid]
            local name = ud and ud.name or ""
            name = name:lower()

            -- Evolving commanders preserve their base name prefix (armcom/corcom/legcom etc.)
            if name:find("armcom") then
                factionByTeam[teamID] = "armada"
                return "armada"
            elseif name:find("corcom") then
                factionByTeam[teamID] = "cortex"
                return "cortex"
            elseif name:find("legcom") then
                factionByTeam[teamID] = "legion"
                return "legion"
            end
        end
    end

    -- Fallback: assume Armada if we can't detect (edge cases only)
    factionByTeam[teamID] = "armada"
    return "armada"
end

    -- UTIL
    local nukeUnitDefIDs = {}
local antiNukeUnitDefIDs = {}
local junoUnitDefIDs = {}
local spGetUnitWeaponState = Spring.GetUnitWeaponState   -- FIX: was missing, caused CountMyNukeUnits to error out
local spGetUnitStockpile   = Spring.GetUnitStockpile     -- correct API for reading ready warhead counts

-- FIX: classifying by "any stockpile weapon, split by interceptor flag"
-- was too broad - it also matched OTHER stockpile-weapon structures
-- like Super Weapon (Vulcan/Buzzkill) and EMP Missile Launcher/Catalyst,
-- silently inflating Nuke/Anti-Nuke counts even with zero silos built.
-- Switched to exact unit names instead (same real defnames already
-- confirmed via gui_team_base_tracker.lua's own category mapping).
local nukeSiloNames = { armsilo = true, corsilo = true, legsilo = true }
local antiNukeNames = { armamd = true, corfmd = true, legabm = true }

local function BuildNukeLookup()
    for udid, ud in pairs(UnitDefs) do
        local name = ud.name and ud.name:lower() or ""
        if nukeSiloNames[name] then
            nukeUnitDefIDs[udid] = true
        elseif antiNukeNames[name] then
            antiNukeUnitDefIDs[udid] = true
        elseif name:find("juno") then
            junoUnitDefIDs[udid] = true
        end
    end
end

local function CountMyNukeUnits(teamID)
    -- FIX: accept the currently VIEWED team (spectator/replay-aware) so
    -- this follows whichever player you're watching, instead of always
    -- reading your own team. Falls back to your own team if none given.
    local myTeam = teamID or spGetMyTeamID()
    local units = spGetTeamUnits(myTeam)
    local nukeCount = 0
    local antiNukeCount = 0
    local junoCount = 0
    if units then
        for _, unitID in ipairs(units) do
            local udid = spGetUnitDefID(unitID)
            if not udid then
                break
            end

            -- FIX: "numStockpiled" is not a valid Spring.GetUnitWeaponState
            -- key (that call just silently returned nil, so nothing was
            -- ever counted). The engine has a dedicated call for this:
            -- Spring.GetUnitStockpile(unitID) -> numStockpiled(ready), numQueued(still being built)
            --
            -- REVERTED "sum ready+queued": that matched the command panel's
            -- "Stockpile X/20" style TARGET number, not "ready to fire".
            -- What we actually want is READY ONLY - the same "X" shown on
            -- the left side of "Stockpile X/20" - since that's what's
            -- actually available to launch right now. Queued/building
            -- warheads aren't fireable yet, so they're excluded.
            if nukeUnitDefIDs[udid] or antiNukeUnitDefIDs[udid] or junoUnitDefIDs[udid] then
                local ready = spGetUnitStockpile(unitID)
                local stockpiled = (type(ready) == "number") and ready or 0

                if nukeUnitDefIDs[udid] then
                    nukeCount = nukeCount + stockpiled
                elseif antiNukeUnitDefIDs[udid] then
                    antiNukeCount = antiNukeCount + stockpiled
                elseif junoUnitDefIDs[udid] then
                    junoCount = junoCount + stockpiled
                end
            end
        end
    end
    return nukeCount, antiNukeCount, junoCount
end

local function GetPlayerNameFromTeam(teamID)
        local players = spGetPlayerList(teamID, true)
        for _, pid in ipairs(players) do
            local name, active, spec, team = spGetPlayerInfo(pid)
            if team == teamID then return name end
        end
        return "Unknown"
    end

BuildNukeLookup()

local function UpdateViewGeometry()
    vsx, vsy = spGetViewGeometry()

    local w = vsx * cfg.width
    local h = vsy * cfg.height

    box.x1 = vsx * cfg.anchorX - w * 0.5
    box.y1 = vsy * cfg.anchorY
    box.x2 = box.x1 + w
    box.y2 = box.y1 + h

    historyMaxSamples = math.max(30, math.floor(cfg.historySeconds * 30))

    if graphList then glDeleteList(graphList) graphList = nil end
end

local function PointInBox(mx, my)
    return mx >= box.x1 and mx <= box.x2 and my >= box.y1 and my <= box.y2
end

local function PointInResizeHandle(mx, my)
    return mx >= (box.x2 - resizeHandleSize) and mx <= box.x2
       and my >= box.y1 and my <= (box.y1 + resizeHandleSize)
end

local function ResetHistory()
    history.metal  = {}
    history.energy = {}
    lastSampleTime = 0
end

local function FormatTime(seconds)
    if not seconds or seconds <= 0 or seconds == math.huge then return "--" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    if m > 0 then return string.format("%dm%02ds", m, s) end
    return string.format("%ds", s)
end

-- Start of Eco Status Logic
-- SMOOTHED ECO STATUS (2-second stability window)
local function GetEcoStatus(mNet, eNet, mIncome, eIncome, mCur, eCur, mStorage, eStorage)

    ----------------------------------------------------------------
    -- 1. RAW STATUS DETECTION (instantaneous)
    ----------------------------------------------------------------
    local rawStatus

    ----------------------------------------------------------------
    -- Determine which resource is worse (lower percent storage)
    ----------------------------------------------------------------
    local mPercent = (mStorage > 0) and (mCur / mStorage) or 0
    local ePercent = (eStorage > 0) and (eCur / eStorage) or 0

    local energyWorse = ePercent < mPercent
    local metalWorse  = mPercent < ePercent

    -- Improvement #1: tie-breaker when storage % is equal
    if mPercent == ePercent then
        metalWorse  = mNet < eNet
        energyWorse = eNet < mNet
    end

    ----------------------------------------------------------------
    -- HARD FAILURES / DRAIN STATES (highest priority)
    ----------------------------------------------------------------

    -- METAL DRAIN: only if metal is worse
    if metalWorse
        and mNet < -1
        and mCur > 0.01
        and mCur < (0.50 * mStorage)
    then
        rawStatus = "METAL DRAIN"

    -- ENERGY DRAIN: only if energy is worse
    elseif energyWorse
        and eNet < -20
        and eCur > 0.01
        and eCur < (0.50 * eStorage)
    then
        rawStatus = "ENERGY DRAIN"


    ----------------------------------------------------------------
    -- STORAGE-BASED STATES
    ----------------------------------------------------------------

    -- DEPLETED: one of the resources is actually empty
    elseif mCur <= 0.01 or eCur <= 0.01 then
        rawStatus = "DEPLETED"

    -- OVERFLOWING:
    elseif (mCur >= mStorage * 0.95 or eCur >= eStorage * 0.95)
        and (mNet > 1 or eNet > 1)
        and (mPercent >= 0.50)
        and (ePercent >= 0.50)
    then
        rawStatus = "OVERFLOWING"


    ----------------------------------------------------------------
    -- ADVANCED STATES (require ratio calculations)
    ----------------------------------------------------------------
    else
        -- Precompute ratios
        local mRatio = (mIncome > 0) and (mNet / mIncome) or 0
        local eRatio = (eIncome > 0) and (eNet / eIncome) or 0
        local r      = math.min(mRatio, eRatio)

        ----------------------------------------------------------------
        -- SURGING
        ----------------------------------------------------------------
        if mNet > 0 and eNet > 0
            and mRatio > 0.35 and eRatio > 0.35
        then
            rawStatus = "SURGING"

        ----------------------------------------------------------------
        -- BURNING
        ----------------------------------------------------------------
        elseif (mNet < 0 or eNet < 0)
            and (mPercent > 0.25 or ePercent > 0.25)
            and (mRatio < -0.25 or eRatio < -0.25)
        then
            rawStatus = "BURNING"

        ----------------------------------------------------------------
        -- FLOATING
        ----------------------------------------------------------------
        elseif (mPercent > 0.80 or ePercent > 0.80)
            and mPercent >= 0.50
            and ePercent >= 0.50
            and (mNet >= 0 or mRatio > -0.10)
            and (eNet >= 0 or eRatio > -0.10)
        then
            rawStatus = "FLOATING"

        ----------------------------------------------------------------
        -- FALLBACK STATES (NO GAPS)
        ----------------------------------------------------------------

        -- ECO WEAK
        elseif r < 0.0
            or mPercent < 0.35
            or ePercent < 0.35
        then
            rawStatus = "ECO WEAK"

        -- ECO STABLE
        elseif r < 0.35
            and mPercent >= 0.35
            and ePercent >= 0.35
        then
            rawStatus = "ECO STABLE"

        -- ECO STRONG
        else
            rawStatus = "ECO STRONG"
        end
    end


    ----------------------------------------------------------------
    -- 2. STATUS SMOOTHING LOGIC (5-second hold)
    ----------------------------------------------------------------
    local now = spGetTimer()

    if rawStatus == currentStatus then
        pendingStatus = nil
        return currentStatus
    end

    if pendingStatus ~= rawStatus then
        pendingStatus    = rawStatus
        pendingStartTime = now
        return currentStatus
    end

    local dt = spDiffTimers(now, pendingStartTime)
    if dt >= STATUS_HOLD_TIME then
        currentStatus        = pendingStatus
        pendingStatus        = nil
        lastStatusChangeTime = now
        return currentStatus
    end

    return currentStatus
end
-- End of Eco Status Logic


-- REPLAY-AWARE VIEWED TEAM DETECTOR (SAFE FOR LIVE GAMES)
-- NOTE: no longer called anywhere in this file (see Spring.GetMyTeamID()
-- usage in SampleEco/the INTEL tooltips instead) - kept fixed rather than
-- deleted in case anything is re-added to use it later.
local function GetViewedTeamID()
    -- Get local player info
    local myPlayerID = Spring.GetMyPlayerID()
    local name, active, spectator, teamID = Spring.GetPlayerInfo(myPlayerID, false)


    -- CASE A: LIVE GAME (not spectator)
        if not spectator then
        -- Must NOT reveal enemy eco
        return teamID
    end


    -- CASE B: REPLAY/SPECTATE POV TEAM
    -- FIX: this used to re-call Spring.GetPlayerInfo with the same args
    -- as above, which just returns YOUR OWN team again - not the
    -- camera's followed team - so this branch always fired and silently
    -- stuck on one fixed team no matter who was being watched. The real
    -- POV team comes from Spring.GetSpectatingState() instead.
    local isSpec, fullView, fullSelect, povTeam = spGetSpectatingState()
    if isSpec and povTeam and povTeam >= 0 then
        return povTeam
    end


    -- CASE C: SPECTATOR CLICKING UNITS
    local sel = Spring.GetSelectedUnits()
    if sel and #sel > 0 then
        local uTeam = Spring.GetUnitTeam(sel[1])
        if uTeam then
            return uTeam
        end
    end

    -- CASE D: Fallback
    return teamID
end

-- SAMPLE ECO
local function SampleEco()
    if paused then return end

    -- FIX: GetViewedTeamID() had a broken replay-POV branch that silently
    -- stuck this on one fixed team regardless of who you were watching.
    -- Spring.GetMyTeamID() is what the header already uses and correctly
    -- tracks whoever a spectator is currently following.
    local teamID = Spring.GetMyTeamID()
    local t      = spDiffTimers(spGetTimer(), startTimer)

    
    -- SAMPLE RATE LIMIT (~20 Hz)
    if lastSampleTime > 0 and (t - lastSampleTime) < (1/20) then
        return
    end
    lastSampleTime = t

    -- RAW RESOURCE PULLS
    local _, _, _, mInc, mExp, _, mOther = spGetTeamResources(teamID, "metal")
    local _, _, _, eInc, eExp            = spGetTeamResources(teamID, "energy")

    mInc   = mInc   or 0
    mExp   = mExp   or 0
    eInc   = eInc   or 0
    eExp   = eExp   or 0
    mOther = mOther or 0

    -- RESET SMOOTHING WHEN SWITCHING VIEWED TEAM
    if teamID ~= lastTeamID then
        -- Metal breakdown smoothing
        smoothMexIncome        = nil
        smoothConversionIncome = nil
        smoothOtherIncome      = nil

        -- Energy breakdown smoothing
        smoothEnergyGen        = nil
        smoothEnergyShare      = nil
        smoothEnergyReclaim    = nil
        rawEnergyTotal         = nil

        -- Storage smoothing
        smoothEnergyCur        = nil
        smoothMetalCur         = nil

        -- Engine totals smoothing
        smoothMetalIncome      = nil
        smoothMetalUsage       = nil
        smoothEnergyIncome     = nil
        smoothEnergyUsage      = nil
        smoothMetal            = nil
        smoothEnergy           = nil

        lastTeamID = teamID
    end

    -- REAL MEX INCOME (extractor-based)
    local mexIncomeRaw = 0
    local units = Spring.GetTeamUnits(teamID)

    for i = 1, #units do
        local udid = Spring.GetUnitDefID(units[i])
        local ud   = UnitDefs[udid]
        if ud and ud.extractsMetal and ud.extractsMetal > 0 then
            local spot = Spring.GetUnitMetalExtraction(units[i])
            mexIncomeRaw = mexIncomeRaw + spot
        end
    end

    local mexIncome = mexIncomeRaw

    -- METAL: ENERGY CONVERSION INCOME
    local conversionIncome = WG.convMetal or 0

    -- METAL: OTHER (reclaim + share)
    local otherIncome = mInc - mexIncome - conversionIncome
    if otherIncome < 0 then otherIncome = 0 end

    -- SMOOTH MEX / CONVERSION / OTHER
    if not smoothMexIncome then smoothMexIncome = mexIncome end
    smoothMexIncome = smoothingAlpha * mexIncome + (1 - smoothingAlpha) * smoothMexIncome

    if not smoothConversionIncome then smoothConversionIncome = conversionIncome end
    smoothConversionIncome = smoothingAlpha * conversionIncome + (1 - smoothingAlpha) * smoothConversionIncome

    if not smoothOtherIncome then smoothOtherIncome = otherIncome end
    smoothOtherIncome = smoothingAlpha * otherIncome + (1 - smoothingAlpha) * smoothOtherIncome


    -- ENERGY INCOME BREAKDOWN (Generators + Reclaim + Share)
    -- Energy received from allies
    local shareIn = Spring.GetTeamRulesParam(teamID, "energyReceived") or 0

    -- Generator energy (sum of all unit energyMake)
    local generatorEnergy = 0
    for i = 1, #units do
        local udid = Spring.GetUnitDefID(units[i])
        local ud   = UnitDefs[udid]
        if ud and ud.energyMake and ud.energyMake > 0 then
            generatorEnergy = generatorEnergy + ud.energyMake
        end
    end

    -- Reclaim energy (residual)
    local reclaimEnergy = eInc - generatorEnergy - shareIn
    if reclaimEnergy < 0 then reclaimEnergy = 0 end

    -- SMOOTH ENERGY GEN / SHARE / RECLAIM
    if not smoothEnergyGen then smoothEnergyGen = generatorEnergy end
    smoothEnergyGen = smoothingAlpha * generatorEnergy + (1 - smoothingAlpha) * smoothEnergyGen

    if not smoothEnergyShare then smoothEnergyShare = shareIn end
    smoothEnergyShare = smoothingAlpha * shareIn + (1 - smoothingAlpha) * smoothEnergyShare

    if not smoothEnergyReclaim then smoothEnergyReclaim = reclaimEnergy end
    smoothEnergyReclaim = smoothingAlpha * reclaimEnergy + (1 - smoothingAlpha) * smoothEnergyReclaim

    -- True energy income (your own total)
    rawEnergyTotal = smoothEnergyGen + smoothEnergyReclaim + smoothEnergyShare

    -- STORAGE VALUES (existing logic)
    local mCur, _ = spGetTeamResources(teamID, "metal")
    local _, mStorage = spGetTeamResources(teamID, "metal")
    local eCur, eStorage = spGetTeamResources(teamID, "energy")

    mCur = mCur or 0
    eCur = eCur or 0

    if not smoothEnergyCur then
        smoothEnergyCur = eCur
        smoothMetalCur  = mCur
    end

    smoothEnergyCur = smoothingAlpha * eCur + (1 - smoothingAlpha) * smoothEnergyCur
    smoothMetalCur  = smoothingAlpha * mCur + (1 - smoothingAlpha) * smoothMetalCur

    -- SMOOTH ENGINE TOTALS (existing logic)
    if not smoothMetalIncome then
        smoothMetalIncome  = mInc
        smoothMetalUsage   = mExp
        smoothEnergyIncome = eInc
        smoothEnergyUsage  = eExp
        smoothMetal        = mInc - mExp
        smoothEnergy       = eInc - eExp
    end

    smoothMetalIncome  = smoothingAlpha * mInc + (1 - smoothingAlpha) * smoothMetalIncome
    smoothMetalUsage   = smoothingAlpha * mExp + (1 - smoothingAlpha) * smoothMetalUsage
    smoothEnergyIncome = smoothingAlpha * eInc + (1 - smoothingAlpha) * smoothEnergyIncome
    smoothEnergyUsage  = smoothingAlpha * eExp + (1 - smoothingAlpha) * smoothEnergyUsage

    smoothMetal  = smoothMetalIncome  - smoothMetalUsage
    smoothEnergy = smoothEnergyIncome - smoothEnergyUsage

    -- HISTORY PUSH
    history.metal[#history.metal+1] = {
        t      = t,
        income = smoothMetalIncome,
        usage  = smoothMetalUsage,
        net    = smoothMetal,
    }

    history.energy[#history.energy+1] = {
        t      = t,
        income = smoothEnergyIncome,
        usage  = smoothEnergyUsage,
        net    = smoothEnergy,
    }

    -- HISTORY TRIM
    if #history.metal > historyMaxSamples  then table.remove(history.metal, 1) end
    if #history.energy > historyMaxSamples then table.remove(history.energy, 1) end

    local cutoff = t - cfg.historySeconds

    while #history.metal > 0 and history.metal[1].t < cutoff do
        table.remove(history.metal, 1)
    end

    while #history.energy > 0 and history.energy[1].t < cutoff do
        table.remove(history.energy, 1)
    end
end

function DrawPanelStats(label, income, usage, xCenter, yTop, incomeColor, usageColor)
    ------------------------------------------------------------
    -- SINGLE-LINE PANEL STATS:  Use   Net   Income
    ------------------------------------------------------------
    local net = income - usage

    -- Cache the formatted strings (and their measured widths) per label
    -- (Metal/Energy), keyed on the raw income/usage values. SampleEco()
    -- only updates these at ~20Hz, so between economy ticks they're
    -- bit-identical across many render frames -- skip rebuilding the
    -- strings and re-measuring their width when nothing actually changed.
    widget._statsCache = widget._statsCache or {}
    local cache = widget._statsCache[label]
    if not cache then
        cache = {}
        widget._statsCache[label] = cache
    end

    local useStr, incStr, netStr, useW, incW, netW
    if cache.income == income and cache.usage == usage then
        useStr, incStr, netStr = cache.useStr, cache.incStr, cache.netStr
        useW, incW, netW = cache.useW, cache.incW, cache.netW
    else
        -- Build strings (patched with K/M formatting)
        useStr = "Use: " .. FormatIncome(usage)
        incStr = "Income: " .. FormatIncome(income)
        netStr = "Net: " .. FormatIncome(net)

        useW = glGetTextWidth(useStr) * fontSize
        incW = glGetTextWidth(incStr) * fontSize
        netW = glGetTextWidth(netStr) * fontSize

        cache.income, cache.usage = income, usage
        cache.useStr, cache.incStr, cache.netStr = useStr, incStr, netStr
        cache.useW, cache.incW, cache.netW = useW, incW, netW
    end

    local pad = 10
    local totalW = useW + pad + incW + pad + netW
    local leftX = xCenter - (totalW * 0.5)
    local y = yTop

    ------------------------------------------------------------
    -- FULL-LINE HITBOX FOR METAL / ENERGY TOOLTIP
    ------------------------------------------------------------
    local lineX1 = leftX
    local lineX2 = leftX + totalW
    local lineY1 = y - fontSize
    local lineY2 = y + fontSize

    if label == "Energy" then
        energyIncRect = widget._setRect(energyIncRect, lineX1, lineY1, lineX2, lineY2)
    elseif label == "Metal" then
        metalIncRect = widget._setRect(metalIncRect, lineX1, lineY1, lineX2, lineY2)
    end

    -- DRAW: Use
    glColor(usageColor)
    glText(useStr, leftX + useW * 0.5, y, fontSize, "oc")

    -- DRAW: Income
    glColor(incomeColor)
    glText(incStr, leftX + useW + pad + incW * 0.5, y, fontSize, "oc")

    -- DRAW: Net
    glColor(net >= 0 and cfg.netPosColor or cfg.netNegColor)
    glText(netStr, leftX + useW + pad + incW + pad + netW * 0.5, y, fontSize, "oc")

    end


local function BuildGraphList()



local graphMarginLeft  = 0.10   -- pushes Energy graph right
local graphMarginRight = 0.10  -- pushes Metal graph left


    if compactMode then
        if graphList then glDeleteList(graphList) graphList = nil end
        widget._bgToggleRect = nil   -- no stale hitbox while the button isn't drawn
        return
    end

    local metal  = history.metal
    local energy = history.energy

    if #metal < 2 or #energy < 2 then
        if graphList then glDeleteList(graphList) graphList = nil end
        return
    end

    local x1,y1,x2,y2 = box.x1, box.y1, box.x2, box.y2
    local w,h         = x2-x1, y2-y1

    local margin = cfg.innerMargin
    local mid    = x1 + w * 0.5

    -- PANEL DEFINITIONS
    local panels = {
        {
            name        = "Metal",
            data        = metal,
            x1          = x1 - 10,
            x2          = mid - 60,
            incomeColor = cfg.metalIncomeColor,
            usageColor  = cfg.metalUsageColor,
        },
        {
            name        = "Energy",
            data        = energy,
            x1          = mid + 120,
            x2          = x2,
            incomeColor = cfg.energyIncomeColor,
            usageColor  = cfg.energyUsageColor,
        }
    }

    if graphList then glDeleteList(graphList) end

    graphList = glCreateList(function()
        
        -- BACKGROUND + BORDER
        local bgCol = widget._transparentMode and cfg.bgColorTransparent or cfg.bgColor
        glColor(bgCol)
        glRect(x1,y1,x2,y2)

        glColor(cfg.borderColor)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, function()
            glVertex(x1,y1); glVertex(x2,y1)
            glVertex(x2,y1); glVertex(x2,y2)
            glVertex(x2,y2); glVertex(x1,y2)
            glVertex(x1,y2); glVertex(x1,y1)
        end)

        ------------------------------------------------------------
        -- BACKGROUND MODE TOGGLE
        -- Sits in the empty gap between the Metal graph (ends at
        -- mid-60) and the Energy graph (starts at mid+120) -- the
        -- only unused space in this layout, confirmed against a
        -- screenshot of the live widget. Click toggles between the
        -- "Default" (opaque) and "Transparent" (bgColorTransparent,
        -- alpha 0) background set above.
        ------------------------------------------------------------
        do
            local barY = y1 + (h * margin) - 5
            local barH = 12
            local gy1  = barY + barH + 5    -- matches graphBottomPadding below
            local gy2  = y2 - 24            -- matches graphTopPadding below

            local tgCenterX = mid + 30      -- center of the mid-60..mid+120 gap
            local tgW, tgH  = 96, 22
            local tgX1 = tgCenterX - tgW * 0.5
            local tgX2 = tgCenterX + tgW * 0.5
            local tgCenterY = (gy1 + gy2) * 0.5
            local tgY1 = tgCenterY - tgH * 0.5
            local tgY2 = tgCenterY + tgH * 0.5

            -- Stored on `widget` (not a new local) for the same 200-local
            -- reason as widget._transparentMode above; read back by
            -- widget:MousePress for hit-testing.
            widget._bgToggleRect = { x1 = tgX1, y1 = tgY1, x2 = tgX2, y2 = tgY2 }

            glColor(0, 0, 0, widget._transparentMode and 0.35 or 0.55)
            glRect(tgX1, tgY1, tgX2, tgY2)

            glColor(1, 1, 1, 0.45)
            glLineWidth(1)
            glBeginEnd(GL_LINES, function()
                glVertex(tgX1, tgY1); glVertex(tgX2, tgY1)
                glVertex(tgX2, tgY1); glVertex(tgX2, tgY2)
                glVertex(tgX2, tgY2); glVertex(tgX1, tgY2)
                glVertex(tgX1, tgY2); glVertex(tgX1, tgY1)
            end)

            glColor(1, 1, 1, 0.9)
            glText(widget._transparentMode and "BG: Off" or "BG: On", tgCenterX, tgCenterY - 4, 11, "oc")
        end

        -- PANEL LOOP
        for _, panel in ipairs(panels) do
            local px1 = panel.x1
            local px2 = panel.x2
            local pw  = px2 - px1

            -- local gx1 = px1 + pw * margin
            local gx1 = px1 + pw * graphMarginLeft

            -- local gx2 = px2 - pw * margin
            local gx2 = px2 - pw * graphMarginRight
          
            -- GRAPH HEIGHT
            local barY = y1 + (h * margin) - 5
            -- Change height size of both the Metal & Energy Storage Bars
			local barH = 12

            -- local graphBottomPadding = 6
			local graphBottomPadding = 5 -- was 35 Lowers graph keep top anchored
            local gy1 = barY + barH + graphBottomPadding

		--  This line is to move the top portion of Meta and Energy dual line graph in full view mode
            local graphTopPadding = 24        --- was 43 -- shrink height
            local gy2 = box.y2 - graphTopPadding

            local gw  = gx2 - gx1
            local gh  = gy2 - gy1

            --------------------------------------------------------
            -- SCALE VALUES
            --------------------------------------------------------
            local data = panel.data
            local maxT = data[#data].t
            local minT = maxT - cfg.historySeconds

            local minV, maxV = math.huge, -math.huge

            for i = 1, #data do
                local s = data[i]
                if s.income < minV then minV = s.income end
                if s.usage  < minV then minV = s.usage  end
                if s.income > maxV then maxV = s.income end
                if s.usage  > maxV then maxV = s.usage  end
            end

            if minV == maxV then
                maxV = maxV + 1
                minV = minV - 1
            end

            local padding = (maxV - minV) * cfg.yPaddingFraction
            minV = minV - padding
            maxV = maxV + padding

            local rangeV = maxV - minV
            local rangeT = maxT - minT

            
            -- ZERO LINE
            local zeroY = gy1 + gh * ((0 - minV) / rangeV)
            glColor(cfg.gridColor)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(gx1, zeroY)
                glVertex(gx2, zeroY)
            end)

            
            -- VERTICAL GRID
            glColor(cfg.gridColor)
            glLineWidth(1.0)
            for j = 1, 3 do
                local frac = j / 4
                local gx   = gx1 + gw * frac
                glBeginEnd(GL_LINES, function()
                    glVertex(gx, gy1)
                    glVertex(gx, gy2)
                end)
            end

if not hideGraphs then
    -- INCOME CURVE
    glColor(panel.incomeColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, function()
        for i = 1, #data, 2 do
            local s  = data[i]
            local tf = (s.t - minT) / rangeT
            local vf = (s.income - minV) / rangeV
            glVertex(gx1 + gw * tf, gy1 + gh * vf)
        end
    end)

    -- USAGE CURVE
    glColor(panel.usageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, function()
        for i = 1, #data, 2 do
            local s  = data[i]
            local tf = (s.t - minT) / rangeT
            local vf = (s.usage - minV) / rangeV
            glVertex(gx1 + gw * tf, gy1 + gh * vf)
        end
    end)
end



-- METAL STORAGE BAR
if panel.name == "Metal" then
    local teamID = Spring.GetMyTeamID()
local mCur, _ = spGetTeamResources(teamID, "metal")
local _, mStorage = spGetTeamResources(teamID, "metal")

    mCur     = mCur or 0
    mStorage = mStorage or 1


local frac
if not metalShareEnabled or metalSharePercent == 0 then
    -- Auto-share OFF → show actual storage fill
    frac = math.max(0, math.min(1, mCur / mStorage))
else
    -- Auto-share ON → show actual fill CLAMPED to keep threshold
    local actualFill   = mCur / mStorage
    local keepFraction = 1 - metalSharePercent
    frac = math.min(actualFill, keepFraction)
end

    -- Dynamic Metal bar width (mirror of Energy)
    local panelW = gx2 - gx1
    local barW   = panelW * 0.50

    -- Center of the panel
    local barX = (gx1 + gx2) * 0.5

    -- ORIGINAL barLeft (used by pulldown + storage text)
    local barLeftOriginal = barX - (barW * 0.5)

    -- OFFSET for bar ONLY
    local barOffset = -20   -- move bar 20px left

    -- SHIFTED barLeft (used ONLY for drawing the bar)
    local barLeft = barLeftOriginal + barOffset

    -- Prevent overlap with Metal availability text
local metalAvailX = metalShareButtonRect.x1 - 150   -- your existing Metal text X
local maxBarRight = metalAvailX - 10               -- 10px safety gap

local barRight = barLeft + barW
if barRight > maxBarRight then
    barW = maxBarRight - barLeft
end

    --------------------------------------------------------
    -- DRAW THE BAR (this is what was missing)
    --------------------------------------------------------
    -- Background
    local r,g,b = unpack(cfg.metalIncomeColor)
    glColor(r, g, b, 0.20)
    glRect(barLeft, barY, barLeft + barW, barY + barH)

    -- Fill
    local fillW = barW * frac
    if fillW > 0 then
        glColor(r, g, b, 0.90)
        glRect(barLeft, barY, barLeft + fillW, barY + barH)
    end

    -- Tick
    if frac > 0 then
        local curX = barLeft + fillW
        glColor(1,1,1,1)
        glRect(curX - 1, barY - 2, curX + 1, barY + barH + 2)
    end

-- CENTERED SHARE BUTTONS (Metal left, Energy right)
local spacing = 30   -- gap between buttons

-- METAL LABEL
local metalLabel = GetMetalShareLabel()
local metalLabelW = glGetTextWidth(metalLabel) * fontSize

-- AUTO‑SIZE METAL BUTTON WIDTH TO FIT TEXT
local metalLabel = GetMetalShareLabel()
local metalTextW = gl.GetTextWidth(metalLabel) * fontSize
local metalPadding = 28
local metalButtonW = metalTextW + metalPadding


-- ENERGY LABEL
local energyLabel = GetEnergyShareLabel()
local energyLabelW = glGetTextWidth(energyLabel) * fontSize
local energyButtonW = energyLabelW + 10

-- Total width of both buttons + spacing
local totalW = metalButtonW + spacing + energyButtonW

-- Center anchor (same as Status/Wind)
local centerX = (box.x1 + box.x2) * 0.5
local statusCenterX = centerX + 35

-- Left edge of the pair
local leftX = statusCenterX - (totalW * 0.5)

-- METAL BUTTON (left)
local bx1 = leftX
local bx2 = bx1 + metalButtonW
local by1 = barY - 3    -- left only Metal pulldown vertical Y
local by2 = by1 + (fontSize + 6 * FONT_SCALE)

metalShareButtonRect.x1 = bx1
metalShareButtonRect.y1 = by1
metalShareButtonRect.x2 = bx2
metalShareButtonRect.y2 = by2

-- ENERGY BUTTON (right)
local ex1 = bx2 + spacing
local ex2 = ex1 + energyButtonW

energyShareButton.x1 = ex1
energyShareButton.y1 = by1
energyShareButton.x2 = ex2
energyShareButton.y2 = by2

    --------------------------------------------------------
    -- STORAGE TEXT (must also use barLeftOriginal)
    --------------------------------------------------------
    local totalText = string.format("[%.1fK]", mStorage / 1000)
    glColor(cfg.titleColor)
    -- Nudging the Metal Storage BAR left or right barW = 15
    glText(totalText, barLeftOriginal + barW - 15, barY + 2, fontSize, "l")

end

            -- ENERGY STORAGE BAR
            if panel.name == "Energy" then
                local teamID = Spring.GetMyTeamID()
                local eCur, eStorage = spGetTeamResources(teamID, "energy")

                eCur     = eCur or 0
                eStorage = eStorage or 1

                local frac = math.max(0, math.min(1, eCur / eStorage))
				
				-- Dynamic Energy bar width (fraction of panel width)
				local panelW = gx2 - gx1
                -- Adjust Energy Bar as in not overlapping the Energy Available State on it's left side.
				local barW   = panelW * 0.45     -- 28% of panel width (tweakable)
				local barX   = (gx1 + gx2) * 0.5
				local barLeft = barX - (barW * 0.5)
                

                -- BAR BACKGROUND
                glColor(1,1,0,0.20)
                glRect(barLeft, barY, barLeft + barW, barY + barH)

                
                -- BAR FILL (two-tone sheen)
                local fillW = barW * frac
                if fillW > 0 then
                    -- Bottom half (base color)
                    glColor(1, 1, 0, 0.90)
                    glRect(barLeft, barY, barLeft + fillW, barY + barH * 0.5)

                    -- Top half (lighter sheen)
                    glColor(1, 1, 0.98, 0.95)  -- slightly lighter yellow
                    glRect(barLeft, barY + barH * 0.5, barLeft + fillW, barY + barH)
                end


                -- WHITE TICK
                if frac > 0 then
                    local curX = barLeft + fillW
                    glColor(1,1,1,1)
                    glRect(curX - 1, barY - 2, curX + 1, barY + barH + 2)
                end

-- CENTERED SHARE BUTTONS (Metal left, Energy right)
local spacing = 30   -- increased gap between buttons

-- METAL LABEL
local metalLabel = GetMetalShareLabel()
local metalLabelW = glGetTextWidth(metalLabel) * fontSize

-- AUTO‑SIZE METAL BUTTON WIDTH TO FIT TEXT
local metalLabel = GetMetalShareLabel()
local metalTextW = gl.GetTextWidth(metalLabel) * fontSize
local metalPadding = 48   --- working one puts a gap between the two share pulldown buttons (metal & energy)
local metalButtonW = metalTextW + metalPadding


-- ENERGY LABEL
local energyLabel = GetEnergyShareLabel()
local energyLabelW = glGetTextWidth(energyLabel) * fontSize
local energyButtonW = energyLabelW + 10

-- Total width of both buttons + spacing
local totalW = metalButtonW + spacing + energyButtonW

-- Center anchor (same as Status/Wind)
local centerX = (box.x1 + box.x2) * 0.5
local statusCenterX = centerX + 35

-- Left edge of the pair
local leftX = statusCenterX - (totalW * 0.5)

-- METAL BUTTON (left)
local bx1 = leftX
local bx2 = bx1 + metalButtonW
local by1 = barY - 3
local by2 = by1 + (fontSize + 6 * FONT_SCALE)

metalShareButtonRect.x1 = bx1
metalShareButtonRect.y1 = by1
metalShareButtonRect.x2 = bx2
metalShareButtonRect.y2 = by2

-- ENERGY BUTTON (right)
local ex1 = bx2 + spacing
local ex2 = ex1 + energyButtonW

energyShareButton.x1 = ex1
energyShareButton.y1 = by1
energyShareButton.x2 = ex2
energyShareButton.y2 = by2

-- ENFORCE MINIMUM GAP BETWEEN METAL AND ENERGY SHARE BUTTONS
local minGap = 20  -- adjust to taste

if energyShareButton.x1 < metalShareButtonRect.x2 + minGap then
    local shift = (metalShareButtonRect.x2 + minGap) - energyShareButton.x1
    energyShareButton.x1 = energyShareButton.x1 + shift
    energyShareButton.x2 = energyShareButton.x2 + shift
end

-- HISTORY SECONDS SELECTOR (Full View, Compact Style)
if not hideGraphs then
    -- Compute center
    local centerX = box.x1 + (box.x2 - box.x1) * 0.5

    -- Position (mirrors Compact Mode but adjusted for Full View height)
    local hx1 = centerX + 220   -- default is 80
    local hx2 = box.x2 - 10
    local hy1 = box.y1 + 30
    local hy2 = hy1 + 20

    -- Background
    glColor(0, 0, 0, 0.25)
    glRect(hx1, hy1, hx2, hy2)

    -- Options
    local opts  = cfg.historyOptions   -- {20,30,40,50,60}
    local count = #opts
    local w     = (hx2 - hx1) / count

    for i = 1, count do
        local x1  = hx1 + (i-1)*w
        local x2  = x1 + w
        local sec = opts[i]

        -- Highlight selected
        if sec == cfg.historySeconds then
            glColor(1,1,1,0.15)
            glRect(x1, hy1, x2, hy2)
        end

        glColor(1,1,1,0.75)
        glText(sec.."s", x1 + w*0.5, hy1 + 3, 11, "oc")
    end
end -- hideGraphs

     
                -- STORAGE TEXT
                local totalText = string.format("[%.1fK]", eStorage / 1000)
                glColor(cfg.titleColor)
                glText(totalText, barLeft + barW + 6, barY + 2, fontSize, "l")
            end

            -- TOP-CENTER PANEL STATS
            local teamID = Spring.GetMyTeamID()
            local inc, exp
            if panel.name == "Metal" then
                inc = smoothMetalIncome or 0
                exp = smoothMetalUsage or 0
            else
                inc = smoothEnergyIncome or 0
                exp = smoothEnergyUsage or 0
            end

            local statsX = (gx1 + gx2) * 0.5
            local statsY = box.y2 - 20


            DrawPanelStats(
                panel.name,
                inc or 0,
                exp or 0,
                statsX,
                statsY,
                panel.incomeColor,
                panel.usageColor
            )
        end
    
        -- RESIZE HANDLE
        glColor(1,1,1,0.8)
        glRect(box.x2 - resizeHandleSize, box.y1,
               box.x2, box.y1 + resizeHandleSize)
    end)
	
        -- METAL INC HITBOX (outside glList)
    do
        local metalPanel = panels[1]
        if metalPanel then
            local px1 = metalPanel.x1
            local px2 = metalPanel.x2
            local pw  = px2 - px1

            local gx1 = px1 + pw * margin
            local gx2 = px2 - pw * margin

            local statsX = (gx1 + gx2) * 0.5
            local statsY = box.y2 - 20
            local inc    = smoothMetalIncome or 0

            local incStr = string.format("Metal Inc: %.1f", inc)
            local incW   = glGetTextWidth(incStr) * fontSize


        end
    end
    end

-- COMPLETE, TOP-BAR-ACCURATE, KILL-EVENT-SAFE VERSION
local function GetCommanderCounts()
    local myTeamID     = spGetMyTeamID()
    local myAllyTeamID = spGetMyAllyTeamID()

    
    -- 1. Rebuild ally team list (Top Bar does this)
    local myAllyTeams = {}
    local allTeams = spGetTeamList() or {}

    for _, teamID in ipairs(allTeams) do
        local _, _, isDead, _, _, allyTeamID = spGetTeamInfo(teamID)
        if not isDead and allyTeamID == myAllyTeamID then
            myAllyTeams[#myAllyTeams+1] = teamID
        end
    end

    -- 2. Count ALLY commanders (local scan)
    local ally = 0
    for _, teamID in ipairs(myAllyTeams) do
        for _, defID in ipairs(commanderUnitDefIDs) do
            ally = ally + spGetTeamUnitDefCount(teamID, defID)
        end
    end

    -- 3. Enemy count from synced gadget (always correct)
    local enemy = spGetTeamRulesParam(myTeamID, "enemyComCount")

    -- 4. Fallback for spectators / replays / AI kill events
    --    (Top Bar does this — full unit scan)
    if ally == 0 then
        local units = Spring.GetAllUnits()
        for _, unitID in ipairs(units) do
            local unitDefID = Spring.GetUnitDefID(unitID)
            if unitDefID then
                local ud = UnitDefs[unitDefID]
                if ud and ud.customParams and ud.customParams.iscommander then
                    local teamID = Spring.GetUnitTeam(unitID)
                    local _, _, isDead, _, _, allyTeamID = spGetTeamInfo(teamID)
                    if not isDead and allyTeamID == myAllyTeamID then
                        ally = ally + 1
                    end
                end
            end
        end
    end

    -- 5. Enemy fallback (rare, but Top Bar includes it)
    if enemy == nil then
        enemy = 0
        for _, teamID in ipairs(allTeams) do
            local _, _, isDead, _, _, allyTeamID = spGetTeamInfo(teamID)
            if not isDead and allyTeamID ~= myAllyTeamID then
                for _, defID in ipairs(commanderUnitDefIDs) do
                    enemy = enemy + spGetTeamUnitDefCount(teamID, defID)
                end
            end
        end
    end

    return ally, enemy
end


-- COMMANDER COUNT CACHE + GAMEFRAME BINDING
local commanderC1, commanderC2 = 0, 0
local spGetGameFrame = Spring.GetGameFrame
local historyCache = {}   -- teamID → {metal={}, energy={}}


-- UPDATED GAMEFRAME (SAFE, LOW-MEMORY)
function widget:GameFrame()

    if not showWidget then return end

    local gf = spGetGameFrame()

    ----------------------------------------------------------------------
    -- THROTTLE: update only every 15 frames (~0.5 seconds)
    ----------------------------------------------------------------------
    if (gf - (lastUpdate or 0)) < 3 then  -- 3 frames is about 0.1 seconds, adjust as needed
        return
    end
    lastUpdate = gf
    ----------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- PRE-GAME: ensure history tables exist and have at least 1 sample
    ----------------------------------------------------------------------
    if gf < 1 then
        local t = os.clock()

        if not history.metal or #history.metal == 0 then
            history.metal = {
                { t = t, income = 0, usage = 0 },
            }
        end

        if not history.energy or #history.energy == 0 then
            history.energy = {
                { t = t, income = 0, usage = 0 },
            }
        end
    end
    ----------------------------------------------------------------------

    local actualTeam = GetActualViewedTeamID()
    local safeTeam   = GetSafeViewedTeamID()

    -- Handle team switching (replay/spec)
    if lastViewedTeam ~= actualTeam then
        if lastViewedTeam then
            historyCache[lastViewedTeam] = {
                metal  = history.metal,
                energy = history.energy,
            }
        end

        if historyCache[actualTeam] then
            history.metal  = historyCache[actualTeam].metal
            history.energy = historyCache[actualTeam].energy
        else
            ResetHistory()
        end

        fadeAlpha     = 0
        fadeStartTime = spGetTimer()
        lastViewedTeam = actualTeam
    end

    -- Update commander counts only every 15 frames
    if gf % 15 == 0 then
        commanderC1, commanderC2 = GetCommanderCounts()
    end

    UpdateFade()
    SampleEco()

    if graphList then
        glDeleteList(graphList)
    end
    BuildGraphList()
end


-- UPDATED DRAW OVERLAY (USES CACHED COMMANDER COUNTS)
local function DrawOverlay()
    local teamID     = Spring.GetMyTeamID()
    local playerName = GetPlayerNameFromTeam(teamID)
    local faction    = DetectFaction(teamID)

    -- SYNC SHARE SETTINGS WITH ENGINE (METAL + ENERGY)
    local engineMetalShare  = Spring.GetTeamRulesParam(teamID, "teamShareMetal")
    local engineEnergyShare = Spring.GetTeamRulesParam(teamID, "teamShareEnergy")

    if engineMetalShare then
        metalSharePercent = engineMetalShare
    end

    if engineEnergyShare then
        energySharePercent = engineEnergyShare
    end

    -- RESOURCE DATA
    local mCur, _, _, mInc, mExp = spGetTeamResources(teamID, "metal")
    local eCur, _, _, eInc, eExp = spGetTeamResources(teamID, "energy")

    mCur = mCur or 0
    eCur = eCur or 0
    mInc = mInc or 0
    eInc = eInc or 0
    mExp = mExp or 0
    eExp = eExp or 0

    local mNet = mInc - mExp
    local eNet = eInc - eExp

    local _, mStorage = spGetTeamResources(teamID, "metal")
    local _, eStorage = spGetTeamResources(teamID, "energy")

    local status = GetEcoStatus(
        mNet, eNet,
        mInc, eInc,
        mCur, eCur,
        mStorage, eStorage
    )

-- HEADER + STATUS
local centerX = (box.x1 + box.x2) * 0.5

-- ECO GRAPH: PlayerName (single row)
local title = "Eco Graph: "
local titleW = glGetTextWidth(title) * (titleSize + 8)

-- Draw title
glColor(cfg.titleColor)
glText(title, box.x1 + 6, box.y2 - 20, titleSize + 8, "o")

-- Draw player name immediately after title
local r, g, b = Spring.GetTeamColor(teamID)
glColor(r, g, b, 1)

-- ⭐ NEW: shorten the name
local shortName = ShortenPlayerName(playerName)

glText(shortName, box.x1 + 6 + titleW, box.y2 - 20, titleSize + 8, "o")

glColor(cfg.titleColor)

local col = statusColors[status] or {1,1,1,1}
glColor(col)
glText(string.format("Status: %s", status),
    centerX + 35, box.y2 - 20, (fontSize + 4 * FONT_SCALE), "oc")


    -- CLOSE BUTTON GEOMETRY (needed for Pause/T midpoint)
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = glGetTextWidth(hideLabel) * hideSize
    local hx1       = box.x2 - hideWidth - 6
    local hy1       = box.y2 - 20

------------------------------------------------------------
-- PAUSE BUTTON + TRANSPARENCY TOGGLE (T sits between Pause and [X])
-- The T toggle here is the MAIN window's own transparency flag
-- (widget._transparentMode) -- independent of the detached dual-line
-- graph's own toggle/flag.
------------------------------------------------------------
do
    -- Transparency toggle, directly left of [X]
    local tLabel = widget._transparentMode and "[T]" or "[D]"
    local tSize  = 14 * FONT_SCALE
    -- Reserve width for the wider of the two labels so the button
    -- doesn't shift position when the label swaps between them.
    local tWidth = math.max(glGetTextWidth("[D]"), glGetTextWidth("[T]")) * tSize

    local tx = hx1 - tWidth - 8   -- 8px gap between T and [X]
    local ty = hy1

    mainTransparentToggleRect = {
        x1 = tx,
        y1 = ty - tSize,
        x2 = tx + tWidth,
        y2 = ty + tSize
    }

    glColor(cfg.titleColor)
    glText(tLabel, tx, ty, tSize, "o")

    local pauseLabel = "[Pause]"
    local pauseSize  = 14 * FONT_SCALE
    local pauseWidth = glGetTextWidth(pauseLabel) * pauseSize

    -- Position Pause directly left of the transparency toggle
    local px = tx - pauseWidth - 8   -- 8px gap between Pause and [T]/[D]
    local py = hy1                    -- same vertical alignment

    -- Save hitbox for click detection
    pauseButtonRect = {
        x1 = px,
        y1 = py - pauseSize,
        x2 = px + pauseWidth,
        y2 = py + pauseSize
    }

    -- Draw Pause label
    glColor(cfg.titleColor)
    glText(pauseLabel, px, py, pauseSize, "o")
end


-- DRAW CLOSE BUTTON
glColor(cfg.titleColor)
glText(hideLabel, hx1, hy1, hideSize, "o")

-- WIND METER (simple two‑line version)

-- ENGINE WIND LIMITS
local minW = Game.windMin or 0
local maxW = Game.windMax or 1

-- RAW ENGINE WIND (matches Top Bar exactly)
local _, _, _, curWind = Spring.GetWind()

-- Clamp to map range (Top Bar does not clamp, but prevents negatives)
curWind = math.min(maxW, math.max(minW, curWind))

-- EXACT BAR AVERAGE (Top Bar lookup table)
local avgWindLookup = windFunctions.averageWindLookup
local avgWind = avgWindLookup[minW] and avgWindLookup[minW][maxW]

-- fallback if lookup missing
if not avgWind then
    avgWind = minW + (maxW - minW) * 0.7
end

-- FRACTION FOR BAR FILL (raw wind / max)
local frac = math.max(0, math.min(1, curWind / maxW))

-- Position Wind directly under Status
local textY = box.y2 - 40
local barY  = textY - 16

-- X anchor (centered)
local centerX = (box.x1 + box.x2) * 0.5

-- TEXT LINE (Range uses whole numbers)
local textWind = string.format(
    "Wind: Avg %.1f   Cur %.1f   Range: %d–%d",
    avgWind, curWind,
    math.floor(minW + 0.5), math.floor(maxW + 0.5)
)

-- Draw text (Cur color-coded)
local beforeCur = string.format("Wind: Avg %.1f   ", avgWind)
local beforeCurW = glGetTextWidth(beforeCur) * fontSize

local curStr = string.format("Cur %.1f", curWind)
local curW   = glGetTextWidth(curStr) * fontSize

-- Draw entire line in white first
glColor(cfg.titleColor)
local statusCenterX = centerX + 35
glText(textWind, statusCenterX, textY, fontSize, "oc")

-- Overdraw Cur with color
local curX = statusCenterX - (glGetTextWidth(textWind) * fontSize) * 0.5 + beforeCurW + curW * 0.5

if frac <= 0.40 then
    glColor(1, 0, 0, 1)
elseif frac <= 0.75 then
    glColor(1, 1, 0, 1)
else
    glColor(0, 1, 0, 1)
end

glText(curStr, curX, textY, fontSize, "oc")

-- BAR (full width under text)
local barW = 200
local barH = 12
local barX = statusCenterX - barW * 0.5

-- background
glColor(0.6, 0.8, 1.0, 0.20)
glRect(barX, barY, barX + barW, barY + barH)

-- fill
local fillW = barW * frac
if fillW > 0 then
    glColor(0.3, 0.6, 1.0, 0.90)
    glRect(barX, barY, barX + fillW, barY + barH)
end

-- tick
if curWind > 0 then
    local curX2 = barX + fillW
    glColor(1, 1, 1, 1)
    glRect(curX2 - 1, barY - 2, curX2 + 1, barY + barH + 2)
end

-- Commander count colors 
local coldColor = {0.2, 1.0, 0.2, 1.0}
local warmColor = {1.0, 0.35, 0.2, 1.0}

-- COMMANDERS + TIDAL (single-line version)
local c1, c2 = commanderC1, commanderC2
local tidal  = Game.tidal or 0

local baseY = box.y2 - 32

local commandersCenterX = (box.x1 + centerX + 320) * 0.5
local tidalCenterX      = (centerX + box.x2 - 235) * 0.5

-- unified Y position (single line)
local commandersY = baseY + 12

-- label
glColor(cfg.titleColor)
glText("Commanders:", commandersCenterX, commandersY, fontSize, "oc")

-- shift numbers to the right of the label
local baseX = commandersCenterX + 70
local offset = 18

-- ally count
glColor(coldColor)
glText(string.format("%d", c1), baseX - offset, commandersY, (fontSize + 7 * FONT_SCALE), "oc")

-- vs
glColor(1, 1, 1, 1)
glText("vs", baseX, commandersY, fontSize, "oc")

-- enemy count
glColor(warmColor)
glText(string.format("%d", c2), baseX + offset, commandersY, (fontSize + 7 * FONT_SCALE), "oc")

glColor(cfg.titleColor)
local tidalText = string.format("Tidal: %.1f", tidal)
local tidalY = box.y2 - (fontSize * 1.6)

glText(tidalText, tidalCenterX, tidalY, fontSize, "oc")

-- CURRENT METAL AVAILABLE (aligned left of share buttons, auto‑shifts to avoid overlap)
do
    local teamID = Spring.GetMyTeamID()
    local mCur = select(1, Spring.GetTeamResources(teamID, "metal")) or 0

    local metalText = "Metal: " .. FormatCompact(mCur)
    local metalFont = (fontSize + 6 * FONT_SCALE)

    -- Align to the LEFT of the Metal share button
    local bx1 = metalShareButtonRect.x1
    local by1 = metalShareButtonRect.y1

    if bx1 and by1 then
        -- Dynamic offset logic to prevent overlap with storage/max text
        local desiredOffset = 150      -- your normal spacing
        local minOffset     = 60       -- never go closer than this
        local availableSpace = bx1 - box.x1

        -- Compute adaptive offset
        local offset = math.min(desiredOffset, math.max(minOffset, availableSpace * 0.6))

        -- local metalTextX = bx1 - offset
        local metalTextX = bx1 - 90   -- fixed position of metal availability 140 original
        local metalTextY = by1 + 5  -- Raise Metal Available upward 

        glColor(0.6, 0.9, 1.0, 1.0)
        glText(metalText, metalTextX, metalTextY, metalFont, "l")

------------------------------------------------------------
-- METAL ICON ABOVE METAL AVAILABLE
------------------------------------------------------------
local iconSize = 46

-- Center icon horizontally over the Metal Available text
local iconX = metalTextX - (iconSize * 0.5) + 100  -- lower goest left 

-- Place icon above the text
local iconY = metalTextY + metalFont + 6 - 15

gl.Texture(metalIconPath)
gl.Color(1,1,1,1)
gl.TexRect(iconX, iconY, iconX + iconSize, iconY + iconSize)
gl.Texture(false)

    end
end
    
    -- METAL SHARE BUTTON + DROPDOWN
    local bx1 = metalShareButtonRect.x1
    local by1 = metalShareButtonRect.y1
    local bx2 = metalShareButtonRect.x2
    local by2 = metalShareButtonRect.y2

    -- METAL SHARE BUTTON WIDTH (match Energy)
    local label = GetMetalShareLabel()
    local textW = gl.GetTextWidth(label) * fontSize
    local padding = 18
    local boxW = textW + padding

    metalShareButtonRect.x2 = metalShareButtonRect.x1 + boxW
    bx2 = metalShareButtonRect.x2   -- update local copy

    if bx1 and by1 and bx2 and by2 and bx1 ~= bx2 and by1 ~= by2 then
        local mx, my = spGetMouseState()

        local isHover = PointInRect(mx, my, bx1, by1, bx2, by2)

		glColor(cfg.titleColor)


    local label = GetMetalShareLabel()   -- ← REQUIRED FIX

 -- Throb when sharing
if IsMetalActuallySharing() then
    local pulse = 0.5 + 0.5 * math.sin(os.clock() * 6)
    glColor(0.6, 1.0, 1.0, 0.6 + 0.4 * pulse)  -- aqua pulse
else
    glColor(cfg.titleColor)
end
    glText(label, (bx1 + bx2) * 0.5, by1 + 6, fontSize, "oc") -- by1 + 6 raised Metal Share button up

            
-- METAL SHARE TOOLTIP (lower-right, 2-line description)
if isHover and not metalShareDropdownOpen then
    -- Tooltip text (2 lines)
    local tip1 = "Choose how much Metal"
    local tip2 = "to share with teammates."

    -- Padding + sizing
    local pad = 6
    local w1 = glGetTextWidth(tip1) * fontSize
    local w2 = glGetTextWidth(tip2) * fontSize
    local tw = math.max(w1, w2) + pad * 2
    local th = fontSize * 2 + pad * 3

    -- LOWER-RIGHT of mouse
    local tipX = mx + 18
    local tipY = my - th - 18

    -- Background (white bubble)
    glColor(1, 1, 1, 0.92)
    glRect(tipX, tipY, tipX + tw, tipY + th)

    -- Border (soft gray)
    glColor(0, 0, 0, 0.25)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, function()
        glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
        glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
        glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
        glVertex(tipX, tipY + th); glVertex(tipX, tipY)
    end)

    -- Centered text (black)
    glColor(0, 0, 0, 1)
    glText(tip1, tipX + tw * 0.5, tipY + th - fontSize - pad, fontSize, "oc")
    glText(tip2, tipX + tw * 0.5, tipY + pad, fontSize, "oc")
end

  
        -- DROPDOWN OPTIONS
        if metalShareDropdownOpen then
            metalShareOptionRects = {}

            local optionHeight = (by2 - by1)
            local gap = 2

			local openUp = false
			local totalHeight = (#metalShareOptions) * (optionHeight + gap)

			-- If dropdown would go off-screen at the bottom, flip upward
			if by1 - totalHeight < 0 then
				openUp = true
			end

			for i, opt in ipairs(metalShareOptions) do
				local oy1, oy2

				if openUp then
					-- open upward
					oy1 = by2 + (optionHeight + gap) * (i - 1)
					oy2 = oy1 + optionHeight
				else
					-- open downward (default)
					oy1 = by1 - (optionHeight + gap) * i
					oy2 = oy1 + optionHeight
				end
                local ox1 = bx1
                local ox2 = bx2

                metalShareOptionRects[i] = { x1 = ox1, y1 = oy1, x2 = ox2, y2 = oy2 }

                local hover = PointInRect(mx, my, ox1, oy1, ox2, oy2)

                if hover then
                    glColor(1, 1, 1, 0.20)
                else
                    glColor(0, 0, 0, 0.80)
                end
                glRect(ox1, oy1, ox2, oy2)

                glColor(1, 1, 1, 0.35)
                glLineWidth(1.0)
                glBeginEnd(GL_LINES, function()
                    glVertex(ox1, oy1); glVertex(ox2, oy1)
                    glVertex(ox2, oy1); glVertex(ox2, oy2)
                    glVertex(ox2, oy2); glVertex(ox1, oy2)
                    glVertex(ox1, oy2); glVertex(ox1, oy1)
                end)

                -- Option label
                local optLabel
                if opt == "Disable" then
                    optLabel = "Disable"
                else
                    optLabel = string.format("%d%%", math.floor(opt * 100 + 0.5))
                end

                glColor(cfg.titleColor)
                glText(optLabel, (ox1 + ox2) * 0.5, oy1 + 3, fontSize, "oc")
            end
        end
    end

-- CURRENT ENERGY AVAILABLE (aligned right of share buttons)
do
    local teamID = Spring.GetMyTeamID()
    local eCur = select(1, Spring.GetTeamResources(teamID, "energy")) or 0

    local energyText = "Energy: " .. FormatCompact(eCur)
    local energyFont = (fontSize + 6 * FONT_SCALE)

    -- Align to the RIGHT of the Energy share button
    local ex2 = energyShareButton.x2
    local ey1 = energyShareButton.y1

    if ex2 and ey1 then
        local energyTextX = ex2 + 5   -- 20px gap to the right
        local energyTextY = ey1 + 5    -- same Y row as share buttons -- Raise Energy Available

        glColor(1, 1, 0, 0.90)
        glText(energyText, energyTextX, energyTextY, energyFont, "l")

------------------------------------------------------------
-- ENERGY ICON ABOVE ENERGY AVAILABLE
------------------------------------------------------------
local iconSize = 46
local iconX = energyTextX - (iconSize * 0.5) + 2  -- center icon over text, lower goes right
local iconY = energyTextY + energyFont + 6 - 15   -- place above the text

gl.Texture(energyIconPath)
gl.Color(1,1,1,1)
gl.TexRect(iconX, iconY, iconX + iconSize, iconY + iconSize)
gl.Texture(false)

    end
end

-- ENERGY SHARE BUTTON + TOOLTIP + DROPDOWN
do
    local ex1 = energyShareButton.x1
    local ey1 = energyShareButton.y1
    local ex2 = energyShareButton.x2
    local ey2 = energyShareButton.y2

    if ex1 and ey1 and ex2 and ey2 and ex1 ~= ex2 and ey1 ~= ey2 then
        local mx, my = spGetMouseState()

        local isHover = PointInRect(mx, my, ex1, ey1, ex2, ey2)

        -- ENERGY SHARE LABEL WITH BRACKETS
        local label = GetEnergyShareLabel()
        glColor(cfg.titleColor)
        glText(label, (ex1 + ex2) * 0.5, ey1 + 6, fontSize, "oc")

        -- TOOLTIP (lower-right, 2-line description)
        if isHover and not energyShareDropdown then
            local tip1 = "Choose how much Energy"
            local tip2 = "to share with teammates."

            local pad = 6
            local w1 = glGetTextWidth(tip1) * fontSize
            local w2 = glGetTextWidth(tip2) * fontSize
            local tw = math.max(w1, w2) + pad * 2
            local th = fontSize * 2 + pad * 3

            -- LOWER-RIGHT of mouse
            local tipX = mx + 18
            local tipY = my - th - 18
            if (detached and detached.y1 and tipY < detached.y1 + 4) or tipY < 0 then
                tipY = my + 18
            end

            -- Background
            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            -- Border
            glColor(0, 0, 0, 0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            -- Text
            glColor(0, 0, 0, 1)
            glText(tip1, tipX + tw * 0.5, tipY + th - fontSize - pad, fontSize, "oc")
            glText(tip2, tipX + tw * 0.5, tipY + pad, fontSize, "oc")
        end
    end

            -- ENERGY SHARE DROPDOWN (Disable, 90 → 10)
            if energyShareDropdown then
                energyShareOptionRects = {}

                local optionHeight = (ey2 - ey1)
                local gap = 2

                local openUp = false
                local totalHeight = (#energyShareOptions) * (optionHeight + gap)

				-- If dropdown would go off-screen at the bottom, flip upward
				if ey1 - totalHeight < 0 then
					openUp = true
				end

				for i, opt in ipairs(energyShareOptions) do
					local oy1, oy2

					if openUp then
						-- open upward
						oy1 = ey2 + (optionHeight + gap) * (i - 1)
						oy2 = oy1 + optionHeight
					else
						-- open downward (default)
						oy1 = ey1 - (optionHeight + gap) * i
						oy2 = oy1 + optionHeight
					end
                    local ox1 = ex1
                    local ox2 = ex2

                    energyShareOptionRects[i] = { x1 = ox1, y1 = oy1, x2 = ox2, y2 = oy2 }

                    local hover = PointInRect(mx, my, ox1, oy1, ox2, oy2)

                    if hover then
                        glColor(1, 1, 1, 0.20)
                    else
                        glColor(0, 0, 0, 0.80)
                    end
                    glRect(ox1, oy1, ox2, oy2)

                    glColor(1, 1, 1, 0.35)
                    glLineWidth(1.0)
                    glBeginEnd(GL_LINES, function()
                        glVertex(ox1, oy1); glVertex(ox2, oy1)
                        glVertex(ox2, oy1); glVertex(ox2, oy2)
                        glVertex(ox2, oy2); glVertex(ox1, oy2)
                        glVertex(ox1, oy2); glVertex(ox1, oy1)
                    end)

                    local optLabel
                    if opt == "Disable" then
                        optLabel = "Disable"
                    else
                        optLabel = string.format("%d%%", opt)
                    end

                    glColor(cfg.titleColor)
                    glText(optLabel, (ox1 + ox2) * 0.5, oy1 + 3, fontSize, "oc")
                end
            end
        end
    end

-- AUTO-SHARE METAL (THRESHOLD-BASED: SHARE ONLY ABOVE % OF STORAGE)
if metalShareEnabled and metalSharePercent > 0 then
    local myTeam = Spring.GetMyTeamID()
    local myAlly = spGetLocalAllyTeamID()

    local cur, stor = spGetTeamResources(myTeam, "metal")
    cur  = cur or 0
    stor = stor or 0

    if stor > 0 then
        -- metalSharePercent is SHARE fraction (0.10 → 10%)
        local shareFraction = metalSharePercent
        local keepFraction  = 1 - shareFraction

        -- Threshold based on TOTAL STORAGE
        local _, realStorage = spGetTeamResources(myTeam, "metal")
        local keepAmount = realStorage * keepFraction

        -- Only share EXCESS above threshold
        if cur > keepAmount then
            local excess = cur - keepAmount

            -- Find ally recipients
            local teams = spGetTeamList()
            local recipients = {}

            for _, tID in ipairs(teams) do
                if tID ~= myTeam then
                    local _, _, isDead = Spring.GetTeamInfo(tID)
                    if not isDead then
                        local allyTeam = Spring.GetTeamAllyTeamID(tID)
                        if allyTeam == myAlly then
                            recipients[#recipients+1] = tID
                        end
                    end
                end
            end

            -- Evenly distribute excess
            local n = #recipients
            if n > 0 and excess > 0 then
                local shareEach = excess / n
                for _, rID in ipairs(recipients) do
                    spShareResources(rID, "metal", shareEach)
                end
            end
        end
    end
end

-- AUTO-SHARE ENERGY (KEEP THRESHOLD, MATCHES METAL)
do
    local sharePct = energySharePercent or 0

    if sharePct > 0 then
        local myTeam = Spring.GetMyTeamID()
        local myAlly = Spring.GetMyAllyTeamID()

        local cur, stor = Spring.GetTeamResources(myTeam, "energy")
        cur  = cur or 0
        stor = stor or 0

        if stor > 0 and cur > 0 then
            local shareFraction = sharePct * 0.01
            local keepFraction  = 1 - shareFraction
            local keepAmount    = stor * keepFraction

            if cur > keepAmount then
                local excess = cur - keepAmount
                local teams = Spring.GetTeamList()
                local recipients = {}

                for _, tID in ipairs(teams) do
                    if tID ~= myTeam then
                        local _, _, isDead = Spring.GetTeamInfo(tID)
                        if not isDead then
                            local allyTeam = Spring.GetTeamAllyTeamID(tID)
                            if allyTeam == myAlly then
                                recipients[#recipients+1] = tID
                            end
                        end
                    end
                end

                local n = #recipients
                if n > 0 and excess > 0 then
                    local shareEach = excess / n
                    for _, rID in ipairs(recipients) do
                        Spring.ShareResources(rID, "energy", shareEach)
                    end
                end
            end
        end
    end
end


local function UpdateConverterStats()
    local teamID = Spring.GetMyTeamID()
    local mmUse      = Spring.GetTeamRulesParam(teamID, "mmUse") or 0
    local mmCapacity = Spring.GetTeamRulesParam(teamID, "mmCapacity") or 0
    local mmAvgEffi  = Spring.GetTeamRulesParam(teamID, "mmAvgEffi") or 0

    convEnergy = mmUse
    convMetal  = mmUse * mmAvgEffi

    if mmCapacity > 0 then
        convUtil = math.floor((mmUse / mmCapacity) * 100 + 0.5)
    else
        convUtil = 0
    end
end

------------------------------------------------------------------------
-- TOP BAR OVERLAP DETECTION
--
-- The engine's "Top Bar" widget (gui_top_bar_reference.lua) publishes its
-- own screen rect for other widgets to query: WG['topbar'].GetPosition()
-- returns { x1, y1, x2, y2, widgetScale }. The common placement for this
-- widget is "top center", directly over Top Bar, and with the FlowUI-
-- skinned background (/ecographbarui, widget._barSkinUi) that background
-- comes from WG.FlowUI.Draw.Element's own theme opacity rather than
-- cfg.bgColor, so Top Bar's resource bars/wind icon can still show
-- through underneath. Declared as a bare global function (not a new
-- chunk-level local) since this file sits at Lua 5.1's 200-local-per-
-- chunk ceiling -- same convention as DrawPanelStats above.
--
-- Round 21 fix: WG['topbar'] alone is NOT a reliable "is Top Bar on"
-- signal -- confirmed via /ecographtopbardebug that in at least one
-- real setup, disabling/removing Top Bar left WG['topbar'] populated
-- with its last-known rect (nothing drawn, but the table and
-- GetPosition() both stuck around), which made this darken everywhere
-- Eco Graph sat near the top of the screen even with Top Bar fully off.
-- So check the same on/off signal this file's shutdown safety net and
-- /ecographtopbardebug both already read -- Spring.GetConfigInt(
-- "widget_Top Bar", 1) -- and only fall through to the WG['topbar']
-- rect/overlap check when that says Top Bar is on. Defaults to "on" (1)
-- when unset, so this still applies out of the box for players who
-- have never touched Top Bar's own enable state.
--
-- NOTE (2026-10-17): the in-widget "Top Bar ON/OFF" toggle button this
-- comment used to reference has been removed from EcoToggleMenu (see
-- that module, below) -- Top Bar can no longer be disabled from here at
-- all, so "widget_Top Bar" now only ever gets set to 0 by something
-- outside this widget (e.g. BAR's own F11 widget list).
------------------------------------------------------------------------
function GetTopBarOverlap(x1, y1, x2, y2)
    if Spring.GetConfigInt("widget_Top Bar", 1) == 0 then
        return false
    end

    local topbar = WG['topbar']
    if not topbar or not topbar.GetPosition then
        return false
    end

    local tb = topbar.GetPosition()
    if not tb then
        return false
    end

    local tx1, ty1, tx2, ty2 = tb[1], tb[2], tb[3], tb[4]

    -- Standard axis-aligned bounding box overlap test.
    return x1 < tx2 and x2 > tx1 and y1 < ty2 and y2 > ty1
end

-- DRAW OVERLAY (COMPACT MODE)
local function DrawCompactOverlay()

UpdateConverterStats()

    local teamID     = Spring.GetMyTeamID()
    local playerName = GetPlayerNameFromTeam(teamID)
    local faction    = DetectFaction(teamID)  -- currently unused in compact mode

    -- Hoisted up from the title-draw block further down (Round 7,
    -- 2026-10-17) -- /ecographtopbaraddon's Status/Wind positioning (set
    -- in the Wind block right below, which draws BEFORE the title row
    -- for z-ordering) needs the actual rendered width of
    -- "Eco Graph: <name>" to anchor off of, so this has to be computed
    -- before that point rather than down at the title row itself.
    local title = "Eco Graph: "
    local titleFont = titleSize + 8
    local titleW = glGetTextWidth(title) * titleFont

    if widget._cache_playerName ~= playerName then
        widget._cache_playerName = playerName
        widget._cache_shortName = ShortenPlayerName(playerName)
        widget._cache_shortNameW = glGetTextWidth(widget._cache_shortName) * titleFont
    end
    local shortName = widget._cache_shortName
    -- Round 10: no longer adds widget._cache_shortNameW -- the name
    -- moved to its own row underneath the title in addon mode (see
    -- the Title + Player Name block further down), so it no longer
    -- shares the title's row there and doesn't need reserved width
    -- here any more. (shortNameW is still cached above in case a
    -- future round needs it again; just unused by this formula now.)
    local titleEndX = box.x1 + 6 + titleW

    local mCur, _, _, mInc, mExp = spGetTeamResources(teamID, "metal")
    local eCur, _, _, eInc, eExp = spGetTeamResources(teamID, "energy")

    mCur = mCur or 0
    eCur = eCur or 0
    mInc = mInc or 0
    eInc = eInc or 0
    mExp = mExp or 0
    eExp = eExp or 0

    local mNet = mInc - mExp
    local eNet = eInc - eExp

    -- Get storage for advanced states (DEPLETED / OVERFLOWING)
    local _, mStorage = spGetTeamResources(teamID, "metal")
    local _, eStorage = spGetTeamResources(teamID, "energy")

    -- Smoothed status (compact mode)
    local status = GetEcoStatus(
        mNet, eNet,
        mInc, eInc,
        mCur, eCur,
        mStorage, eStorage
    )

    ------------------------------------------------------------------------
    -- Round 10: Status/Wind's X, hoisted and computed ONCE here (right
    -- after `status` itself is known) instead of being recomputed twice
    -- further down -- the Wind block and the Status block each used to
    -- keep their own separate copy of this formula in sync by hand every
    -- round (Round 9 and 9b both had to touch both copies). They just
    -- read the single statusCenterX/statusTextWidth computed here now.
    --
    -- /ecographtopbaraddon only: also clamped against the energy-to-metal
    -- bracket's own left edge now, not just the title's right edge --
    -- the user's screenshot showed "Status: OVERFLOWING" colliding with
    -- the bracket on the RIGHT at small panel widths. The bracket's own
    -- reserved width is built from fixed max-length placeholder strings
    -- (like "-99.9ke", not the live numbers), so it does not shrink as
    -- the panel narrows the way the open gap between the title and the
    -- bracket does -- hence computing that same width here too, ahead
    -- of the bracket's own draw block further down (same formula).
    local statusTextWidth = glGetTextWidth("Status: " .. status) * (fontSize + 4 * FONT_SCALE)
    local bracketPauseSize = 14 * FONT_SCALE
    local bracketReservedW = glGetTextWidth("[") * bracketPauseSize * 0.9 * 2
        + glGetTextWidth("-99.9ke") * bracketPauseSize
        + glGetTextWidth("+99.9km") * bracketPauseSize
        + glGetTextWidth("100%") * bracketPauseSize
    local bracketLeftX = box.x2 - 10 - bracketReservedW
    local statusCenterX
    if widget._topAddonMode then
        -- The player name now draws on its OWN row underneath the title
        -- in addon mode (Round 10), on the same row Wind/Status share --
        -- so the real left-hand obstacle for THIS row is whichever is
        -- wider: the title text above it, or the name text beside it.
        -- Using titleEndX alone here would let a long player name poke
        -- into Wind's own left edge even though Status (on the title's
        -- own row) stayed clear of the title.
        local nameEndX = box.x1 + 6 + (widget._cache_shortNameW or 0)
        local clearLeftX = math.max(titleEndX, nameEndX)
        local leftBound = clearLeftX + statusTextWidth * 0.5 + 4
        local rightBound = bracketLeftX - statusTextWidth * 0.5 - 4
        if leftBound <= rightBound then
            -- Plenty of room: center in the open gap, but never let the
            -- left edge pass the title/name or the right edge pass the bracket.
            statusCenterX = math.max((clearLeftX + bracketLeftX) * 0.5, leftBound)
            statusCenterX = math.min(statusCenterX, rightBound)
        else
            -- Not enough room to clear both sides at once (the panel's
            -- squeezed narrower than the status text itself) -- split
            -- the unavoidable overlap evenly instead of letting one
            -- side (usually the bracket) absorb all of it.
            statusCenterX = (leftBound + rightBound) * 0.5
        end
    else
        statusCenterX = (box.x1 + box.x2) * 0.5 + 35
    end

    local compactBgCol = widget._transparentMode and cfg.bgColorTransparent or cfg.bgColor

    if widget._barSkinUi and not widget._transparentMode and WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
        -- FlowUI's own theme opacity (not cfg.bgColor) governs this skin's
        -- background, and it's translucent enough that Top Bar still shows
        -- through when this panel sits on top of it (the common "top
        -- center" placement). Since Top Bar draws at layer -999999
        -- (essentially first/furthest back) and this widget draws after
        -- it, an opaque rect here hides Top Bar wherever this panel
        -- covers it -- no need to touch Top Bar's own file or its locked
        -- enable/disable switch at all.
        --
        -- Round 23: draw that opaque backing FIRST, BEHIND FlowUI's own
        -- panel, not on top of it. Round 22 drew it on top (after
        -- WG.FlowUI.Draw.Element), which hid Top Bar but also blotted out
        -- FlowUI's own gradient/texture with flat black -- per the user,
        -- that "basically looking like the original" lost the whole point
        -- of the Top Bar-style skin (matching BAR's own UI look). Drawing
        -- it first means FlowUI's translucent panel still renders visibly
        -- on top of it afterward, same as always -- it's just opaque
        -- black underneath instead of Top Bar.
        if GetTopBarOverlap(box.x1, box.y1, box.x2, box.y2) then
            -- Round 27: switched from fully opaque to genuinely
            -- translucent, per the user's explicit choice -- Round 26's
            -- color fix (warm brown over gray) still read "the same dark
            -- as before" because alpha was still 1 the whole time; color
            -- alone couldn't get it looking as light/airy as the natural
            -- uncovered panel. Asked the user directly whether they'd
            -- rather keep Top Bar 100% hidden (lighter color, still
            -- opaque) or accept real alpha transparency closer to the
            -- natural look -- they chose transparency. This WILL let a
            -- faint hint of Top Bar show through again in bright areas
            -- (that's the explicit tradeoff), unlike every round from 21
            -- through 26 which guaranteed zero bleed-through.
            --
            -- Round 28: nudged up a bit per the user (0.5 let resource
            -- numbers like "1000" show through too clearly) -- still
            -- meaningfully translucent, just a bit less bleed-through.
            --
            -- Round 29: user iterated locally in their own editor and
            -- landed on 0.80 as the final opacity -- "keep it this way."
            -- Round 31: user bumped opacity to 0.90 themselves and asked
            -- for an even lighter color on top of that. Same hue ratio,
            -- brighter again.
            -- Round 32: user said "when over top bar darken it again" --
            -- stepped the color back down (opacity stays at 0.90).
            glColor(0.30, 0.25, 0.19, 0.90)
            glRect(box.x1, box.y1, box.x2, box.y2)
        end

        glColor(1, 1, 1, 1)
        WG.FlowUI.Draw.Element(box.x1, box.y1, box.x2, box.y2, 0, 0, 1, 1, nil, nil, nil, nil, nil, nil, nil, nil)
    elseif widget._barSkin and not widget._transparentMode then
        glBeginEnd(GL.TRIANGLE_FAN, widget._barSkinPanelVerts, box.x1, box.y1, box.x2, box.y2, 10,
            0.22, 0.07, 0.05, compactBgCol[4],
            0.04, 0.02, 0.02, compactBgCol[4])

        glColor(0.55, 0.32, 0.16, 0.75)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, widget._barSkinBorderVerts, box.x1, box.y1, box.x2, box.y2, 10)
    else
        glColor(compactBgCol)
        glRect(box.x1, box.y1, box.x2, box.y2)

        glColor(cfg.borderColor)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, widget._rectBorderVerts, box.x1, box.y1, box.x2, box.y2)
    end

    ----------------------------------------------------------------
    -- WIND BACKPLATE (moved here so it draws BEHIND the window)
    ----------------------------------------------------------------

    -- RAW ENGINE WIND (needed for bar geometry)
    local _, _, _, curWind = Spring.GetWind()
    local minW = Game.windMin or 0
    local maxW = Game.windMax or 1
    curWind = math.min(maxW, math.max(minW, curWind))
    local frac = math.max(0, math.min(1, curWind / maxW))

    -- Position Wind directly under Status
    local textY = box.y2 - 40
    local barY  = textY - 20

    -- X anchor (centered) -- /ecographtopbaraddon anchors off the actual
    -- end of "Eco Graph: <name>" instead of the full panel's center,
    -- so Status/Wind don't leave a big gap on their left where the
    -- hidden sections used to be.
    local centerX = (box.x1 + box.x2) * 0.5
    -- Round 10: statusCenterX/statusTextWidth are now computed ONCE,
    -- right after `status` itself is known -- see the hoisted comment
    -- near the top of this function. This just reuses that single
    -- value instead of keeping its own separate copy in sync by hand.

    -- BAR GEOMETRY
    local barW = 190
    local barH = 12
    local barX = statusCenterX - barW * 0.5

    -- BACKPLATE GEOMETRY
    local bgPad = 5
    local bevel = 8
    local bx1 = barX - bgPad
    local bx2 = barX + barW + bgPad
    local by1 = barY - bgPad + 3
    local by2 = barY + barH + bgPad + 3

    -- extend slanted sides all the way down
    -- local midY = by2
    local midY = (by1 + by2) * 0.5


    if widget._barSkinUi and not widget._transparentMode and WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
        -- /ecographbarui only: no separate backplate rect at all here --
        -- Metal/Energy don't have one either. The off-color tint behind
        -- the bar is drawn directly at the bar's own size, further down
        -- where the fill itself is drawn (see the inner-bar-background
        -- block below), instead of this separate, differently-sized
        -- outer rect.
    elseif widget._barSkin and not widget._transparentMode then
        -- Round 10's chamfer skin, scaled down to this smaller backplate
        -- (6px chamfer vs. the main panel's 10px), same gradient/border
        -- colors as the main panel for visual consistency.
        glBeginEnd(GL.TRIANGLE_FAN, widget._barSkinPanelVerts, bx1, by1, bx2, by2, 6,
            0.22, 0.07, 0.05, compactBgCol[4],
            0.04, 0.02, 0.02, compactBgCol[4])

        glColor(0.55, 0.32, 0.16, 0.75)
        glLineWidth(1.3)
        glBeginEnd(GL_LINES, widget._barSkinBorderVerts, bx1, by1, bx2, by2, 6)
    else
        -- BACKPLATE FILL
        glColor(0, 0, 0, compactBgCol[4])
        glBeginEnd(GL.TRIANGLE_FAN, widget._windBackplateFillVerts, bx1, bevel, by1, bx2, midY)

        -- BACKPLATE BORDER
        glColor(cfg.borderColor)
        glLineWidth(1.3)
        glBeginEnd(GL.LINE_STRIP, widget._windBackplateBorderVerts, bx1, midY, bevel, by1, bx2)
    end

    
-- Title + Player Name (single row, Compact View)
glColor(cfg.titleColor)

-- Draw "Eco Graph: " (title/titleFont/titleW/shortName are hoisted
-- above, near the top of this function -- see the Round 7 comment
-- there)
glText(title, box.x1 + 6, box.y2 - 20, titleFont, "o")

-- Draw player name: same row as the title in normal mode; its own
-- row underneath in addon mode (Round 10, per the user's own ask) --
-- same Y as the Wind text row, whose left-hand gutter is otherwise
-- empty there since Wind/Status center well to the right of the
-- title (see the hoisted statusCenterX comment above).
local teamID = viewedTeamID or Spring.GetMyTeamID()
local r, g, b = Spring.GetTeamColor(teamID)
glColor(r, g, b, 1)

local nameX = widget._topAddonMode and (box.x1 + 6) or (box.x1 + 6 + titleW)
local nameY = widget._topAddonMode and (box.y2 - 40) or (box.y2 - 20)
glText(shortName, nameX, nameY, titleFont, "o")

-- METAL / ENERGY STATS (match Full Mode layout)
local teamID = Spring.GetMyTeamID()
local mid = (box.x1 + box.x2) * 0.5

local metalStatsX  = (box.x1 + mid) * 0.5
local energyStatsX = (mid + box.x2) * 0.5

local statsY = box.y2 - 20

if widget._detachedVisible then
    -- Redundant with the detached dual-line window's own stats row --
    -- skip entirely (not just visually) so no string/width work or
    -- rect updates happen here while the detached window is showing
    -- the same Use/Income/Net numbers. Clear the hitboxes too so a
    -- stale hover tooltip doesn't linger where this text used to be.
    metalIncRect = nil
    energyIncRect = nil
else
    -- Metal stats
    local mInc = smoothMetalIncome or 0
    local mUse = smoothMetalUsage or 0

    DrawPanelStats(
        "Metal",
        mInc,
        mUse,
        metalStatsX,
        statsY,
        cfg.metalIncomeColor,
        cfg.metalUsageColor
    )

    -- Energy stats
    local eInc = smoothEnergyIncome or 0
    local eUse = smoothEnergyUsage or 0

    DrawPanelStats(
        "Energy",
        eInc,
        eUse,
        energyStatsX,
        statsY,
        cfg.energyIncomeColor,
        cfg.energyUsageColor
    )
end

    local centerX = (box.x1 + box.x2) * 0.5
    -- Round 10: same hoisted-value reuse as the Wind block above --
    -- see that comment and the hoisted comment near the top of this
    -- function.

    -- Status color (compact mode)
    local col = statusColors[status] or {1,1,1,1}
    glColor(col)
    -- status only changes after GetEcoStatus()'s own hold-timer settles,
    -- so it's stable across many frames -- cache the formatted string
    -- once per status change and reuse it for both the display line and
    -- the tooltip measurement below instead of rebuilding it twice a frame.
    if widget._cache_status ~= status then
        widget._cache_status = status
        widget._cache_statusText = "Status: " .. status
    end
    glText(widget._cache_statusText,
        statusCenterX, box.y2 - 20, (fontSize + 4 * FONT_SCALE), "oc")

-- STATUS TOOLTIP (hover area is exactly the "Status: ..." text itself --
-- per the user's own ask, no padding/expansion, and specifically no
-- reach up into the wind stats/bar above it. Previously this expanded
-- upward by 55px to deliberately cover the wind text + wind bar, then
-- grew the whole box by another 50% -- removed both so hovering the
-- wind status/bar no longer triggers this tooltip at all.)
local statusText = widget._cache_statusText
local fontH = (fontSize + 4 * FONT_SCALE)

-- Measure text width
local textWidth = gl.GetTextWidth(statusText) * fontH

-- Text is centered ("oc"), so offset left by half width
local sx = statusCenterX - (textWidth * 0.5)
local sy = box.y2 - 20

-- Hover box is exactly the text's own bounding box.
--
-- glText(..., "o") anchors the BASELINE at the given y, with the glyphs
-- drawn upward from there (same convention as every other "o"/"oc" call
-- in this file, e.g. the button labels at `by1 + 6`) -- not downward.
-- Round 18 had this backwards: it put most of the box (0.8*fontH) BELOW
-- the baseline, reaching down into the wind stats/bar beneath the status
-- line, and only a sliver (0.2*fontH) above it, which is why only the
-- very bottom of the "Status: ..." glyphs registered and the box still
-- reached the wind row. Flipped so the box extends mostly upward
-- (ascent) from the baseline and only slightly downward (descent).
local x1 = sx
local x2 = sx + textWidth
local y1 = sy - fontH * 0.2
local y2 = sy + fontH * 0.8

local mx, my = Spring.GetMouseState()

if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
    local tip = statusTooltips[status]
    if tip then
        -- Tooltip box size
        local pad = 6
        local lines = {}

        -- Preserve blank lines
        for line in tip:gmatch("([^\n]*)\n?") do
            if line == "" then
                lines[#lines+1] = " "
            else
                lines[#lines+1] = line
            end
        end

        local maxWidth = 0
        for _, line in ipairs(lines) do
            local w = gl.GetTextWidth(line) * fontSize
            if w > maxWidth then maxWidth = w end
        end

        local tw = maxWidth + pad * 4
        local th = (#lines * (fontSize + 4)) + pad * 3

        -- Tooltip position
        local tipX = mx + 18
        local tipY = my + 18
        if tipY + th > vsy - 4 then
            tipY = my - th - 18
        end

        ----------------------------------------------------------------
        -- FOREGROUND TOOLTIP HANDOFF
        ----------------------------------------------------------------
        pendingTooltip = {
            lines = lines,
            tw = tw,
            th = th,
            pad = pad,
        }
        pendingTooltipX = tipX
        pendingTooltipY = tipY
    end
end


-- COMMANDERS ONLY (same column, resize‑safe)
if not widget._topAddonMode then
    local c1, c2 = commanderC1, commanderC2

    -- X anchor for BOTH the label and the numbers
    -- local commandersX = metalStatsX + 105
	local commandersX = (metalStatsX + centerX) * 0.5 + 3

    -- Y positions
    local commandersLabelY = statsY
    local countY = commandersLabelY   -- same line as label

    local baseX = commandersX + 80   -- Increases horizontal spacing from label, but numbers are still centered around commandersX

    -- Horizontal spacing for the numbers
    local offset = 18

    -- Persistent color tables instead of a fresh {r,g,b,a} table literal
    -- every frame -- the colors never change, only the table used to
    -- hold them kept getting reallocated.
    widget._commanderColdColor = widget._commanderColdColor or {0.2, 1.0, 0.2, 1.0}
    widget._commanderWarmColor = widget._commanderWarmColor or {1.0, 0.35, 0.2, 1.0}
    local coldColor = widget._commanderColdColor
    local warmColor = widget._commanderWarmColor

    -- Label
    glColor(cfg.titleColor)
    glText("Commanders:   ", commandersX, commandersLabelY, fontSize + 3, "oc")
	

    -- Numbers (same column, centered around commandersX). commanderC1/C2
    -- only update every 15 game frames, so cache the formatted digit
    -- strings instead of rebuilding them every render frame.
    if widget._cache_c1 ~= c1 then
        widget._cache_c1 = c1
        widget._cache_c1Str = string.format("%d", c1)
    end
    if widget._cache_c2 ~= c2 then
        widget._cache_c2 = c2
        widget._cache_c2Str = string.format("%d", c2)
    end

    glColor(coldColor)
    glText(widget._cache_c1Str, baseX - offset, countY, (fontSize + 7 * FONT_SCALE), "oc")

    glColor(1, 1, 1, 1)
    glText("vs", baseX, countY, fontSize, "oc")

    glColor(warmColor)
    glText(widget._cache_c2Str, baseX + offset, countY, (fontSize + 7 * FONT_SCALE), "oc")

end

-- WIND METER (simple two‑line version)

-- RAW ENGINE WIND (matches Top Bar exactly)
local _, _, _, curWind = Spring.GetWind()

-- ENGINE WIND LIMITS
local minW    = Game.windMin or 0
local maxW    = Game.windMax or 1

-- EXACT BAR AVERAGE (matches Top Bar)
local avgWindLookup = windFunctions.averageWindLookup
local avgWind = avgWindLookup[minW] and avgWindLookup[minW][maxW]

-- fallback if lookup missing
if not avgWind then
    avgWind = minW + (maxW - minW) * 0.7
end

-- Clamp current wind to map range (Top Bar does not clamp, but prevents negatives)
curWind = math.min(maxW, math.max(minW, curWind))

-- FRACTION FOR BAR FILL
local frac = math.max(0, math.min(1, curWind / maxW))

-- Position Wind directly under Status
local textY = box.y2 - 40
local barY  = textY - 20

-- X anchor (centered)
local centerX = (box.x1 + box.x2) * 0.5

-- TEXT LINE (Range uses whole numbers)
local textWind = string.format(
    "Wind: Avg %.1f   Cur %.1f   Range: %d–%d",
    avgWind, curWind,
    math.floor(minW + 0.5), math.floor(maxW + 0.5)
)

-- Draw text (Cur color-coded)
local beforeCur = string.format("Wind: Avg %.1f   ", avgWind)
local beforeCurW = glGetTextWidth(beforeCur) * fontSize

local curStr = string.format("Cur %.1f", curWind)
local curW   = glGetTextWidth(curStr) * fontSize

-- Draw entire line in white first
glColor(cfg.titleColor)
-- Round 11 (2026-10-18): this used to redeclare its OWN local
-- statusCenterX (= centerX + 35, a plain full-panel-center anchor
-- that never changed with addon mode, the title, or the bracket) --
-- a completely separate, never-updated position from the hoisted
-- statusCenterX the Status text itself draws at (see the hoisted
-- comment near the top of this function). That mismatch is why
-- Status and the Wind text/bar visibly didn't share a center: two
-- different formulas, one of them frozen since before Round 7 ever
-- existed. Removed the redeclaration so this just falls through to
-- the same single hoisted value Status uses -- same centering, same
-- clamp, always aligned.
glText(textWind, statusCenterX, textY, fontSize, "oc")

-- Overdraw Cur with color
local curX = statusCenterX - (glGetTextWidth(textWind) * fontSize) * 0.5 + beforeCurW + curW * 0.5


if frac <= 0.40 then
    glColor(1, 0, 0, 1)
elseif frac <= 0.75 then
    glColor(1, 1, 0, 1)
else
    glColor(0, 1, 0, 1)
end

glText(curStr, curX, textY, fontSize, "oc")

-- BAR (full width under text)
local barW = 190
local barH = 12
local barX = statusCenterX - barW * 0.5

--- here is the place for the slandted backplate

-- inner bar background
-- /ecographbarui: match Metal/Energy's own storage-bar background
-- exactly -- a single rect at the bar's own full size (no inset) tinted
-- with a dim, off-color version of the bar's own fill hue, instead of a
-- separate padded black box. Every other skin keeps the original black
-- 0.65 inset box unchanged.
local useWindBarTint = widget._barSkinUi and not widget._transparentMode and WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element
local innerPadX = useWindBarTint and 0 or 6
local innerPadY = useWindBarTint and 0 or 1
local innerX1 = barX + innerPadX
local innerX2 = barX + barW - innerPadX
local innerY1 = barY + innerPadY
local innerY2 = barY + barH - innerPadY

if useWindBarTint then
    glColor(0.6, 0.8, 1.0, 0.20)
else
    -- Follows the Default/Transparent toggle, same as the graph panels and
    -- window backdrop -- this was a flat 0.65 regardless of mode, which is
    -- why it stayed dark after everything else went transparent.
    glColor(0, 0, 0, widget._transparentMode and 0 or 0.65)
end
glRect(innerX1, innerY1, innerX2, innerY2)

-- FILL (bug fix, 2026-10-18): this was lost somewhere during the
-- inner-bar-background restyle above (whichever round switched this
-- box from a flat black backdrop to the tint-aware one) -- only the
-- empty backdrop box was ever drawn after that, never the actual
-- wind-level fill or the current-wind tick, which is why the bar
-- looked like it "stopped working" (a static, unchanging empty box).
-- Same fill/tick treatment as the Full Mode wind bar earlier in this
-- file, just sized to this bar's own (possibly inset) inner box
-- instead of introducing new locals this close to this function's own
-- 200-local ceiling (see Round 7's note on that).
if frac > 0 then
    glColor(0.3, 0.6, 1.0, 0.90)
    glRect(innerX1, innerY1, innerX1 + (innerX2 - innerX1) * frac, innerY2)
end

if curWind > 0 then
    glColor(1, 1, 1, 1)
    glRect(innerX1 + (innerX2 - innerX1) * frac - 1, innerY1 - 2, innerX1 + (innerX2 - innerX1) * frac + 1, innerY2 + 2)
end

-- TIDAL ONLY (Compact View — single line)
if not widget._topAddonMode then
    local tidal = Game.tidal or 0

    -- X anchor centered between Status and Energy Inc
    local tidalX = (centerX + energyStatsX) * 0.5 + 15

    -- Same Y as Energy Inc (top row)
    local tidalY = statsY

    -- Game.tidal is a fixed per-map constant -- never changes mid-match --
    -- so the formatted string only needs to be built once, not every frame.
    if widget._cache_tidal ~= tidal then
        widget._cache_tidal = tidal
        widget._cache_tidalText = string.format("Tidal: %.1f", tidal)
    end

    glColor(1, 1, 1, 1)
    glText(widget._cache_tidalText, tidalX, tidalY, fontSize, "oc")
end

			
-- METAL INCOME/USAGE GRAPH (Compact Mode, full auto-scaling)
-- Fully skipped (data scan, background, zero line, curves) when
-- hideGraphs is true -- previously only the curves themselves were
-- gated, while the scan/background/zero-line ran every frame regardless.
if not widget._topAddonMode then
if not hideGraphs then

    local data = history.metal
    if #data < 2 then return end

    -- Compute center
    local centerX = box.x1 + (box.x2 - box.x1) * 0.5

    -- AUTO-SCALING GEOMETRY (Option A + full vertical stretch)

    -- Horizontal: 3% outer margin, 1% center gap
    local gx1 = box.x1 + (box.x2 - box.x1) * 0.03
	-- Moves right side of metal dual line to the left
    local gx2 = centerX - (box.x2 - box.x1) * 0.07

    -- Vertical: stretch from top of storage bar to just below Net: line
    local storageBarTop = box.y1 + 28      -- was + 30 (Round 16: +10 for bottom-row spacing)
    local graphTopLimit = box.y2 - 22   -- leave 60px buffer below Net: line. Top ceiling of the Metal Dual Graph

    local gy1 = storageBarTop
    local gy2 = graphTopLimit

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1


    -- BACKGROUND
    -- Follows the main window's own Default/Transparent toggle (0.25
    -- default, 0 transparent) instead of the fixed value this always
    -- used to be -- was the one panel left behind as a flat black box
    -- even with everything else in the window gone transparent.
    glColor(0, 0, 0, widget._transparentMode and 0 or 0.25)
    glRect(gx1, gy1, gx2, gy2)


    -- SCALE VALUES (same as Full View)
    local maxT = data[#data].t
    local minT = maxT - cfg.historySeconds

    local minV, maxV = math.huge, -math.huge
    for i = 1, #data do
        local s = data[i]
        if s.income < minV then minV = s.income end
        if s.usage  < minV then minV = s.usage  end
        if s.income > maxV then maxV = s.income end
        if s.usage  > maxV then maxV = s.usage  end
    end

    if minV == maxV then
        maxV = maxV + 1
        minV = minV - 1
    end

    local padding = (maxV - minV) * cfg.yPaddingFraction
    minV = minV - padding
    maxV = maxV + padding

    local rangeV = maxV - minV
    local rangeT = cfg.historySeconds

    -- ZERO LINE
    local zeroY = gy1 + gh * ((0 - minV) / rangeV)
    glColor(cfg.gridColor)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, widget._zeroLineVerts, gx1, zeroY, gx2)

    -- INCOME CURVE
    glColor(cfg.metalIncomeColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, true)

    -- USAGE CURVE
    glColor(cfg.metalUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, false)

    -- EXPOSE BOTTOM FOR STORAGE BAR
    compactGraphBottom = gy1
end
end

-- HISTORY SECONDS SELECTOR (Compact Mode, right side)
-- Changed 'do' to 'if not hideGraphs then'
if not hideGraphs and not widget._topAddonMode then 
    local hx1 = centerX + 220
    local hx2 = box.x2 - 10
    local hy1 = box.y1 + 30
    local hy2 = hy1 + 20

    -- Background
    -- Follows the main window's own Default/Transparent toggle -- see
    -- the matching comment on the Metal graph's background above.
    glColor(0, 0, 0, widget._transparentMode and 0 or 0.25)
    glRect(hx1, hy1, hx2, hy2)

    -- Options
    local opts = cfg.historyOptions  -- {20,30,40,50,60}
    local count = #opts
    local w = (hx2 - hx1) / count

    -- cfg.historyOptions never changes at runtime, so the "Ns" labels are
    -- built once per option value and cached, instead of concatenating a
    -- fresh string for each of the 5 options every single frame.
    widget._historyLabels = widget._historyLabels or {}

    for i = 1, count do
        local x1 = hx1 + (i-1)*w
        local x2 = x1 + w
        local sec = opts[i]

        -- Highlight selected
        if sec == cfg.historySeconds then
            glColor(1,1,1,0.15)
            glRect(x1, hy1, x2, hy2)
        end

        local label = widget._historyLabels[sec]
        if not label then
            label = sec.."s"
            widget._historyLabels[sec] = label
        end

        -- Text
        glColor(1,1,1,1)
        glText(label, x1 + w*0.5, hy1 + 3, 11, "oc")
    end
end -- End of the if not hideGraphs check

-- ENERGY INCOME/USAGE GRAPH (Compact Mode, full auto-scaling)
-- Fully skipped (data scan, background, zero line, curves) when
-- hideGraphs is true -- see the matching comment on the Metal graph above.
if not widget._topAddonMode then
if not hideGraphs then

    local data = history.energy
    if #data < 2 then return end

    -- Compute center
    local centerX = box.x1 + (box.x2 - box.x1) * 0.5

    
    -- AUTO-SCALING GEOMETRY (Option A + full vertical stretch)
    -- Horizontal: 1% gap from center, 3% margin from right
    local gx1 = centerX + (box.x2 - box.x1) * 0.12
    local gx2 = box.x2 - (box.x2 - box.x1) * 0.03

    -- Vertical: stretch from top of storage bar to just below Net: line
    local storageBarTop = box.y1 + 40  -- Round 16: +10 for bottom-row spacing
    local graphTopLimit = box.y2 - 24   -- buffer below Net: line  Top ceiling for the Energy dual graph

    local gy1 = storageBarTop
    local gy2 = graphTopLimit

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1


    -- BACKGROUND
    -- Follows the main window's own Default/Transparent toggle -- see
    -- the matching comment on the Metal graph's background above.
    glColor(0, 0, 0, widget._transparentMode and 0 or 0.25)
    glRect(gx1, gy1, gx2, gy2)

    -- SCALE VALUES (same as Full View)
    local maxT = data[#data].t
    local minT = maxT - cfg.historySeconds

    local minV, maxV = math.huge, -math.huge
    for i = 1, #data do
        local s = data[i]
        if s.income < minV then minV = s.income end
        if s.usage  < minV then minV = s.usage  end
        if s.income > maxV then maxV = s.income end
        if s.usage  > maxV then maxV = s.usage  end
    end

    if minV == maxV then
        maxV = maxV + 1
        minV = minV - 1
    end

    local padding = (maxV - minV) * cfg.yPaddingFraction
    minV = minV - padding
    maxV = maxV + padding

    local rangeV = maxV - minV
    local rangeT = cfg.historySeconds

    -- ZERO LINE
    local zeroY = gy1 + gh * ((0 - minV) / rangeV)
    glColor(cfg.gridColor)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, widget._zeroLineVerts, gx1, zeroY, gx2)

    -- INCOME CURVE
    glColor(cfg.energyIncomeColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, true)

    -- USAGE CURVE
    glColor(cfg.energyUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, false)

    -- EXPOSE BOTTOM FOR FUTURE ELEMENTS
    compactEnergyGraphBottom = gy1
end
end

-- METAL STORAGE BAR (Compact Mode, bottom-anchored, layered)
if not widget._topAddonMode then
    -- This controls left and right length of bar nudge left or right
	local barX1 = box.x1 + 170 + metalOffset  -- Moves left side of metal storage bar to the right
    local barX2 = centerX - 270 + metalOffset
    local barH  = 12
	-- Nudge the Storage bar up or down.
    local barY1 = box.y1 + 15  -- Round 16: +10 for bottom-row spacing
    local barY2 = barY1 + barH

    -- Values
    local cur   = mCur or 0
    local max   = mStorage or 1
    local share = metalShare or 0

    -- Background bar (dark base)
    -- glColor(0, 0, 0, 0.35)
	glColor(0, 1, 1, 0.20)
    glRect(barX1, barY1, barX2, barY2)

-- Fill overlay (two-tone sheen for Metal)
local fillX = barX1 + (cur / max) * (barX2 - barX1)

-- Bottom half (base metal color)
glColor(cfg.metalIncomeColor[1], cfg.metalIncomeColor[2], cfg.metalIncomeColor[3], 0.90)
glRect(barX1, barY1, fillX, barY1 + (barH * 0.5))

-- Top half (lighter sheen)
local shine = 0.12  -- adjust for more/less highlight
glColor(
    math.min(1, cfg.metalIncomeColor[1] + shine),
    math.min(1, cfg.metalIncomeColor[2] + shine),
    math.min(1, cfg.metalIncomeColor[3] + shine),
    0.95
)
glRect(barX1, barY1 + (barH * 0.5), fillX, barY2)


    -- White tick (current)
    glColor(1, 1, 1, 1)
	glRect(fillX - 1, barY1 - 2, fillX + 1, barY2 + 2)

------------------------------------------------------------
-- AUTO‑SHARE SLIDER (METAL) — Compact View
------------------------------------------------------------
do
    local res = "metal"

    -- current share value (0–1)
    local value = draggingShareIndicatorValue[res]
    if value == nil then
        local _, _, _, _, _, share = Spring.GetTeamResources(Spring.GetMyTeamID(), res)
        value = share
    end
    if value == nil then
        value = 1   -- engine default: keep 100%
    end

    -- slider geometry (scaled to your compact bar)
    local barWidth = barX2 - barX1
    local sliderHalfWidth = math.max(1, barH * 0.9 - 1)
    local sliderHeightAdd = barH * 1.2

    -- base (normal-size) position of the thumb
    local baseX1 = barX1 + (value * barWidth) - sliderHalfWidth
    local baseX2 = barX1 + (value * barWidth) + sliderHalfWidth
    local baseY1 = barY1 - sliderHeightAdd
    local baseY2 = barY2 + sliderHeightAdd

    local cx = (baseX1 + baseX2) * 0.5
    local cy = (baseY1 + baseY2) * 0.5
    local r  = sliderHalfWidth

    -- HOVER-TO-ENLARGE (grows 50% on hover or while dragging; uses last
    -- frame's stored hitbox so it doesn't flicker while your mouse is
    -- moving inside the grown area)
    local mx, my = spGetMouseState()
    local prev = shareIndicatorArea[res]
    local hovering = prev and prev[1] and mx >= prev[1] and mx <= prev[3] and my >= prev[2] and my <= prev[4]
    local isDragging = (draggingShareIndicator == res)
    local effR = (hovering or isDragging) and (r * 1.5) or r

    shareIndicatorArea[res] = { cx - effR, cy - effR, cx + effR, cy + effR }

    ------------------------------------------------------------
    -- SHADOW (added, nothing else changed)
    ------------------------------------------------------------
    glColor(0, 0, 0, 0.10)
    glRect(cx - effR - 2, cy - effR - 2, cx + effR + 2, cy + effR + 2)

    glColor(0, 0, 0, 0.18)
    glRect(cx - effR - 1, cy - effR - 1, cx + effR + 1, cy + effR + 1)

    ------------------------------------------------------------
    -- ORIGINAL THUMB (grows 50% on hover/drag, otherwise unchanged)
    ------------------------------------------------------------
    glColor(1, 0.2, 0.2, 1)
    glRect(cx - effR, cy - effR, cx + effR, cy + effR)

    -- GRIP NOTCHES (3 thin vertical lines = "drag me" cue)
    glColor(0, 0, 0, 0.45)
    local notchW   = math.max(1, effR * 0.16)
    local notchGap = effR * 0.42
    local notchH   = effR * 1.1
    for i = -1, 1 do
        local nx = cx + i * notchGap
        glRect(nx - notchW * 0.5, cy - notchH * 0.5, nx + notchW * 0.5, cy + notchH * 0.5)
    end
end

-- Storage total (aligned with PP: No)
glColor(1, 1, 1, 1)
-- Storage capacity only changes when a storage building finishes/dies,
-- not every frame -- cache the formatted string on that value.
if widget._cache_metalStorage ~= max then
    widget._cache_metalStorage = max
    widget._cache_metalStorageText = string.format("[%.1fK]", max/1000)
end
local text = widget._cache_metalStorageText

local textY = box.y1 + 18   -- EXACT same Y as PP: No (Round 16: +10 for bottom-row spacing)
glText(text, barX2 + 65, textY, fontSize, "or")   -- + 60  This moves the Metal Storage total stat. Higher goes right

end
-- ENERGY STORAGE BAR (Compact Mode, bottom‑anchored, mirrored)
if not widget._topAddonMode then
    
    -- Values
    local cur   = eCur or 0
    local max   = eStorage or 1
    local frac  = math.max(0, math.min(1, cur / max))

    --------------------------------------------------------
    -- GEOMETRY (mirrored from Metal side)
    --------------------------------------------------------
    local barX1 = centerX + 265 + energyOffset
    local barX2 = box.x2 - 150 + energyOffset

    local barH  = 12
    local barY1 = box.y1 + 15  -- Round 16: +10 for bottom-row spacing
    local barY2 = barY1 + barH

    -- BAR BACKGROUND
    glColor(1, 1, 0, 0.20)
    glRect(barX1, barY1, barX2, barY2)

    -- BAR FILL
    local fillX = barX1 + frac * (barX2 - barX1)
    if frac > 0 then
        glColor(1, 1, 0, 0.90)
        glRect(barX1, barY1, fillX, barY2)
    end

    -- WHITE TICK
    if frac > 0 then
        glColor(1, 1, 1, 1)
        glRect(fillX - 1, barY1 - 2, fillX + 1, barY2 + 2)
    end

    ------------------------------------------------------------
    -- ENERGY → METAL CONVERSION SLIDER (Compact View)
    ------------------------------------------------------------
    do
        local mm = draggingConversionIndicatorValue
        if mm == nil then
            mm = (Spring.GetTeamRulesParam(Spring.GetMyTeamID(), "mmLevel") or 1)
        end

        local barWidth = barX2 - barX1
        local sliderHalfWidth = math.max(1, barH * 0.9 - 1)
        local sliderHeightAdd = barH * 1.2

        local convX = barX1 + (mm * barWidth)

        local baseX1 = convX - sliderHalfWidth
        local baseX2 = convX + sliderHalfWidth
        local baseY1 = barY1 - sliderHeightAdd
        local baseY2 = barY2 + sliderHeightAdd

        local cx = (baseX1 + baseX2) * 0.5
        local cy = (baseY1 + baseY2) * 0.5
        local r  = sliderHalfWidth

        -- HOVER-TO-ENLARGE (grows 50% on hover or while dragging)
        local mx, my = spGetMouseState()
        local prev = conversionIndicatorArea
        local hovering = prev and prev[1] and mx >= prev[1] and mx <= prev[3] and my >= prev[2] and my <= prev[4]
        local effR = (hovering or draggingConversionIndicator) and (r * 1.5) or r

        conversionIndicatorArea = { cx - effR, cy - effR, cx + effR, cy + effR }

        glColor(0, 0, 0, 0.10)
        glRect(cx - effR - 2, cy - effR - 2, cx + effR + 2, cy + effR + 2)

        glColor(0, 0, 0, 0.18)
        glRect(cx - effR - 1, cy - effR - 1, cx + effR + 1, cy + effR + 1)

        glColor(0.95, 0.95, 0.7, 1)
        glRect(cx - effR, cy - effR, cx + effR, cy + effR)

        -- GRIP NOTCHES (3 thin vertical lines = "drag me" cue)
        glColor(0, 0, 0, 0.45)
        local notchW   = math.max(1, effR * 0.16)
        local notchGap = effR * 0.42
        local notchH   = effR * 1.1
        for i = -1, 1 do
            local nx = cx + i * notchGap
            glRect(nx - notchW * 0.5, cy - notchH * 0.5, nx + notchW * 0.5, cy + notchH * 0.5)
        end
    end

    ------------------------------------------------------------
    -- AUTO‑SHARE SLIDER (ENERGY) — Compact View
    ------------------------------------------------------------
    do
        local res = "energy"

        local value = draggingShareIndicatorValue[res]
        if value == nil then
            local _, _, _, _, _, share = Spring.GetTeamResources(Spring.GetMyTeamID(), res)
            value = share
        end
        if value == nil then
            value = 1
        end

        local barWidth = barX2 - barX1
        local sliderHalfWidth = math.max(1, barH * 0.9 - 1)
        local sliderHeightAdd = barH * 1.2

        local baseX1 = barX1 + (value * barWidth) - sliderHalfWidth
        local baseX2 = barX1 + (value * barWidth) + sliderHalfWidth
        local baseY1 = barY1 - sliderHeightAdd
        local baseY2 = barY2 + sliderHeightAdd

        local cx = (baseX1 + baseX2) * 0.5
        local cy = (baseY1 + baseY2) * 0.5
        local r  = sliderHalfWidth

        -- HOVER-TO-ENLARGE (grows 50% on hover or while dragging)
        local mx, my = spGetMouseState()
        local prev = shareIndicatorArea[res]
        local hovering = prev and prev[1] and mx >= prev[1] and mx <= prev[3] and my >= prev[2] and my <= prev[4]
        local isDragging = (draggingShareIndicator == res)
        local effR = (hovering or isDragging) and (r * 1.5) or r

        shareIndicatorArea[res] = { cx - effR, cy - effR, cx + effR, cy + effR }

        glColor(0, 0, 0, 0.10)
        glRect(cx - effR - 2, cy - effR - 2, cx + effR + 2, cy + effR + 2)

        glColor(0, 0, 0, 0.18)
        glRect(cx - effR - 1, cy - effR - 1, cx + effR + 1, cy + effR + 1)

        glColor(1, 0.2, 0.2, 1)
        glRect(cx - effR, cy - effR, cx + effR, cy + effR)

        -- GRIP NOTCHES (3 thin vertical lines = "drag me" cue)
        glColor(0, 0, 0, 0.45)
        local notchW   = math.max(1, effR * 0.16)
        local notchGap = effR * 0.42
        local notchH   = effR * 1.1
        for i = -1, 1 do
            local nx = cx + i * notchGap
            glRect(nx - notchW * 0.5, cy - notchH * 0.5, nx + notchW * 0.5, cy + notchH * 0.5)
        end
    end

    -- STORAGE TOTAL TEXT
    glColor(1, 1, 1, 1)
    -- Storage capacity only changes when a storage building finishes/dies,
    -- not every frame -- cache the formatted string on that value.
    if widget._cache_energyStorage ~= max then
        widget._cache_energyStorage = max
        widget._cache_energyStorageText = string.format("[%.1fK]", max / 1000)
    end
    local text = widget._cache_energyStorageText
    local textY = box.y1 + 18  -- Round 16: +10 for bottom-row spacing
    glText(text, barX2 + 60, textY, fontSize, "or")   -- + 55 original  moving Energy Total Storage Stat left or right. Higher goes right
end

-- BIG METAL AVAILABLE (Compact Mode, Full View style)
if not widget._topAddonMode then
    local myTeamID = Spring.GetMyTeamID()
    if myTeamID then
        local mCur = select(1, Spring.GetTeamResources(myTeamID, "metal")) or 0
    local metalText = "Metal: " .. FormatCompact(mCur)

        -- Full View font size
        local metalFont = (fontSize + 6 * FONT_SCALE)

        -- Full View color (lighter aqua)
        glColor(0.6, 0.9, 1.0, 1.0)

        -- Recompute bar geometry
        local barX1 = box.x1 + 170   -- Match this with the left side of the Metal Storage bar
        local barX2 = centerX - 250
        local barY1 = box.y1 + 15  -- Round 16: +10 for bottom-row spacing

        -- Position: nicely to the right of the storage bar
        local metalTextX = barX2 + 25     -- ← 90 adjust this if needed Metal Available left to right
        local metalTextY = barY1 - 2

        glText(metalText, metalTextX, metalTextY, metalFont, "l")

--[[ ------------------------------------------------------------
-- METAL ICON ABOVE METAL AVAILABLE
------------------------------------------------------------
local iconSize = 38

-- Center icon horizontally over the Metal Available text
local iconX = metalTextX - (iconSize * 0.5) + 45    -- was 60  higher goes right

-- Place icon above the text
local iconY = metalTextY + metalFont + 6 - 15

gl.Texture(metalIconPath)
gl.Color(1,1,1,1)
gl.TexRect(iconX, iconY, iconX + iconSize, iconY + iconSize)
gl.Texture(false) ]]

    end
end

-- BIG ENERGY AVAILABLE (Compact Mode, bottom-aligned)
if not widget._topAddonMode then
    local myTeamID = Spring.GetMyTeamID()
    if myTeamID then
        local eCur = select(1, Spring.GetTeamResources(myTeamID, "energy")) or 0
        local energyText = "Energy: " .. FormatCompact(eCur)

        -- Full View font size
        local energyFont = (fontSize + 6 * FONT_SCALE)

        -- Full View energy color
        glColor(1, 1, 0, 0.90)

        -- Recompute Energy bar geometry (must match your actual bar)
        local barX1 = centerX + 410 -- 390  This is the Energy Available stat just below and right of Wind Bar
        local barX2 = box.x2 - 150
        local barY1 = box.y1 + 15  -- Round 16: +10 for bottom-row spacing

        -- Mirror Metal placement:
        -- Metal uses: barX2 + 90
        -- So Energy uses: barX1 - 90
        local energyTextX = barX1 - 90
        local energyTextY = barY1 - 2

        glText(energyText, energyTextX, energyTextY, energyFont, "r")

    end
end

----------------------------------------------------------------
-- METAL : ENERGY RATIO  (Compact View, next to [Intel])
----------------------------------------------------------------
do
    local mInc = smoothMetalIncome or 0
    local eInc = smoothEnergyIncome or 0

    -- Compute ratio safely
    local ratio = (mInc > 0) and (eInc / mInc) or 0

    -- Clamp
    if ratio < 0 then ratio = 0 end
    if ratio > 999 then ratio = 999 end

    -- Rounded ratio for display
    local ratioRounded = math.floor(ratio + 0.5)

    ------------------------------------------------------------
    -- Position: right of [Intel]
    ------------------------------------------------------------
    local intelX = box.x1 + 8
    -- /ecographtopbaraddon: same bottom-left-corner Y as [Intel]'s own
    -- addon-mode position below, so M:E stays aligned next to it.
    local intelY = widget._topAddonMode and (box.y1 + 12) or (box.y1 + 18)  -- Round 16: +10 for bottom-row spacing; Round 7: addon mode pinned to the bottom corner

    -- VERY TIGHT spacing
    local ratioX = intelX + 50
    local ratioY = intelY

    ------------------------------------------------------------
    -- Color coding -- 4 persistent color tables instead of a fresh
    -- table literal every frame; which one applies still depends on the
    -- live ratio, only the table objects themselves are no longer
    -- reallocated each time.
    ------------------------------------------------------------
    widget._meRatioColorLow    = widget._meRatioColorLow    or {1, 0.2, 0.2, 1}
    widget._meRatioColorLowMid = widget._meRatioColorLowMid or {1, 1, 0.2, 1}
    widget._meRatioColorGood   = widget._meRatioColorGood   or {0.2, 1, 0.2, 1}
    widget._meRatioColorHigh   = widget._meRatioColorHigh   or {0.2, 1, 1, 1}

    local col
    if ratio < 8 then
        col = widget._meRatioColorLow
    elseif ratio < 10 then
        col = widget._meRatioColorLowMid
    elseif ratio <= 40 then
        col = widget._meRatioColorGood
    else
        col = widget._meRatioColorHigh
    end

    ------------------------------------------------------------
    -- Draw bracketed label: [M:E  1:XXX  ] -- cached on the rounded
    -- ratio, the only part of the label that can actually change.
    ------------------------------------------------------------
    if widget._cache_meRatio ~= ratioRounded then
        widget._cache_meRatio = ratioRounded
        widget._cache_meRatioText = string.format("[M:E 1:%d]", ratioRounded)
    end
    local display = widget._cache_meRatioText

    glColor(col)
    glText(display, ratioX, ratioY, fontSize + 2, "l")

    ------------------------------------------------------------
    -- Tooltip hitbox (wide enough for 1:999)
    ------------------------------------------------------------
    local size  = fontSize + 2
    local width = gl.GetTextWidth(display) * size

    meRatioRect = widget._setRect(meRatioRect, ratioX - 4, ratioY - fontSize, ratioX - 4 + width + 8, ratioY + fontSize)
end


----------------------------------------------------------------
-- M:E RATIO TOOLTIP (SMART VERSION, STYLED, LIGHT BG, NET-AWARE)
----------------------------------------------------------------
do
    local mx, my = Spring.GetMouseState()

    -- Tooltip visible if hovered OR pinned
    if meRatioPinned or (
        meRatioRect
        and mx >= meRatioRect.x1 and mx <= meRatioRect.x2
        and my >= meRatioRect.y1 and my <= meRatioRect.y2
    ) then

        local mInc = smoothMetalIncome or 0
        local mUse = smoothMetalUsage or 0
        local mNet = mInc - mUse

        local eInc = smoothEnergyIncome or 0
        local ratio = (mInc > 0) and (eInc / mInc) or 0
        local ratioRounded = math.floor(ratio + 0.5)
        local ratioStr = string.format("1:%d", ratioRounded)

        ------------------------------------------------------------
        -- Metal context (NET-AWARE + styled, hold-based anti-flicker --
        -- see widget._getMetalHint near the top of the file)
        ------------------------------------------------------------
        local metalHint, metalColor, metalIcon = widget._getMetalHint(mNet, mInc)

        ------------------------------------------------------------
        -- Tooltip lines
        ------------------------------------------------------------
        local lines = {
            { text = "Metal to Energy Ratio:", center = true, big = true },
            "",

            string.format("Metal Income:  %.1f", mInc),
            string.format("Metal Use:     %.1f", mUse),
            string.format("Metal Net:     %.1f", mNet),
            "",

            string.format("Energy Income: %.1f", eInc),
            "",

            { text = string.format("RATIO: %s", ratioStr), bigger = true },
            "",
            string.format("Equation: eInc / mInc = %.2f", ratio),
            "",

            { text = metalIcon .. metalHint, color = metalColor, big = true },

            "",
            "Severe Stall: 1:0 – 1:7",
            "Low / Unstable: 1:8 – 1:9",
            "Healthy Baseline: 1:10 – 1:15",
            "Strong Eco: 1:16 – 1:25",
            "High-Power Eco: 1:26 – 1:40",
            "Converter Eco: 1:41 – 1:80",
            "Overbuilt Energy: 1:81 – 1:200",
            "Extreme Surplus: 200+",
            "",
            { text = "Click on [M:E 1:XX] to pin this tooltip for reference.", center = true, small = true, color = {0.35, 0.35, 0.35, 1} }
        }

        ------------------------------------------------------------
        -- Tooltip sizing
        ------------------------------------------------------------
        local pad = 10
        local maxW = 0
        for _, line in ipairs(lines) do
            local text = (type(line) == "table") and line.text or line
            local w = glGetTextWidth(text) * fontSize
            if w > maxW then maxW = w end
        end

        local tw = maxW + pad * 4
        local th = (#lines * (fontSize + 4)) + pad * 3

        ------------------------------------------------------------
        -- FIXED POSITION WHEN PINNED
        ------------------------------------------------------------
        local tipX, tipY

        if meRatioPinned then
            -- Anchor tooltip to the M:E label instead of the mouse
           -- tipX = meRatioRect.x2 + 12
            tipX = meRatioRect.x1 - tw + 20 --This moves the tooltip left or right when pinned. Higher moves right.
            tipY = meRatioRect.y1 - th - 12

            -- If popping downward runs off the bottom of the screen
            -- (widget sitting near the bottom edge), flip to popping
            -- above the whole widget box instead.
            if tipY < 0 then
                tipY = box.y2 + 12
            end
        else
            -- Normal hover behavior
            tipX = mx + 18
            tipY = my - th - 18
        end

        ------------------------------------------------------------
        -- Tooltip background + border (matches INTEL / Energy-to-Metal)
        ------------------------------------------------------------
        glColor(1, 1, 1, 0.92)
        glRect(tipX, tipY, tipX + tw, tipY + th)

        glColor(0, 0, 0, 0.25)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
            glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
            glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
            glVertex(tipX, tipY + th); glVertex(tipX, tipY)
        end)

        ------------------------------------------------------------
        -- Draw text (supports centered + styled lines + bigger)
        ------------------------------------------------------------
        local y = tipY + th - pad - fontSize
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                glColor(line.color or {0,0,0,1})

                local size =
                    line.bigger and (fontSize + 3) or
                    line.big    and (fontSize + 1) or
                    line.small  and (fontSize * 0.85) or
                    fontSize

                if line.center then
                    local w = glGetTextWidth(line.text) * size
                    local cx = tipX + (tw * 0.5) - (w * 0.5)
                    glText(line.text, cx, y, size, "lo")
                else
                    glText(line.text, tipX + pad, y, size, "lo")
                end
            else
                glColor(0,0,0,1)
                glText(line, tipX + pad, y, fontSize, "lo")
            end

            y = y - (fontSize + 4)
        end
    end
end


-- GAME SPEED + PINPOINTER + BUILD POWER (Compact Mode, lower-left corner)
do
    local px = box.x1 + 8
    -- /ecographtopbaraddon: pinned to the panel's bottom-left corner
    -- (same Y as [Pause]/[D]/[X]'s own bottom-right corner -- see the
    -- PAUSE BUTTON section below), instead of the Wind text's row.
    local py = widget._topAddonMode and (box.y1 + 12) or (box.y1 + 18)  -- Round 16: +10 for bottom-row spacing; Round 7: addon mode pinned to the bottom corner

    glColor(1, 1, 1, 1)
    glText("[INTEL]", px, py, font_scale, "o")

    -------------------------------------------------
    -- Hover rect (covers Intel area)
    -------------------------------------------------
    ppRect = widget._setRect(ppRect, px - 4, py - 4, px + 35, py + 36)
end

-- TOOLTIP FOR INFO (Compact View)
do
    local mx, my = Spring.GetMouseState()
    if intelPinned or (ppRect and mx >= ppRect.x1 and mx <= ppRect.x2 and my >= ppRect.y1 and my <= ppRect.y2) then

        local currentAlly = GetCurrentViewedAllyTeamID()
        local count = allyPinCount[currentAlly] or 0
        local has = (count > 0)

        -- Left column (labels)
        local label1 = "Game Speed:"
        local label2 = "Pinpointers (team):"
        local label3 = "Build Power:"
        local label4 = "Nuke Missiles:"
        local label5 = "Anti-Nuke:"
        local label6 = "Juno:"

        -- FIX 2: GetViewedTeamID() had a broken replay-POV branch (it
        -- re-called Spring.GetPlayerInfo, which just returns YOUR OWN
        -- team again - not the camera's followed team - so it silently
        -- got stuck on one fixed team no matter who was selected). The
        -- header above already correctly tracks whoever you're watching
        -- via Spring.GetMyTeamID(), which is a direct alias for the
        -- engine's GetLocalTeamID (gu->myTeam) - the actual value Spring
        -- updates when a spectator follows a different player. Using
        -- that same call here keeps this in sync with the header.
        local viewedTeamID = Spring.GetMyTeamID()

        local speedVal = string.format("%.1f", Spring.GetGameSpeed() or 1)
        local ppVal = has and tostring(count) or "None"
        local bpVal = string.format("%.2f", GetTotalBuildPower(viewedTeamID))
        local nukeCount, antiNukeCount, junoCount = CountMyNukeUnits(viewedTeamID)
        local nukeVal = tostring(nukeCount)
        local antiNukeVal = tostring(antiNukeCount)
        local junoVal = tostring(junoCount)

        local pad = 6

        -- Measure column widths
        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3),
            glGetTextWidth(label4),
            glGetTextWidth(label5),
            glGetTextWidth(label6)
        ) * fontSize

        local descW = math.max(
            glGetTextWidth(speedVal),
            glGetTextWidth(ppVal),
            glGetTextWidth(bpVal),
            glGetTextWidth(nukeVal),
            glGetTextWidth(antiNukeVal),
            glGetTextWidth(junoVal)
        ) * fontSize

        -- Reminder line (bottom row, spans full width)
        local reminderText = "Click on [INTEL] to pin this tooltip for reference."
        local reminderSize = fontSize * 0.85
        local reminderW = glGetTextWidth(reminderText) * reminderSize

        -- Total width
        local tw = math.max(labelW + descW + pad * 3, reminderW + pad * 2)

        -- Height for 6 rows + reminder line
        local th = fontSize * 6 + pad * 7 + reminderSize + pad

        -- LOWER-RIGHT of mouse, or anchored to [INTEL] when pinned
        local tipX, tipY
        if intelPinned then
            tipX = ppRect.x1 + 18
            tipY = ppRect.y1 - th - 18

            -- If popping downward runs off the bottom of the screen
            -- (widget sitting near the bottom edge), flip to popping
            -- above the whole widget box instead.
            if tipY < 0 then
                tipY = box.y2 + 18
            end
        else
            tipX = mx + 18
            tipY = my - th - 18
        end

        -- Background
        glColor(1, 1, 1, 0.92)
        glRect(tipX, tipY, tipX + tw, tipY + th)

        -- Border
        glColor(0, 0, 0, 0.25)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
            glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
            glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
            glVertex(tipX, tipY + th); glVertex(tipX, tipY)
        end)

        -- Text (two columns)
        glColor(0, 0, 0, 1)

        -- Row 1
        glText(label1, tipX + pad, tipY + th - fontSize - pad, fontSize, "lo")
        glText(speedVal, tipX + pad + labelW + pad, tipY + th - fontSize - pad, fontSize, "lo")

        -- Row 2
        glText(label2, tipX + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")
        glText(ppVal, tipX + pad + labelW + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")

        -- Row 3
        glText(label3, tipX + pad, tipY + th - fontSize*3 - pad*3, fontSize, "lo")
        glText(bpVal, tipX + pad + labelW + pad, tipY + th - fontSize*3 - pad*3, fontSize, "lo")

        -- Row 4
        glText(label4, tipX + pad, tipY + th - fontSize*4 - pad*4, fontSize, "lo")
        glText(nukeVal, tipX + pad + labelW + pad, tipY + th - fontSize*4 - pad*4, fontSize, "lo")

        -- Row 5
        glText(label5, tipX + pad, tipY + th - fontSize*5 - pad*5, fontSize, "lo")
        glText(antiNukeVal, tipX + pad + labelW + pad, tipY + th - fontSize*5 - pad*5, fontSize, "lo")

        -- Row 6
        glText(label6, tipX + pad, tipY + reminderSize + pad * 2, fontSize, "lo")
        glText(junoVal, tipX + pad + labelW + pad, tipY + reminderSize + pad * 2, fontSize, "lo")

        -- Reminder (centered, bottom row)
        glColor(0.35, 0.35, 0.35, 1)
        local reminderCx = tipX + (tw * 0.5) - (reminderW * 0.5)
        glText(reminderText, reminderCx, tipY + pad, reminderSize, "lo")
    end
end


    glColor(1,1,1,0.8)
    glRect(box.x2 - resizeHandleSize, box.y1,
           box.x2, box.y1 + resizeHandleSize)         

-----------------------------------------------------------
-- PAUSE BUTTON + TRANSPARENCY TOGGLE (Compact View, T sits between
-- Pause and [X]. Own flag (widget._transparentMode) -- independent of
-- the detached dual-line graph's own toggle/flag.)
------------------------------------------------------------
do
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = glGetTextWidth(hideLabel) * hideSize

    -- Same geometry as DrawHideButton()
    local hx1 = box.x2 - hideWidth - 6 - (widget._topAddonMode and 20 or 0)  -- Round 8: extra left margin in addon mode so [X] clears the resize handle (see below)
    -- /ecographtopbaraddon: [Pause]/[D or T]/[X] move down to the panel's
    -- bottom-right corner in this mode (same X -- only the Y changes),
    -- mirroring [Intel]/M:E's own bottom-left corner instead of sitting
    -- in the top row next to Status.
    local btnY = widget._topAddonMode and (box.y1 + 12) or (box.y2 - 20)

    -- Transparency toggle, directly left of [X]
    local tLabel = widget._transparentMode and "[T]" or "[D]"
    local tSize  = 14 * FONT_SCALE
    -- Reserve width for the wider of the two labels so the button
    -- doesn't shift position when the label swaps between them.
    local tWidth = math.max(glGetTextWidth("[D]"), glGetTextWidth("[T]")) * tSize
    local tx = hx1 - tWidth - 8
    local ty = btnY

    mainTransparentToggleRect = widget._setRect(mainTransparentToggleRect, tx, ty - tSize, tx + tWidth, ty + tSize)

    glColor(cfg.titleColor)
    glText(tLabel, tx, ty, tSize, "o")

    -- Round 16: "[A]" TOP-BAR ADDON MODE TOGGLE, directly left of [D]/[T]
    -- -- moved here (between [Pause] and [D]) from its original Round 15
    -- spot on the Wind bar row, per the user's own correction. Same
    -- fixed-label style as [D]/[T]/[X] (just toggles on click), same
    -- widget._addonBtnX1/Y1/X2/Y2 hitbox fields the MousePress click
    -- check already reads -- only WHERE this button draws changed, not
    -- how clicking it is detected or what it does.
    local addonLabel = "[A]"
    local addonSize  = 14 * FONT_SCALE
    local addonWidth = glGetTextWidth(addonLabel) * addonSize
    local ax = tx - addonWidth - 8
    local ay = btnY

    widget._addonBtnX1 = ax
    widget._addonBtnY1 = ay - addonSize
    widget._addonBtnX2 = ax + addonWidth
    widget._addonBtnY2 = ay + addonSize

    glColor(cfg.titleColor)
    glText(addonLabel, ax, ay, addonSize, "o")

    -- Pause button
    local pauseLabel = "[Pause]"
    local pauseSize  = 14 * FONT_SCALE
    local pauseWidth = glGetTextWidth(pauseLabel) * pauseSize

    -- Round 16: Pause now sits left of "[A]" instead of directly left of
    -- the transparency toggle, to make room for the new button between
    -- them.
    local px = ax - pauseWidth - 8
    local py = btnY

    -- Save hitbox for click detection
    pauseButtonRect = widget._setRect(pauseButtonRect, px, py - pauseSize, px + pauseWidth, py + pauseSize)

------------------------------------------------------------
-- ENERGY → METAL STATS (Compact View, fixed + ultra-compact)
------------------------------------------------------------
do
    -- format helper: converts 1200 → 1.2k
    local function formatK(n, suffix)
        local absn = math.abs(n)
        if absn >= 1000 then
            return string.format("%.1fk%s", n / 1000, suffix)
        else
            return string.format("%d%s", n, suffix)
        end
    end

    -- use raw values (fixes the "always 0" bug)
    local eVal = convEnergy
    local mVal = convMetal

    -- local eText = formatK(eVal, "e")
    -- local mText = formatK(mVal, "m")
    -- local uText = string.format("%d%%", convUtil)

widget._convStatCache = widget._convStatCache or {}
local ccache = widget._convStatCache
local eText, mText, uText
if ccache.eVal == eVal and ccache.mVal == mVal and ccache.convUtil == convUtil then
    eText, mText, uText = ccache.eText, ccache.mText, ccache.uText
else
    eText = "-" .. formatK(math.abs(eVal or 0), "e")
    mText = "+" .. formatK(math.abs(mVal or 0), "m")
    uText = string.format("%d%%", convUtil or 0)
    ccache.eVal, ccache.mVal, ccache.convUtil = eVal, mVal, convUtil
    ccache.eText, ccache.mText, ccache.uText = eText, mText, uText
end

    -- ultra-compact reserved widths
    local eW = glGetTextWidth("-99.9ke") * pauseSize
    local mW = glGetTextWidth("+99.9km") * pauseSize
    local uW = glGetTextWidth("100%")    * pauseSize
    local bracketW = glGetTextWidth("[") * pauseSize * 0.9

    local totalW = bracketW + eW + mW + uW + bracketW

    -- position: LEFT of Pause button (X only -- see below for Y).
    -- Round 9: in addon mode, Pause moved down to the bottom-right
    -- corner (see sy below), so anchoring this bracket's X off px
    -- any more just leaves it stranded wherever Pause used to be --
    -- not actually near the panel's right edge any more. Anchor it
    -- directly off box.x2 instead so it's flush in the top-right
    -- corner on its own, independent of where Pause now sits.
    local sx = widget._topAddonMode and (box.x2 - 10 - totalW) or (px - 14 - totalW)  -- moving the Energy to Metal stats left or right. The higher goes left.
    -- /ecographtopbaraddon: Pause moved down to the bottom-right corner,
    -- but this bracket stays on the TOP row next to Status -- so its Y
    -- can't just follow Pause's py any more; pin it to the same fixed
    -- top-row Y Status/the title row use instead.
    local sy = widget._topAddonMode and (box.y2 - 20) or py

    -- [
    glColor(1,1,1,1)
    glText("[", sx + bracketW * 0.5, sy, pauseSize, "oc")

    -- energy
    glColor(1,1,0.2,1)
    glText(eText, sx + bracketW + eW * 0.5, sy, pauseSize, "oc")

    -- metal
    glColor(0.2,1,1,1)
    glText(mText, sx + bracketW + eW + mW * 0.5, sy, pauseSize, "oc")

    -- util %
    glColor(1,1,1,1)
    glText(uText, sx + bracketW + eW + mW + uW * 0.5, sy, pauseSize, "oc")

    -- ]
    glColor(1,1,1,1)
    glText("]", sx + bracketW + eW + mW + uW + bracketW * 0.5, sy, pauseSize, "oc")

    -- Tooltip hitbox
    convStatRect = widget._setRect(convStatRect, sx, sy - pauseSize, sx + totalW, sy + pauseSize)
end

-- Draw Pause
glColor(cfg.titleColor)
glText(pauseLabel, px, py, pauseSize, "o")

end

------------------------------------------------------------
-- METAL INCOME TOOLTIP (Compact View)
------------------------------------------------------------
do
    local mx, my = Spring.GetMouseState()

    if metalIncRect
    and mx >= metalIncRect.x1 and mx <= metalIncRect.x2
    and my >= metalIncRect.y1 and my <= metalIncRect.y2 then

        local rawTotal = (smoothMexIncome or 0)
                       + (smoothConversionIncome or 0)
                       + (smoothOtherIncome or 0)

        local label1 = "Mexes"
        local label2 = "E-Conv"
        local label3 = "Other"
        local label4 = "Raw Total"

        local value1 = string.format("= %6.1f", smoothMexIncome or 0)
        local value2 = string.format("= %6.1f", smoothConversionIncome or 0)
        local value3 = string.format("= %6.1f", smoothOtherIncome or 0)
        local value4 = string.format("= %6.1f", rawTotal)

        local pad = 6

        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3),
            glGetTextWidth(label4)
        ) * fontSize

        local valueW = math.max(
            glGetTextWidth(value1),
            glGetTextWidth(value2),
            glGetTextWidth(value3),
            glGetTextWidth(value4)
        ) * fontSize

        local tw = (labelW + valueW + pad * 3) * 1.5
        local th = fontSize * 4 + pad * 5

        local tipX = mx + 18
        local tipY = my - th - 18

        glColor(1, 1, 1, 0.92)
        glRect(tipX, tipY, tipX + tw, tipY + th)

        glColor(0, 0, 0, 0.25)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
            glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
            glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
            glVertex(tipX, tipY + th); glVertex(tipX, tipY)
        end)

        glColor(0, 0, 0, 1)

        glText(label1, tipX + pad,                     tipY + th - fontSize - pad,             fontSize, "lo")
        glText(value1, tipX + tw - pad,                tipY + th - fontSize - pad,             fontSize, "ro")

        glText(label2, tipX + pad,                     tipY + th - fontSize*2 - pad*2,         fontSize, "lo")
        glText(value2, tipX + tw - pad,                tipY + th - fontSize*2 - pad*2,         fontSize, "ro")

        glText(label3, tipX + pad,                     tipY + th - fontSize*3 - pad*3,         fontSize, "lo")
        glText(value3, tipX + tw - pad,                tipY + th - fontSize*3 - pad*3,         fontSize, "ro")

        glText(label4, tipX + pad,                     tipY + pad,                              fontSize, "lo")
        glText(value4, tipX + tw - pad,                tipY + pad,                              fontSize, "ro")
    end
end

-- ENERGY INC TOOLTIP (Bold labels + aligned values)
do
    if energyIncRect then
        local mx, my = Spring.GetMouseState()
        if mx >= energyIncRect.x1 and mx <= energyIncRect.x2
        and my >= energyIncRect.y1 and my <= energyIncRect.y2 then

            -- Labels (left column, BOLD)
            local label1 = "Static Generators"
            local label2 = "Dynamic Generators"
            local label3 = "Total"

            -- Values (right column, aligned + bold)
            local value1 = string.format("= %6.1f", smoothEnergyGen or 0)
            local value2 = string.format("= %6.1f", smoothEnergyReclaim or 0)
            local value3 = string.format("= %6.1f", (smoothEnergyGen or 0) + (smoothEnergyReclaim or 0))

            ------------------------------------------------------------------
            -- NEW TWO‑COLUMN DESCRIPTIONS
            ------------------------------------------------------------------
            local descL1 = "Static:"
            local descR1 = "Commander, T1/T2 Construction Bots"
            local descR2 = "T1 Solar, Advanced Solar, Fusion, Advanced Fusion, etc."

            local descL2 = "Dynamic:"
            local descR3 = "Turbines, Share, Reclaim"
            local descR4 = "Tidal Generators, etc."

            -- Measure width
            local pad = 6

            local wTop = math.max(
                glGetTextWidth(label1 .. value1),
                glGetTextWidth(label2 .. value2),
                glGetTextWidth(label3 .. value3)
            ) * fontSize

            local wDescLeft = math.max(
                glGetTextWidth(descL1),
                glGetTextWidth(descL2)
            ) * fontSize

            local wDescRight = math.max(
                glGetTextWidth(descR1),
                glGetTextWidth(descR2),
                glGetTextWidth(descR3),
                glGetTextWidth(descR4)
            ) * fontSize

            local tw = math.max(wTop, wDescLeft + wDescRight + pad * 2) + pad * 2
            local th = fontSize * 7 + pad * 8

            local tipX = mx + 18
            local tipY = my - th - 18
            if (detached and detached.y1 and tipY < detached.y1 + 4) or tipY < 0 then
                tipY = my + 18
            end

            -- Background
            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            -- Border
            glColor(0, 0, 0, 0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            -- BOLD labels (left-aligned)
            glColor(0, 0, 0, 1)
            glText(label1, tipX + pad,                     tipY + th - fontSize - pad,             fontSize, "lo")
            glText(label2, tipX + pad,                     tipY + th - fontSize*2 - pad*2,         fontSize, "lo")
            glText(label3, tipX + pad,                     tipY + th - fontSize*3 - pad*3,         fontSize, "lo")

            -- BOLD values (right-aligned)
            glText(value1, tipX + tw - pad,                tipY + th - fontSize - pad,             fontSize, "ro")
            glText(value2, tipX + tw - pad,                tipY + th - fontSize*2 - pad*2,         fontSize, "ro")
            glText(value3, tipX + tw - pad,                tipY + th - fontSize*3 - pad*3,         fontSize, "ro")

            ------------------------------------------------------------------
            -- TWO‑COLUMN DESCRIPTIONS (Static + Dynamic)
            ------------------------------------------------------------------

            -- Static row 1
            glText(descL1, tipX + pad,                     tipY + th - fontSize*4 - pad*5,         fontSize, "lo")
            glText(descR1, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*4 - pad*5,         fontSize, "lo")

            -- Static row 2
            glText(descR2, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*5 - pad*6,         fontSize, "lo")

            -- Dynamic row 1
            glText(descL2, tipX + pad,                     tipY + th - fontSize*6 - pad*7,         fontSize, "lo")
            glText(descR3, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*6 - pad*7,         fontSize, "lo")

            -- Dynamic row 2
            glText(descR4, tipX + pad + wDescLeft + pad,   tipY + pad,                             fontSize, "lo")

        end
    end
end

------------------------------------------------------------
-- ENERGY → METAL CONVERSION TOOLTIP (Compact View)
------------------------------------------------------------
do
    local mx, my = Spring.GetMouseState()

    if convStatPinned or (convStatRect
    and mx >= convStatRect.x1 and mx <= convStatRect.x2
    and my >= convStatRect.y1 and my <= convStatRect.y2) then

        local title  = "Energy to Metal Conversion"
        local label1 = "Energy use:"
        local label2 = "Metal gain:"
        local label3 = "Efficiency:"

        local value1 = string.format("-%de", math.floor(convEnergy + 0.5))
        local value2 = string.format("+%dm", math.floor(convMetal + 0.5))
        local value3 = string.format("%d%%", convUtil)

        local pad = 6
        local titleSize = fontSize * 1.1

        -- measure widths
        local titleW = glGetTextWidth(title) * titleSize

        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3)
        ) * fontSize

        local valueW = math.max(
            glGetTextWidth(value1),
            glGetTextWidth(value2),
            glGetTextWidth(value3)
        ) * fontSize

        -- Reminder line (bottom row, just a hint text)
        local reminderText = "Click to pin this tooltip for reference."
        local reminderSize = fontSize * 0.85
        local reminderW = glGetTextWidth(reminderText) * reminderSize

        local tw = math.max(titleW, labelW + valueW + pad * 3, reminderW) + pad * 2
        local th = titleSize + (fontSize * 3) + pad * 6 + reminderSize + pad

        -- Nudged 20px further down from where it would otherwise pop up,
        -- so it clears the metal storage bar and draggable thumbs below
        -- instead of covering them.
        local NUDGE_DOWN = 10
        local tipX, tipY
        if convStatPinned then
            -- Anchor tooltip to the stat itself instead of the mouse.
            -- Extends LEFTWARD (like M:E) since this icon sits near the
            -- widget's right edge next to Pause/X.
            --
            -- Vertically: this icon sits at the widget's TOP edge (fixed,
            -- doesn't move on resize). INTEL/M:E sit at the BOTTOM edge
            -- and pop their tooltip further down, away from the widget,
            -- into free space - that's why resizing never makes them
            -- cover anything. Popping downward from a TOP-anchored icon
            -- instead pops the tooltip straight into the widget's
            -- interior (over the energy bar/thumbs), which is the bug.
            -- Fix: pop UPWARD instead, away from the widget entirely,
            -- so it can never overlap widget content regardless of size.
            tipX = convStatRect.x1 - tw + 20
            tipY = convStatRect.y2 + 18

            -- If popping upward would push it off the top of the screen
            -- (widget sitting near the top edge), fall back to popping
            -- downward instead - but below the WHOLE widget box (box.y1),
            -- not just below the icon, so it lands outside the widget's
            -- borders instead of over the graph/energy bar/thumbs inside it.
            local _, vsy = Spring.GetViewGeometry()
            if tipY + th > vsy then
                tipY = box.y1 - th - 18
            end
        else
            tipX = mx + 18
            tipY = my - th - 18 - NUDGE_DOWN
        end

        -- background
        glColor(1, 1, 1, 0.92)
        glRect(tipX, tipY, tipX + tw, tipY + th)

        -- border
        glColor(0, 0, 0, 0.25)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
            glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
            glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
            glVertex(tipX, tipY + th); glVertex(tipX, tipY)
        end)

        glColor(0, 0, 0, 1)

        -- title
        glText(title, tipX + pad, tipY + th - titleSize - pad, titleSize, "lo")

        -- rows
        glText(label1, tipX + pad,                     tipY + th - titleSize - fontSize*1 - pad*3, fontSize, "lo")
        glText(value1, tipX + tw - pad,                tipY + th - titleSize - fontSize*1 - pad*3, fontSize, "ro")

        glText(label2, tipX + pad,                     tipY + th - titleSize - fontSize*2 - pad*4, fontSize, "lo")
        glText(value2, tipX + tw - pad,                tipY + th - titleSize - fontSize*2 - pad*4, fontSize, "ro")

        glText(label3, tipX + pad,                     tipY + th - titleSize - fontSize*3 - pad*5, fontSize, "lo")
        glText(value3, tipX + tw - pad,                tipY + th - titleSize - fontSize*3 - pad*5, fontSize, "ro")

        -- Reminder (centered, bottom row)
        glColor(0.35, 0.35, 0.35, 1)
        local reminderCx = tipX + (tw * 0.5) - (reminderW * 0.5)
        glText(reminderText, reminderCx, tipY + pad, reminderSize, "lo")
    end
end


end  -- end of DrawCompactOverlay()

-- WIDGET CALLINS
local Detached_Load, Detached_Save
function widget:ViewResize()
    UpdateViewGeometry()
end

function widget:Initialize()

    
compactMode = true

    -- Team + ally tracking for commander logic
	myAllyTeamID = Spring.GetLocalAllyTeamID()
    myAllyTeam = Spring.GetLocalAllyTeamID()   -- FIXED

    -- Reset commander counters
    commanderC1 = 0   -- my allyteam
    commanderC2 = 0   -- enemy allyteams

    -- Scan all existing units for commanders (correct BAR signature)
    local units = Spring.GetAllUnits()
    for _, unitID in ipairs(units) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if unitDefID then
            local ud = UnitDefs[unitDefID]
            if ud and ud.customParams and ud.customParams.iscommander then
                local teamID = Spring.GetUnitTeam(unitID)

                -- Correct BAR return signature:
                -- teamID, leader, isDead, isAiTeam, side, allyTeamID
                local _, _, isDead, _, _, allyTeamID = Spring.GetTeamInfo(teamID)

                if not isDead then
                    if allyTeamID == myAllyTeam then
                        commanderC1 = commanderC1 + 1
                    else
                        commanderC2 = commanderC2 + 1
                    end
                end
            end
        end
    end

    -- Initialize geometry (vsx/vsy + box coords)
    UpdateViewGeometry()

    -- Load saved BAR config (position + size)
    local savedX = Spring.GetConfigFloat("eco_graph_x", cfg.anchorX)
    local savedY = Spring.GetConfigFloat("eco_graph_y", cfg.anchorY)
    local savedW = Spring.GetConfigFloat("eco_graph_w", cfg.width)
    local savedH = Spring.GetConfigFloat("eco_graph_h", cfg.height)

    cfg.anchorX = savedX
    cfg.anchorY = savedY
    cfg.width   = savedW
    cfg.height  = savedH

    -- FIRST TIME EVER: place Eco Graph upper‑center
    
    -- Detect first-time by checking if user never saved a position
    local hasSavedPos = Spring.GetConfigFloat("eco_graph_x", nil, false)

    if hasSavedPos == nil then
        -- center horizontally
        cfg.anchorX = 0.5

        -- upper center (75% up the screen)
        cfg.anchorY = 0.75
    end

    -- Recompute box from cfg
    local w = vsx * cfg.width
    local h = vsy * cfg.height

    box.x1 = vsx * cfg.anchorX - w * 0.5
    box.y1 = vsy * cfg.anchorY
    box.x2 = box.x1 + w
    box.y2 = box.y1 + h

    
    -- Build initial graph list
    if graphList then
        glDeleteList(graphList)
    end
    graphList = nil

------------------------------------------------------------
-- LOAD SAVED HISTORY SECONDS
------------------------------------------------------------
local savedHist = Spring.GetConfigInt("eco_graph_history_seconds", cfg.historySeconds)
cfg.historySeconds = savedHist or cfg.historySeconds

-- Resync the sample-retention cap to the just-restored history length.
-- UpdateViewGeometry() already ran above (for vsx/vsy + box sizing)
-- using the DEFAULT cfg.historySeconds, before this saved value loaded --
-- without this, the actual sample buffer stays capped at the default
-- duration's worth of samples for the rest of the session, even though
-- the dropdown and the graph's drawn time axis correctly show the
-- restored length.
historyMaxSamples = math.max(30, math.floor(cfg.historySeconds * 30))

------------------------------------------------------------
-- LOAD SAVED BACKGROUND MODE ("Default" opaque vs "Transparent")
-- Stored on the widget table (not a new top-level local) -- this file's
-- main chunk is already at Lua's 200-local ceiling, same reason the
-- Top-Bar-safety-net Shutdown hook below stores its state on `widget`.
--
-- Two independent flags, two independent config keys: the main/attached
-- window and the detached dual-line graph each remember their own
-- transparency choice and can be switched on/off separately.
------------------------------------------------------------
widget._transparentMode = Spring.GetConfigInt("eco_graph_transparent_mode", 0) == 1
widget._detachedTransparentMode = Spring.GetConfigInt("eco_detached_transparent_mode", 0) == 1

-- "Top Bar"-style panel skin (/ecographbar) -- one flag shared by both
-- windows, same reasoning as /ecographt//ecographd setting both
-- windows' transparency together: there's no way to name "just one
-- window" from a single command, so this one switch covers both.
widget._barSkin = Spring.GetConfigInt("eco_graph_bar_skin", 0) == 1

-- "Top Bar" skin, take 2 (/ecographbarui) -- uses WG.FlowUI.Draw.Element,
-- BAR's own shared panel-chrome function (see the big comment above the
-- vertex helpers for where this was confirmed). Kept as a separate flag
-- from widget._barSkin/`/ecographbar` (Round 10's hand-approximated
-- version) rather than replacing it -- the user asked to keep both as
-- independent options.
--
-- Round 12: this is now the DEFAULT look for a player who has never
-- touched this setting. Spring.GetConfigInt's own default argument can't
-- tell "never set" apart from "explicitly set to 0" -- both come back as
-- whatever default you pass -- so -1 is used as a sentinel that could
-- never come from Spring.SetConfigInt(key, 0/1) elsewhere in this file.
-- Seeing -1 means this key has never been written for this player; the
-- flag is set ON and immediately persisted as a real 1, so every
-- subsequent load (including after an explicit /ecographbarui OFF, or
-- /ecographorig) reads back whatever the player actually chose, not the
-- sentinel.
local savedBarSkinUi = Spring.GetConfigInt("eco_graph_bar_skin_ui", -1)
if savedBarSkinUi == -1 then
    widget._barSkinUi = true
    Spring.SetConfigInt("eco_graph_bar_skin_ui", 1)
else
    widget._barSkinUi = savedBarSkinUi == 1
end

-- Load saved hide state for the dual-line/history selector toggle
local savedHide = Spring.GetConfigInt("eco_graph_hide_graphs", 0)
hideGraphs = (savedHide == 1)

-- Load saved Top-Bar addon mode (/ecographtopbaraddon) -- a minimal,
-- Top-Bar-replacement layout that hides the storage bars (and their
-- draggable auto-share thumbs), the Big Metal/Energy Available
-- readout, the commander count, the Tidal stat, and the income/usage
-- graphs + history selector -- leaving just the title/status row,
-- [Pause]/[D]/[X], the energy-to-metal stats bracket, [Intel], the
-- M:E ratio, and the Wind text + bar. See the /ecographtopbaraddon
-- console command (bottom of this file) for the actual toggle.
widget._topAddonMode = Spring.GetConfigInt("eco_graph_top_addon_mode", 0) == 1

    -- Ensure detached window respects saved position on initialize
    -- `Detached_Load()` is called later after the detached helpers are defined.

--------------------------------------------------------------------------------
-- LOAD SAVED FONT SCALE
--------------------------------------------------------------------------------
-- FONT_SCALE is a plain chunk-level local (see its declaration near the
-- top), reassigned here rather than re-declared -- this file is already
-- at Lua's 200-local ceiling, same reason everything else below hangs
-- off `widget` or an existing table instead of a new local.
FONT_SCALE = Spring.GetConfigFloat("eco_graph_font_scale", FONT_SCALE)

end

    -- Load saved position (if any)
    if WG and WG.EcoGraphPos then
        box.x1 = WG.EcoGraphPos.x1
        box.y1 = WG.EcoGraphPos.y1
        box.x2 = WG.EcoGraphPos.x2
        box.y2 = WG.EcoGraphPos.y2
    end

    -- Build initial graph list
    if graphList then
        glDeleteList(graphList)
    end
    graphList = nil

function widget:Shutdown()
    if graphList then glDeleteList(graphList) end
end

-- GAMEFRAME (PLAYER SWITCH + FADE + HISTORY RESET)

local historyCache = {}   -- teamID → {metal={}, energy={}}

-- FLOATING UNHIDE BUTTO
local function DrawUnhideButton()
    local label    = "[Unhide Eco Graph]"
    local fontSize = 14 * FONT_SCALE

    -- Position: top center of the screen
    local textWidth = gl.GetTextWidth(label) * fontSize
    local x         = (vsx * 0.5) - (textWidth * 0.5)
    local y         = vsy - 40

    glColor(1,1,1,0.9)
    glText(label, x, y, fontSize, "o")
end

local function DrawHideButton()
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = gl.GetTextWidth(hideLabel) * hideSize
    local hx1 = box.x2 - hideWidth - 6 - (widget._topAddonMode and 20 or 0)  -- Round 8: see the PAUSE BUTTON block comment in DrawCompactOverlay
    -- /ecographtopbaraddon: moves down to the bottom-right corner along
    -- with Pause/[D]/[T] (see the PAUSE BUTTON block in DrawCompactOverlay)
    local hy1 = widget._topAddonMode and (box.y1 + 12) or (box.y2 - 20)
    
    glColor(1,1,1,0.9)
    glText(hideLabel, hx1, hy1, hideSize, "o")
end

function DrawMetalShareDropdown()
    metalShareOptionRects = {}

    local bx1 = metalShareButtonRect.x1
    local by1 = metalShareButtonRect.y1
    local bx2 = metalShareButtonRect.x2
    local by2 = metalShareButtonRect.y2

    local optionHeight = (by2 - by1)
    local gap = 2

    for i, pct in ipairs(metalShareOptions) do
        local oy1 = by1 - (optionHeight + gap) * i
        local oy2 = oy1 + optionHeight
        local ox1 = bx1
        local ox2 = bx2

        metalShareOptionRects[i] = { x1 = ox1, y1 = oy1, x2 = ox2, y2 = oy2 }

        local mx, my = spGetMouseState()
        local hover = PointInRect(mx, my, ox1, oy1, ox2, oy2)

        if hover then
            glColor(1, 1, 1, 0.20)
        else
            glColor(0, 0, 0, 0.80)
        end
        glRect(ox1, oy1, ox2, oy2)

        glColor(1, 1, 1, 0.35)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(ox1, oy1); glVertex(ox2, oy1)
            glVertex(ox2, oy1); glVertex(ox2, oy2)
            glVertex(ox2, oy2); glVertex(ox1, oy2)
            glVertex(ox1, oy2); glVertex(ox1, oy1)
        end)

local optLabel
if pct == "Disable" then
    optLabel = "Disable"
else
    optLabel = string.format("%d%%", math.floor(pct * 100 + 0.5))
end
        glColor(cfg.titleColor)
        glText(optLabel, (ox1 + ox2) * 0.5, oy1 + 3, fontSize, "oc")
    end
end

-- DRAW SCREEN (FINAL, BAR-SAFE)
function widget:DrawScreen()

    -- Always draw toggle menu
    EcoToggleMenu.Draw()

    ------------------------------------------------------------------
    -- FIXED: Only hide the entire widget when explicitly hidden,
    -- NOT when hideGraphs is toggled.
    ------------------------------------------------------------------
if WG.EcoGraph_UIVisible == false then
    return
end

    -- Existing BAR-safe hide logic
    if fullyHidden then
        DrawUnhideButton()
        return
    end

    if not showWidget then return end
    if spIsGUIHidden() then return end

    if compactMode then
        DrawCompactOverlay()
        DrawHideButton()
    else

        ------------------------------------------------------------------
        -- FIXED: Only skip the dual-line graphs, NOT the whole UI
        ------------------------------------------------------------------
        if not hideGraphs then
            if graphList then glCallList(graphList) end
        end

        -- Always draw the rest of the UI (in-game UI)
        DrawOverlay()

        -- INFO badge (lower-left corner)
        do
            local currentAlly = GetCurrentViewedAllyTeamID()
            local count = allyPinCount[currentAlly] or 0
            local has = (count > 0)

            -- Base position
            local px = box.x1 + 8
            local py = box.y1 + 8

            glColor(1, 1, 1, 1)
            glText("[ Intel ]", px, py, font_scale, "o")

            -- INTEL tooltip hitbox (reduced)
            intelRect = {
                x1 = intelX - 2,
                y1 = intelY - fontSize,
                x2 = intelX + 55,   -- was too long before, now short
                y2 = intelY + fontSize,
            }

        end

-- INFO TOOLTIP (Two-Column)
do
    local mx, my = Spring.GetMouseState()
    if intelPinned or (ppRect and mx >= ppRect.x1 and mx <= ppRect.x2 and my >= ppRect.y1 and my <= ppRect.y2) then

        local currentAlly = GetCurrentViewedAllyTeamID()
        local count = allyPinCount[currentAlly] or 0
        local has = (count > 0)

        -- Left column (labels)
        local label1 = "Game Speed:"
        local label2 = "Pinpointers (team):"
        local label3 = "Build Power:"
        local label4 = "Nuke Missiles:"
        local label5 = "Anti-Nuke:"
        local label6 = "Juno:"

        -- FIX 2: GetViewedTeamID() had a broken replay-POV branch (it
        -- re-called Spring.GetPlayerInfo, which just returns YOUR OWN
        -- team again - not the camera's followed team - so it silently
        -- got stuck on one fixed team no matter who was selected). The
        -- header above already correctly tracks whoever you're watching
        -- via Spring.GetMyTeamID(), which is a direct alias for the
        -- engine's GetLocalTeamID (gu->myTeam) - the actual value Spring
        -- updates when a spectator follows a different player. Using
        -- that same call here keeps this in sync with the header.
        local viewedTeamID = Spring.GetMyTeamID()

        local speedVal = string.format("%.1f", Spring.GetGameSpeed() or 1)
        local ppVal = has and tostring(count) or "None"
        local bpVal = string.format("%.2f", GetTotalBuildPower(viewedTeamID))
        local nukeCount, antiNukeCount, junoCount = CountMyNukeUnits(viewedTeamID)
        local nukeVal = tostring(nukeCount)
        local antiNukeVal = tostring(antiNukeCount)
        local junoVal = tostring(junoCount)

        local pad = 6

        -- Measure column widths
        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3),
            glGetTextWidth(label4),
            glGetTextWidth(label5),
            glGetTextWidth(label6)
        ) * fontSize

        local descW = math.max(
            glGetTextWidth(speedVal),
            glGetTextWidth(ppVal),
            glGetTextWidth(bpVal),
            glGetTextWidth(nukeVal),
            glGetTextWidth(antiNukeVal),
            glGetTextWidth(junoVal)
        ) * fontSize

        -- Reminder line (bottom row, spans full width)
        local reminderText = "Click on [INTEL] to pin this tooltip for reference."
        local reminderSize = fontSize * 0.85
        local reminderW = glGetTextWidth(reminderText) * reminderSize

        -- Total width
        local tw = math.max(labelW + descW + pad * 3, reminderW + pad * 2)

        -- Height for 6 rows + reminder line
        local th = fontSize * 6 + pad * 7 + reminderSize + pad

        -- LOWER-RIGHT of mouse cursor, or anchored to [INTEL] when pinned
        local tipX, tipY
        if intelPinned then
            tipX = ppRect.x1 + 18
            tipY = ppRect.y1 - th - 18

            -- If popping downward runs off the bottom of the screen
            -- (widget sitting near the bottom edge), flip to popping
            -- above the whole widget box instead.
            if tipY < 0 then
                tipY = box.y2 + 18
            end
        else
            tipX = mx + 18
            tipY = my - th - 18
        end

        -- Background
        glColor(1, 1, 1, 0.92)
        glRect(tipX, tipY, tipX + tw, tipY + th)

        -- Border
        glColor(0, 0, 0, 0.25)
        glLineWidth(1.0)
        glBeginEnd(GL_LINES, function()
            glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
            glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
            glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
            glVertex(tipX, tipY + th); glVertex(tipX, tipY)
        end)

        -- Text (two columns)
        glColor(0, 0, 0, 1)

        -- Row 1
        glText(label1, tipX + pad, tipY + th - fontSize - pad, fontSize, "lo")
        glText(speedVal, tipX + pad + labelW + pad, tipY + th - fontSize - pad, fontSize, "lo")

        -- Row 2
        glText(label2, tipX + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")
        glText(ppVal, tipX + pad + labelW + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")

        -- Row 3
        glText(label3, tipX + pad, tipY + th - fontSize*3 - pad*3, fontSize, "lo")
        glText(bpVal, tipX + pad + labelW + pad, tipY + th - fontSize*3 - pad*3, fontSize, "lo")

        -- Row 4
        glText(label4, tipX + pad, tipY + th - fontSize*4 - pad*4, fontSize, "lo")
        glText(nukeVal, tipX + pad + labelW + pad, tipY + th - fontSize*4 - pad*4, fontSize, "lo")

        -- Row 5
        glText(label5, tipX + pad, tipY + th - fontSize*5 - pad*5, fontSize, "lo")
        glText(antiNukeVal, tipX + pad + labelW + pad, tipY + th - fontSize*5 - pad*5, fontSize, "lo")

        -- Row 6
        glText(label6, tipX + pad, tipY + reminderSize + pad * 2, fontSize, "lo")
        glText(junoVal, tipX + pad + labelW + pad, tipY + reminderSize + pad * 2, fontSize, "lo")

        -- Reminder (centered, bottom row)
        glColor(0.35, 0.35, 0.35, 1)
        local reminderCx = tipX + (tw * 0.5) - (reminderW * 0.5)
        glText(reminderText, reminderCx, tipY + pad, reminderSize, "lo")
    end
end

-- METAL INC TOOLTIP (50% wider, tight vertical spacing)
do

        Spring.Echo("Checking metalIncRect...")
    if metalIncRect then
        local mx, my = Spring.GetMouseState()
        if mx >= metalIncRect.x1 and mx <= metalIncRect.x2
        and my >= metalIncRect.y1 and my <= metalIncRect.y2 then

            local rawTotal = (smoothMexIncome or 0)
                           + (smoothConversionIncome or 0)
                           + (smoothOtherIncome or 0)

            -- Labels (left column, bold)
            local label1 = "Mexes"
            local label2 = "E-Conv"
            local label3 = "Other"
            local label4 = "Raw Total"

            -- Values (right column, aligned + bold)
            local value1 = string.format("= %6.1f", smoothMexIncome or 0)
            local value2 = string.format("= %6.1f", smoothConversionIncome or 0)
            local value3 = string.format("= %6.1f", smoothOtherIncome or 0)
            local value4 = string.format("= %6.1f", rawTotal)

            -- Measure width
            local pad = 6
            local labelW = math.max(
                glGetTextWidth(label1),
                glGetTextWidth(label2),
                glGetTextWidth(label3),
                glGetTextWidth(label4)
            ) * fontSize

            local valueW = math.max(
                glGetTextWidth(value1),
                glGetTextWidth(value2),
                glGetTextWidth(value3),
                glGetTextWidth(value4)
            ) * fontSize

            -- Add 50% extra width for breathing room
            local tw = (labelW + valueW + pad * 3) * 1.5
            local th = fontSize * 4 + pad * 5

            local tipX = mx + 18
            local tipY = my + 18

Spring.Echo(string.format("Tooltip: my=%d, th=%d, vsy=%d, tipY+th=%d, limit=%d", my, th, vsy, tipY + th, vsy - 4))

            -- If below cursor goes off bottom, place above instead
            if tipY + th > vsy - 4 then
                tipY = my - th - 18
            end
            -- Final clamp to screen bounds
            if tipY < 4 then tipY = 4 end
            if tipY + th > vsy - 4 then tipY = vsy - th - 4 end

            -- Background
            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            -- Border
            glColor(0, 0, 0, 0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)


            -- Text (tight spacing, bold)
            glColor(0, 0, 0, 1)

            glText(label1, tipX + pad, tipY + th - fontSize - pad,             fontSize, "lo")
            glText(value1, tipX + tw - pad, tipY + th - fontSize - pad,        fontSize, "ro")

            glText(label2, tipX + pad, tipY + th - fontSize*2 - pad*2,         fontSize, "lo")
            glText(value2, tipX + tw - pad, tipY + th - fontSize*2 - pad*2,    fontSize, "ro")

            glText(label3, tipX + pad, tipY + th - fontSize*3 - pad*3,         fontSize, "lo")
            glText(value3, tipX + tw - pad, tipY + th - fontSize*3 - pad*3,    fontSize, "ro")

            glText(label4, tipX + pad, tipY + th - fontSize*4 - pad*4,         fontSize, "lo")
            glText(value4, tipX + tw - pad, tipY + th - fontSize*4 - pad*4,    fontSize, "ro")

        end
    end
end

-- ENERGY INC TOOLTIP (Bold labels + aligned values)
do
    if energyIncRect then
        local mx, my = Spring.GetMouseState()
        if mx >= energyIncRect.x1 and mx <= energyIncRect.x2
        and my >= energyIncRect.y1 and my <= energyIncRect.y2 then

            -- Labels (left column, BOLD)
            local label1 = "Static Generators"
            local label2 = "Dynamic Generators"
            local label3 = "Total"

            -- Values (right column, aligned + bold)
            local value1 = string.format("= %6.1f", smoothEnergyGen or 0)
            local value2 = string.format("= %6.1f", smoothEnergyReclaim or 0)
            local value3 = string.format("= %6.1f", (smoothEnergyGen or 0) + (smoothEnergyReclaim or 0))

            ------------------------------------------------------------------
            -- NEW TWO‑COLUMN DESCRIPTIONS
            ------------------------------------------------------------------
            local descL1 = "Static:"
            local descR1 = "Commander, T1/T2 Construction Bots"
            local descR2 = "Advanced Solar, Fusion, Advanced Fusion, etc."

            local descL2 = "Dynamic:"
            local descR3 = "T1 Solar, Turbines, Share, Reclaim"
            local descR4 = "Tidal Generators, etc."

            -- Measure width
            local pad = 6

            local wTop = math.max(
                glGetTextWidth(label1 .. value1),
                glGetTextWidth(label2 .. value2),
                glGetTextWidth(label3 .. value3)
            ) * fontSize

            local wDescLeft = math.max(
                glGetTextWidth(descL1),
                glGetTextWidth(descL2)
            ) * fontSize

            local wDescRight = math.max(
                glGetTextWidth(descR1),
                glGetTextWidth(descR2),
                glGetTextWidth(descR3),
                glGetTextWidth(descR4)
            ) * fontSize

            local tw = math.max(wTop, wDescLeft + wDescRight + pad * 2) + pad * 2
            local th = fontSize * 7 + pad * 8

            local tipX = mx + 18
            local tipY = my - th - 18

            -- Background
            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            -- Border
            glColor(0, 0, 0, 0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            -- BOLD labels (left-aligned)
            glColor(0, 0, 0, 1)
            glText(label1, tipX + pad,                     tipY + th - fontSize - pad,             fontSize, "lo")
            glText(label2, tipX + pad,                     tipY + th - fontSize*2 - pad*2,         fontSize, "lo")
            glText(label3, tipX + pad,                     tipY + th - fontSize*3 - pad*3,         fontSize, "lo")

            -- BOLD values (right-aligned)
            glText(value1, tipX + tw - pad,                tipY + th - fontSize - pad,             fontSize, "ro")
            glText(value2, tipX + tw - pad,                tipY + th - fontSize*2 - pad*2,         fontSize, "ro")
            glText(value3, tipX + tw - pad,                tipY + th - fontSize*3 - pad*3,         fontSize, "ro")

            ------------------------------------------------------------------
            -- TWO‑COLUMN DESCRIPTIONS (Static + Dynamic)
            ------------------------------------------------------------------

            -- Static row 1
            glText(descL1, tipX + pad,                     tipY + th - fontSize*4 - pad*5,         fontSize, "lo")
            glText(descR1, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*4 - pad*5,         fontSize, "lo")

            -- Static row 2
            glText(descR2, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*5 - pad*6,         fontSize, "lo")

            -- Dynamic row 1
            glText(descL2, tipX + pad,                     tipY + th - fontSize*6 - pad*7,         fontSize, "lo")
            glText(descR3, tipX + pad + wDescLeft + pad,   tipY + th - fontSize*6 - pad*7,         fontSize, "lo")

            -- Dynamic row 2
            glText(descR4, tipX + pad + wDescLeft + pad,   tipY + pad,                             fontSize, "lo")

        end
    end
end

 
        -- DROPDOWN + HIDE BUTTON
        if metalShareDropdownOpen then
            DrawMetalShareDropdown()
        end

        DrawHideButton()
    end   -- ← closes DrawCompactOverlay() call inside DrawScreen

----------------------------------------------------------------
-- INSERT FOREGROUND TOOLTIP RENDERER HERE
----------------------------------------------------------------

-- FINAL FOREGROUND TOOLTIP DRAW
if pendingTooltip then
    local tip = pendingTooltip
    local tipX = pendingTooltipX
    local tipY = pendingTooltipY

    -- Background
    glColor(1, 1, 1, 0.92)
    glRect(tipX, tipY, tipX + tip.tw, tipY + tip.th)

    -- Border
    glColor(0, 0, 0, 0.25)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, function()
        glVertex(tipX, tipY); glVertex(tipX + tip.tw, tipY)
        glVertex(tipX + tip.tw, tipY); glVertex(tipX + tip.tw, tipY + tip.th)
        glVertex(tipX + tip.tw, tipY + tip.th); glVertex(tipX, tipY + tip.th)
        glVertex(tipX, tipY + tip.th); glVertex(tipX, tipY)
    end)

    -- Text
    glColor(0, 0, 0, 1)
    local y = tipY + tip.th - tip.pad - fontSize
    for _, line in ipairs(tip.lines) do
        glText(line, tipX + tip.pad, y, fontSize, "lo")
        y = y - (fontSize + 4)
    end

    pendingTooltip = nil
end

----------------------------------------------------------------
-- END OF INSERT
----------------------------------------------------------------
end   -- ← THIS closes widget:DrawScreen()

-- METAL INC TOOLTIP
do
    if metalIncRect then
        local mx, my = Spring.GetMouseState()
        if mx >= metalIncRect.x1 and mx <= metalIncRect.x2
        and my >= metalIncRect.y1 and my <= metalIncRect.y2 then

            local tip1 = "Metal income breakdown"
            local tip2 = "Hover for detailed sources"

            local pad = 6
            local w1 = glGetTextWidth(tip1) * fontSize
            local w2 = glGetTextWidth(tip2) * fontSize
            local tw = math.max(w1, w2) + pad * 2
            local th = fontSize * 2 + pad * 3

            -- LOWER‑RIGHT of mouse cursor, with fallback
            local tipX = mx + 18
            local tipY = my + 18

Spring.Echo(string.format("Tooltip: my=%d, th=%d, vsy=%d, tipY+th=%d, limit=%d", my, th, vsy, tipY + th, vsy - 4))

            -- If below cursor goes off bottom, place above instead
            if tipY + th > vsy - 4 then
                tipY = my - th - 18
            end
            -- Final clamp to screen bounds
            if tipY < 4 then tipY = 4 end
            if tipY + th > vsy - 4 then tipY = vsy - th - 4 end

            -- Background bubble
            glColor(1, 1, 1, 0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            -- Border
            glColor(0, 0, 0, 0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            -- Text
            glColor(0, 0, 0, 1)
            glText(tip1, tipX + tw * 0.5, tipY + th - fontSize - pad, fontSize, "oc")
            glText(tip2, tipX + tw * 0.5, tipY + pad, fontSize, "oc")
        end
    end
end

-- HELPERS FOR HIDE / UNHIDE SYSTEM
local function PointInUnhideButton(mx, my)
    local label    = "[Unhide Eco Graph]"
    local fontSize = 14 * FONT_SCALE
    local textWidth = gl.GetTextWidth(label) * fontSize

    local x = (vsx * 0.5) - (textWidth * 0.5)
    local y = vsy - 40

    return mx >= x and mx <= x + textWidth
       and my >= y - fontSize and my <= y + fontSize
end


-- INPUT HANDLING
function widget:IsAbove(mx,my)
    if fullyHidden then
        return PointInUnhideButton(mx,my)
    end

    if not showWidget then return false end
    return PointInBox(mx,my)
end

function widget:MousePress(mx, my, button)
    local alt, ctrl, meta, shift = spGetModKeyState()

    ------------------------------------------------------------
    -- 0. M:E RATIO PIN TOGGLE (FIRST PRIORITY)
    ------------------------------------------------------------
    if button == 1 and meRatioRect then
        if mx >= meRatioRect.x1 and mx <= meRatioRect.x2
        and my >= meRatioRect.y1 and my <= meRatioRect.y2 then
            meRatioPinned = not meRatioPinned
            Spring.Echo("M:E pinned:", meRatioPinned)
            return true
        end
    end

    ------------------------------------------------------------
    -- 0b. [INTEL] PIN TOGGLE (same priority as M:E)
    ------------------------------------------------------------
    if button == 1 and ppRect then
        if mx >= ppRect.x1 and mx <= ppRect.x2
        and my >= ppRect.y1 and my <= ppRect.y2 then
            intelPinned = not intelPinned
            Spring.Echo("INTEL pinned:", intelPinned)
            return true
        end
    end

    ------------------------------------------------------------
    -- 0c. [ -Xe +Xm X% ] CONVERSION STAT PIN TOGGLE (same priority)
    ------------------------------------------------------------
    if button == 1 and convStatRect then
        if mx >= convStatRect.x1 and mx <= convStatRect.x2
        and my >= convStatRect.y1 and my <= convStatRect.y2 then
            convStatPinned = not convStatPinned
            Spring.Echo("Conversion stat pinned:", convStatPinned)
            return true
        end
    end

    ------------------------------------------------------------
    -- 1. CTRL + RMB always toggles dual-line graphs
    ------------------------------------------------------------
    if ctrl and button == 3 and box then
        if mx >= box.x1 and mx <= box.x2 and my >= box.y1 and my <= box.y2 then
            hideGraphs = not hideGraphs
            Spring.SetConfigInt("eco_graph_hide_graphs", hideGraphs and 1 or 0)
            Spring.Echo("Dual-line graphs toggled:", hideGraphs)
            return true
        end
    end

    ------------------------------------------------------------
    -- 2. Toggle menu always gets first chance (AFTER M:E)
    ------------------------------------------------------------
    if EcoToggleMenu.MousePress(mx, my, button) then
        return true
    end

    ------------------------------------------------------------
    -- 3. If Eco Graph is hidden, do NOT process Eco Graph clicks
    ------------------------------------------------------------
    if not WG.EcoGraph_UIVisible then
        return false
    end

    local x1 = box.x1
    local y1 = box.y1
    local x2 = box.x2
    local y2 = box.y2
    local w  = x2 - x1
    local h  = y2 - y1
    local margin = cfg.innerMargin
    local barY = y1 + (h * margin) + 10
    local barH = 8
    local mid = x1 + w * 0.5
    local panelX1 = mid + 120
    local panelX2 = x2
    local gx1 = panelX1 + ((panelX2 - panelX1) * margin)
    local gx2 = panelX2 - ((panelX2 - panelX1) * margin)
    local barW = 140
    local barX = (gx1 + gx2) * 0.5
    local barLeft = barX - (barW * 0.5)
    local convX = barLeft + (barW * energyConversionPercent)
    local handleW = 4
    local centerX = box.x1 + (box.x2 - box.x1) * 0.5

    -- 1. FLOATING UNHIDE BUTTON
    if fullyHidden then
        local label    = "[Unhide Eco Graph]"
        local fontSize = 14 * FONT_SCALE
        local textWidth = gl.GetTextWidth(label) * fontSize
        local x         = (vsx * 0.5) - (textWidth * 0.5)
        local y         = vsy - 40

        if mx >= x and mx <= x + textWidth
        and my >= y - fontSize and my <= y + fontSize then
            fullyHidden = false
            return true
        end

        return false
    end

    -- 2. NORMAL VISIBILITY CHECKS
    if not showWidget then return false end
    if spIsGUIHidden() then return false end

    -- 3. METAL DROPDOWN OPTION CLICK
    if metalShareDropdownOpen and metalShareOptionRects then
        for i, r in ipairs(metalShareOptionRects) do
            if PointInRect(mx, my, r.x1, r.y1, r.x2, r.y2) then

                local opt = metalShareOptions[i]

                if opt == "Disable" then
                    metalShareEnabled = false
                    metalSharePercent = 0
                    metalShareDropdownOpen = false
                    if graphList then glDeleteList(graphList) graphList = nil end
                    return true
                end

                metalShareEnabled = true
                metalSharePercent = opt
                Spring.SetConfigFloat("eco_metal_share_keep_percent", metalSharePercent)

                metalShareDropdownOpen = false
                if graphList then glDeleteList(graphList) graphList = nil end
                return true
            end
        end
    end

    -- Click outside dropdown closes it
    if metalShareDropdownOpen then
        if not PointInRect(mx, my,
            metalShareButtonRect.x1,
            metalShareButtonRect.y1,
            metalShareButtonRect.x2,
            metalShareButtonRect.y2)
        then
            metalShareDropdownOpen = false
        end
    end

    -- 4. ENERGY DROPDOWN OPTION CLICK
    if energyShareDropdown and energyShareOptionRects then
        for i, r in ipairs(energyShareOptionRects) do
            if PointInRect(mx, my, r.x1, r.y1, r.x2, r.y2) then
                local opt = energyShareOptions[i]

                if opt == "Disable" then
                    energyShareEnabled = false
                    energySharePercent = 0
                else
                    energyShareEnabled = true
                    energySharePercent = opt
                end

                Spring.SetConfigFloat("eco_energy_share_percent", energySharePercent)

                energyShareDropdown = false
                return true
            end
        end

        if not PointInRect(mx, my,
            energyShareButton.x1,
            energyShareButton.y1,
            energyShareButton.x2,
            energyShareButton.y2)
        then
            energyShareDropdown = false
        end
    end

    -- 5. CLICK OUTSIDE MAIN BOX
    if not PointInBox(mx, my) then
        if metalShareDropdownOpen then
            local insideDropdown = false
            if metalShareOptionRects then
                for _, r in ipairs(metalShareOptionRects) do
                    if PointInRect(mx, my, r.x1, r.y1, r.x2, r.y2) then
                        insideDropdown = true
                        break
                    end
                end
            end

            if not insideDropdown then
                metalShareDropdownOpen = false
            end
        end

        return false
    end

    -- Pause button
    if pauseButtonRect
    and mx >= pauseButtonRect.x1 and mx <= pauseButtonRect.x2
    and my >= pauseButtonRect.y1 and my <= pauseButtonRect.y2 then
        Spring.SendCommands("pause")
        return true
    end

    -- Transparency toggle (title-bar [T]/[D] button, between Pause and
    -- [X] -- present in both compact and full view, since both draw
    -- blocks set this rect the same way). Own flag/config key for the
    -- main/attached window -- independent of the detached dual-line
    -- graph's own transparency toggle.
    if mainTransparentToggleRect
    and mx >= mainTransparentToggleRect.x1 and mx <= mainTransparentToggleRect.x2
    and my >= mainTransparentToggleRect.y1 and my <= mainTransparentToggleRect.y2 then
        widget._transparentMode = not widget._transparentMode
        Spring.SetConfigInt("eco_graph_transparent_mode", widget._transparentMode and 1 or 0)
        if graphList then glDeleteList(graphList) graphList = nil end
        return true
    end

    -- 6. CLOSE BUTTON
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = gl.GetTextWidth(hideLabel) * hideSize
    local hx1       = box.x2 - hideWidth - 6 - (widget._topAddonMode and 20 or 0)  -- Round 8: matches DrawHideButton()'s own addon-mode extra left margin
    -- /ecographtopbaraddon: matches DrawHideButton()'s own addon-mode Y
    -- (bottom-right corner) so the click target tracks where [X] is
    -- actually drawn in this mode.
    local hy1       = widget._topAddonMode and (box.y1 + 12) or (box.y2 - 20)

    if mx >= hx1 and mx <= hx1 + hideWidth
    and my >= hy1 - hideSize and my <= hy1 + hideSize then
        WG.EcoGraph_ToggleUI()
        return true
    end

    -- 7. COMPACT TOGGLE
    if button == 1 and ctrl then
        compactMode = not compactMode
        if graphList then glDeleteList(graphList) graphList = nil end
        return true
    end

    -- 8. PAUSE / RESET
    if button == 2 then
        if ctrl then
            ResetHistory()
        else
            paused = not paused
        end
        return true
    end

    -- 9. METAL SHARE BUTTON
    if button == 1 then
        local bx1 = metalShareButtonRect.x1
        local by1 = metalShareButtonRect.y1
        local bx2 = metalShareButtonRect.x2
        local by2 = metalShareButtonRect.y2

        if bx1 and by1 and bx2 and by2 then
            if PointInRect(mx, my, bx1, by1, bx2, by2) then
                metalShareDropdownOpen = not metalShareDropdownOpen
                return true
            end
        end
    end

    -- ENERGY SHARE BUTTON
    if button == 1 then
        if PointInRect(mx, my,
            energyShareButton.x1,
            energyShareButton.y1,
            energyShareButton.x2,
            energyShareButton.y2)
        then
            energyShareDropdown = not energyShareDropdown
            metalShareDropdownOpen = false
            return true
        end
    end

    ------------------------------------------------------------
    -- HISTORY SECONDS SELECTOR CLICK
    ------------------------------------------------------------
    do
        local centerX = box.x1 + (box.x2 - box.x1) * 0.5
        local hx1 = centerX + 220
        local hx2 = box.x2 - 10
        local hy1 = box.y1 + 30
        local hy2 = hy1 + 20

        if mx >= hx1 and mx <= hx2 and my >= hy1 and my <= hy2 then
            local opts  = cfg.historyOptions
            local count = #opts
            local w     = (hx2 - hx1) / count

            for i = 1, count do
                local x1 = hx1 + (i-1)*w
                local x2 = x1 + w
                if mx >= x1 and mx <= x2 then
                    cfg.historySeconds = opts[i]
                    Spring.SetConfigInt("eco_graph_history_seconds", cfg.historySeconds)

                    if graphList then
                        glDeleteList(graphList)
                        graphList = nil
                    end

                    return true
                end
            end
        end
    end

    ------------------------------------------------------------
    -- BACKGROUND MODE TOGGLE CLICK (Default <-> Transparent)
    -- Only live outside compactMode -- that's the only view that
    -- draws it (BuildGraphList clears the rect while compact).
    ------------------------------------------------------------
    if not compactMode and button == 1 and widget._bgToggleRect then
        local r = widget._bgToggleRect
        if mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2 then
            widget._transparentMode = not widget._transparentMode
            Spring.SetConfigInt("eco_graph_transparent_mode", widget._transparentMode and 1 or 0)

            if graphList then
                glDeleteList(graphList)
                graphList = nil
            end

            return true
        end
    end

    ------------------------------------------------------------
    -- AUTO‑SHARE SLIDER CLICK (Compact View)
    ------------------------------------------------------------
    if compactMode and button == 1 then
        -- METAL slider
        local r = shareIndicatorArea["metal"]
        if r and r[1] and r[2] and r[3] and r[4] then
            if mx >= r[1] and mx <= r[3] and my >= r[2] and my <= r[4] then
                draggingShareIndicator = "metal"
                return true
            end
        end

        -- ENERGY slider
        local r2 = shareIndicatorArea["energy"]
        if r2 and r2[1] and r2[2] and r2[3] and r2[4] then
            if mx >= r2[1] and mx <= r2[3] and my >= r2[2] and my <= r2[4] then
                draggingShareIndicator = "energy"
                return true
            end
        end

        -- ENERGY → METAL conversion slider (Compact View)
        if conversionIndicatorArea and conversionIndicatorArea[1] then
            if mx >= conversionIndicatorArea[1]
            and mx <= conversionIndicatorArea[3]
            and my >= conversionIndicatorArea[2]
            and my <= conversionIndicatorArea[4] then

                draggingConversionIndicator = true

                -- store drag offset so thumb doesn't jump
                dragOffsetX_conv = mx - ((conversionIndicatorArea[1] + conversionIndicatorArea[3]) * 0.5)

                return true
            end
        end

    end

    -- 11. RESIZE HANDLE
    if button == 1 and PointInResizeHandle(mx, my) and not dragLocked then
        resizing     = true
        resizeStartX = mx
        resizeStartY = my
        return true
    end

    -- 12. DRAGGING
    if button == 1 and not dragLocked then
        dragging    = true
        dragOffsetX = mx - box.x1
        dragOffsetY = my - box.y1
        return true
    end

    return false
end



function widget:MouseMove(mx, my, dx, dy, button)

    -- 1. Toggle menu always gets mouse move
    EcoToggleMenu.MouseMove(mx, my)

    -- 2. If Eco Graph is hidden, stop here
    if not WG.EcoGraph_UIVisible then
        return
    end

------------------------------------------------------------
-- AUTO‑SHARE SLIDER DRAGGING (Compact View)
------------------------------------------------------------
if compactMode and draggingShareIndicator then
    local res = draggingShareIndicator

    -- get bar geometry
    local barX1, barX2
    if res == "metal" then
        barX1 = box.x1 + 170 + metalOffset
        barX2 = (box.x1 + (box.x2 - box.x1) * 0.5) - 270 + metalOffset
    else
        -- ENERGY uses global energyOffset
        barX1 = (box.x1 + (box.x2 - box.x1) * 0.5) + 265 + energyOffset
        barX2 = box.x2 - 150 + energyOffset
    end

    local barWidth = barX2 - barX1

    -- convert mouse X → share value
    local shareValue = (mx - barX1) / barWidth
    if shareValue < 0 then shareValue = 0 end
    if shareValue > 1 then shareValue = 1 end

    draggingShareIndicatorValue[res] = shareValue
    Spring.SetShareLevel(res, shareValue)

    return true
end

------------------------------------------------------------
-- ENERGY → METAL CONVERSION SLIDER DRAGGING (BEIGE)
------------------------------------------------------------
if compactMode and draggingConversionIndicator then

    -- MATCH DRAWING GEOMETRY EXACTLY
    local barX1 = (box.x1 + (box.x2 - box.x1) * 0.5) + 265 + energyOffset
    local barX2 = box.x2 - 150 + energyOffset
    local barWidth = barX2 - barX1

    -- mouse X → mmLevel (0 on left, 1 on right)
    local mm = (mx - barX1) / barWidth
    if mm < 0 then mm = 0 end
    if mm > 1 then mm = 1 end

    -- clamp to 10%–90% keep (same visual limits as Top Bar)
    if mm < 0.10 then mm = 0.10 end
    if mm > 0.90 then mm = 0.90 end

    draggingConversionIndicatorValue = mm

    -- engine treats this as "percent to KEEP"
    local convValue = math.floor(mm * 100 + 0.5)
    Spring.SendLuaRulesMsg(string.format("%c%i", 137, convValue))

    return true
end

    ------------------------------------------------------------
    -- FREEFORM RESIZING. This resizes the main Eco Graph Window.
    ------------------------------------------------------------
    if resizing and button == 1 then
        local w = mx - box.x1

        local minW = vsx * 0.15 -- Original 0.45, then 0.40 - Minimum horizonal width of the main Eco Graph allowed.
        -- Round 18: in Top-Bar addon mode, [Pause]/[A]/[D]/[X] (anchored
        -- off box.x2) and [INTEL]/[M:E] (anchored off box.x1) share the
        -- SAME row -- unlike normal mode, where they're on different
        -- rows -- with no collision-avoidance between the two groups.
        -- Resizing narrower than ~350-400px let them visually overlap.
        -- Raise the floor specifically in addon mode so that can't
        -- happen; normal mode is untouched since it was never at risk
        -- (different rows there). 420 is a conservative estimate, not
        -- yet checked pixel-for-pixel against the real font in-game --
        -- see widget.ToggleTopBarAddonMode()'s own matching clamp on
        -- widget._addonWidth (same literal, duplicated rather than a
        -- shared constant -- see that site's own comment why).
        if widget._topAddonMode then
            minW = math.max(minW, 420)
        end
        local maxW = vsx * 0.95
        if w < minW then w = minW end
        if w > maxW then w = maxW end

        local top = box.y2
        local h   = top - my

        local minH = vsy * 0.050 --original 0.033  Vertical minimum  height of the main Eco Graph allowed.
        local maxH = vsy * 0.90
        if h < minH then h = minH end
        if h > maxH then h = maxH end

        box.y1 = top - h
        box.y2 = top

        box.x2 = box.x1 + w

        cfg.width  = w / vsx
        cfg.height = h / vsy

        if graphList then glDeleteList(graphList) graphList = nil end
        BuildGraphList()
        return true
    end

    ------------------------------------------------------------
    -- DRAGGING THE WHOLE WIDGET
    ------------------------------------------------------------
    if dragging and button == 1 then
        cfg.anchorX = (mx - dragOffsetX) / vsx
        cfg.anchorY = (my - dragOffsetY) / vsy

        local w = box.x2 - box.x1
        local h = box.y2 - box.y1

        local newX1 = mx - dragOffsetX
        local newY1 = my - dragOffsetY
        local newX2 = newX1 + w
        local newY2 = newY1 + h

        if newX1 < 0   then newX1 = 0;   newX2 = w      end
        if newY1 < 0   then newY1 = 0;   newY2 = h      end
        if newX2 > vsx then newX2 = vsx; newX1 = vsx-w  end
        if newY2 > vsy then newY2 = vsy; newY1 = vsy-h  end

        box.x1, box.y1, box.x2, box.y2 = newX1, newY1, newX2, newY2
        cfg.anchorX = (box.x1 + w*0.5) / vsx
        cfg.anchorY = box.y1 / vsy

        if graphList then glDeleteList(graphList) graphList = nil end
        BuildGraphList()
        return true
    end
end


function widget:MouseRelease(mx, my, button)

    -- 1. Toggle menu always gets first chance
    if EcoToggleMenu.MouseRelease(mx, my, button) then
        return true
    end

    -- 2. If Eco Graph is hidden, stop here
    if not WG.EcoGraph_UIVisible then
        return false
    end

    ------------------------------------------------------------
    -- AUTO‑SHARE SLIDER RELEASE (Compact View)
    ------------------------------------------------------------
    if compactMode and draggingShareIndicator and button == 1 then
        draggingShareIndicator = nil
        return true
    end

    ------------------------------------------------------------
    -- ENERGY → METAL CONVERSION SLIDER RELEASE (BEIGE)
    ------------------------------------------------------------
    if compactMode and draggingConversionIndicator and button == 1 then
        draggingConversionIndicator = false
        return true
    end

    ------------------------------------------------------------
    -- STOP RESIZING
    ------------------------------------------------------------
    if resizing and button == 1 then
        resizing = false

        Spring.SetConfigFloat("eco_graph_w", cfg.width)
        Spring.SetConfigFloat("eco_graph_h", cfg.height)

        return true
    end

    ------------------------------------------------------------
    -- STOP DRAGGING WIDGET
    ------------------------------------------------------------
    if dragging and button == 1 then
        dragging = false

        Spring.SetConfigFloat("eco_graph_x", cfg.anchorX)
        Spring.SetConfigFloat("eco_graph_y", cfg.anchorY)

        return true
    end
end


-- HOTKEYS
function widget:KeyPress(key, mods)
    local ctrl = mods.ctrl

    -- Show/hide widget
    if ctrl and key == string.byte(";") then
        showWidget = not showWidget
        return true
    end

    -- Compact/full toggle
    if ctrl and key == string.byte("'") then
        compactMode = not compactMode
        if graphList then glDeleteList(graphList) graphList = nil end
        return true
    end

    -- Lock/unlock dragging and resizing
    if ctrl and (key == string.byte("l") or key == string.byte("L")) then
        dragLocked = not dragLocked
        dragging   = false
        resizing   = false
        return true
    end
end

-- STATE -----------------------------------------------------------------------
local detached = {
    visible = false,
    x1 = 0, y1 = 0,
    x2 = 0, y2 = 0,
    dragging = false,
    resizing = false,
    dragOffsetX = 0,
    dragOffsetY = 0,
    resizeStartX = 0,
    resizeStartY = 0,
    -- Round 13: "stuck" (magnet) mode -- while true, dragging EITHER the
    -- main window or the detached window shifts the other by the same
    -- delta, so they move together without merging into one window. Set
    -- by the "^" button (detached.AttachBelowMain()), cleared by the "v"
    -- button that replaces it while stuck.
    stuck = false,
}

-- DEFAULT SIZE (relative to screen)
local DETACHED_DEFAULT_W = 0.22   -- 22% of screen width
local DETACHED_DEFAULT_H = 0.32   -- 32% of screen height

-- RESIZE HANDLE SIZE
local DETACHED_RESIZE = 16

-- LOAD SAVED POSITION ---------------------------------------------------------
local function Detached_Load()
    local vsx, vsy = Spring.GetViewGeometry()

local savedVisible = Spring.GetConfigInt("eco_detached_visible", 0)
detached.visible = (savedVisible == 1)
widget._detachedVisible = detached.visible

detached.stuck = Spring.GetConfigInt("eco_detached_stuck", 0) == 1

    local savedX = Spring.GetConfigFloat("eco_detached_x", -1)
    local savedY = Spring.GetConfigFloat("eco_detached_y", -1)
    local savedW = Spring.GetConfigFloat("eco_detached_w", -1)
    local savedH = Spring.GetConfigFloat("eco_detached_h", -1)

    local w = (savedW > 0) and savedW or (vsx * DETACHED_DEFAULT_W)
    local h = (savedH > 0) and savedH or (vsy * DETACHED_DEFAULT_H)

    -- Default spawn: right side, vertically centered
    local x = (savedX > 0) and savedX or (vsx * 0.70)
    local y = (savedY > 0) and savedY or ((vsy * 0.50) - (h * 0.50))

    detached.x1 = x
    detached.y1 = y
    detached.x2 = x + w
    detached.y2 = y + h
end

-- SAVE POSITION ---------------------------------------------------------------
local function Detached_Save()
    local w = detached.x2 - detached.x1
    local h = detached.y2 - detached.y1

    Spring.SetConfigFloat("eco_detached_x", detached.x1)
    Spring.SetConfigFloat("eco_detached_y", detached.y1)
    Spring.SetConfigFloat("eco_detached_w", w)
    Spring.SetConfigFloat("eco_detached_h", h)
end

-- Re-centers the detached window on the CURRENT screen, keeping its
-- existing size. Exists for /ecographcenter -- same reasoning as
-- EcoToggleMenu.Center() above: a saved position from a wider screen can
-- leave this window off-screen on a smaller one, with nothing to drag
-- because there's nothing visible to click.
function detached.Center()
    local vsx, vsy = Spring.GetViewGeometry()
    local w = detached.x2 - detached.x1
    local h = detached.y2 - detached.y1

    detached.x1 = (vsx - w) * 0.5
    detached.y1 = (vsy - h) * 0.5
    detached.x2 = detached.x1 + w
    detached.y2 = detached.y1 + h

    Detached_Save()
end

-- "^" RE-ATTACH + STICK: docks the detached window directly below the
-- main window, horizontally centered under it, keeping its existing
-- size, and turns on "stuck" (magnet) mode -- see the `detached.stuck`
-- comment on the table above. Reads `box` (the main window's own live
-- geometry) directly, so this works the same whether the main window is
-- in its normal height or shrunk down via /ecographtopbaraddon --
-- box.x1/x2/y1 always reflect whatever the main window's current
-- position/size actually is, no special-casing needed for either mode.
-- (box.y1 is the main window's BOTTOM edge in this coordinate system --
-- see the FREEFORM RESIZING block's own "local top = box.y2" convention
-- -- so "below" means just under box.y1, not box.y2.)
function detached.AttachBelowMain()
    local vsx, vsy = Spring.GetViewGeometry()
    local w = detached.x2 - detached.x1
    local h = detached.y2 - detached.y1
    local gap = 6

    local mainCenterX = (box.x1 + box.x2) * 0.5

    local newX1 = mainCenterX - w * 0.5
    local newY2 = box.y1 - gap
    local newY1 = newY2 - h

    -- Keep it on-screen if the main window is sitting near the bottom
    -- edge and there isn't room below it for the detached window's own
    -- height -- same screen-bounds clamping style as the DRAGGING THE
    -- WHOLE WIDGET block above.
    if newY1 < 0 then
        newY1 = 0
        newY2 = h
    end
    if newX1 < 0 then
        newX1 = 0
    elseif newX1 + w > vsx then
        newX1 = vsx - w
    end

    detached.x1 = newX1
    detached.y1 = newY1
    detached.x2 = newX1 + w
    detached.y2 = newY2

    detached.stuck = true
    Spring.SetConfigInt("eco_detached_stuck", 1)

    Detached_Save()
end

-- "v" UNSTICK: turns off magnet mode. Doesn't move either window --
-- they stay exactly where they are, just stop following each other.
function detached.Unstick()
    detached.stuck = false
    Spring.SetConfigInt("eco_detached_stuck", 0)
end

-- GEOMETRY HELPERS ------------------------------------------------------------
local function Detached_PointIn(mx, my)
    return mx >= detached.x1 and mx <= detached.x2
       and my >= detached.y1 and my <= detached.y2
end

local function Detached_PointInResize(mx, my)
    return mx >= detached.x2 - DETACHED_RESIZE and mx <= detached.x2
       and my >= detached.y1 and my <= detached.y1 + DETACHED_RESIZE
end

--------------------------------------------------------------------------------
-- STATS ROW (Metal / Energy, Option B style)
--------------------------------------------------------------------------------
local function Detached_DrawStatsRow()
    local x1, y1, x2, y2 = detached.x1, detached.y1, detached.x2, detached.y2
    local mid = (x1 + x2) * 0.5
    local statsY = y2 - 18

    local metalStatsX  = (x1 + mid) * 0.5
    local energyStatsX = (mid + x2) * 0.5

    local mInc = smoothMetalIncome or 0
    local mUse = smoothMetalUsage or 0
    local eInc = smoothEnergyIncome or 0
    local eUse = smoothEnergyUsage or 0

    -- Metal stats (same helper as Compact Mode)
    DrawPanelStats(
        "Metal",
        mInc,
        mUse,
        metalStatsX,
        statsY,
        cfg.metalIncomeColor,
        cfg.metalUsageColor
    )

    -- Energy stats
    DrawPanelStats(
        "Energy",
        eInc,
        eUse,
        energyStatsX,
        statsY,
        cfg.energyIncomeColor,
        cfg.energyUsageColor
    )

    --------------------------------------------------------------------
    -- DETACHED TOOLTIP HITBOXES (Metal + Energy)
    --------------------------------------------------------------------
    do
        -- Metal hitbox
        local mUseStr = "Use: " .. FormatIncome(mUse)
        local mIncStr = "Income: " .. FormatIncome(mInc)
        local mNetStr = "Net: " .. FormatIncome(mInc - mUse)

        local mUseW = glGetTextWidth(mUseStr) * fontSize
        local mIncW = glGetTextWidth(mIncStr) * fontSize
        local mNetW = glGetTextWidth(mNetStr) * fontSize
        local pad   = 10
        local totalW = mUseW + pad + mIncW + pad + mNetW

        local leftX = metalStatsX - (totalW * 0.5)
        local y1 = statsY - fontSize
        local y2 = statsY + fontSize

        detached.metalIncRect = widget._setRect(detached.metalIncRect, leftX, y1, leftX + totalW, y2)

        -- Energy hitbox
        local eUseStr = "Use: " .. FormatIncome(eUse)
        local eIncStr = "Income: " .. FormatIncome(eInc)
        local eNetStr = "Net: " .. FormatIncome(eInc - eUse)

        local eUseW = glGetTextWidth(eUseStr) * fontSize
        local eIncW = glGetTextWidth(eIncStr) * fontSize
        local eNetW = glGetTextWidth(eNetStr) * fontSize

        totalW = eUseW + pad + eIncW + pad + eNetW
        leftX = energyStatsX - (totalW * 0.5)

        detached.energyIncRect = widget._setRect(detached.energyIncRect, leftX, y1, leftX + totalW, y2)
    end


    -- "^" / "v" RE-ATTACH + STICK BUTTON: centered between the two stat
    -- groups, same row as Income/Net (same `mid` X the two stat groups
    -- are built around above). Round 13: while NOT stuck, shows "^" --
    -- click docks this window directly below the main window, centered
    -- under it, and turns on magnet (stuck) mode -- see
    -- detached.AttachBelowMain(). While stuck, shows "v" instead --
    -- click turns magnet mode back off (detached.Unstick()) without
    -- moving either window.
    do
        local attachLabel = detached.stuck and "v" or "^"
        local attachSize  = 14 * FONT_SCALE
        local attachW     = glGetTextWidth(attachLabel) * attachSize

        glColor(cfg.titleColor)
        glText(attachLabel, mid, statsY, attachSize, "oc")

        local pad = 4
        detached.attachX1 = mid - attachW * 0.5 - pad
        detached.attachY1 = statsY - attachSize
        detached.attachX2 = mid + attachW * 0.5 + pad
        detached.attachY2 = statsY + attachSize
    end


    -- Optional: [X] close button on far right of stats row
    local closeLabel = "[X]"
    local closeSize  = 12 * FONT_SCALE
    local closeW     = glGetTextWidth(closeLabel) * closeSize
    local closeX     = x2 - 6 - closeW * 0.5
    local closeY     = statsY

    glColor(cfg.titleColor)
    glText(closeLabel, closeX, closeY, closeSize, "oc")
    -- NOTE: if you want this clickable, you can hook it in MousePress

    -- Save hitbox for click detection
    detached.closeX1 = closeX - closeW * 0.5
    detached.closeY1 = closeY - closeSize
    detached.closeX2 = closeX + closeW * 0.5
    detached.closeY2 = closeY + closeSize

end

--------------------------------------------------------------------------------
-- DUAL-LINE GRAPH HELPERS (Metal / Energy, Compact-style)
--------------------------------------------------------------------------------

local function Detached_DrawMetalGraph()
    
    local data = history.metal
    if not data or #data < 2 then return end

    local x1, y1, x2, y2 = detached.x1, detached.y1, detached.x2, detached.y2
    local centerX = x1 + (x2 - x1) * 0.5

    -- Horizontal: 3% outer margin, center gap (left half)
    -- Center gap reduced by 1/3 twice (0.07 -> 0.0467 -> 0.0311 per side)
    local gx1 = x1 + (x2 - x1) * 0.03
    local gx2 = centerX - (x2 - x1) * 0.0311

    -- Vertical: from bottom + small pad to below stats row
    local bottomPad = 10
    local topPad    = 40
    local gy1 = y1 + bottomPad
    local gy2 = y2 - topPad

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1

    -- BACKGROUND
    -- Follows the detached window's OWN Default/Transparent toggle
    -- (0.25 default, 0 transparent) instead of a fixed value -- a flat
    -- always-dark box looked worse floating inside an otherwise see-
    -- through window than just letting it go fully transparent too.
    -- Independent of the main/attached window's transparency flag.
    glColor(0, 0, 0, widget._detachedTransparentMode and 0 or 0.25)
    glRect(gx1, gy1, gx2, gy2)

    -- SCALE VALUES (same as Compact / Full)
    local maxT = data[#data].t
    local minT = maxT - cfg.historySeconds

    local minV, maxV = math.huge, -math.huge
    for i = 1, #data do
        local s = data[i]
        if s.income < minV then minV = s.income end
        if s.usage  < minV then minV = s.usage  end
        if s.income > maxV then maxV = s.income end
        if s.usage  > maxV then maxV = s.usage  end
    end

    if minV == maxV then
        maxV = maxV + 1
        minV = minV - 1
    end

    local padding = (maxV - minV) * cfg.yPaddingFraction
    minV = minV - padding
    maxV = maxV + padding

    local rangeV = maxV - minV
    local rangeT = cfg.historySeconds

    -- ZERO LINE
    local zeroY = gy1 + gh * ((0 - minV) / rangeV)
    glColor(cfg.gridColor)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, widget._zeroLineVerts, gx1, zeroY, gx2)

    -- INCOME CURVE
    glColor(cfg.metalIncomeColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, true)

    -- USAGE CURVE
    glColor(cfg.metalUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, false)
end

local function Detached_DrawEnergyGraph()
    local data = history.energy
    if not data or #data < 2 then return end

    local x1, y1, x2, y2 = detached.x1, detached.y1, detached.x2, detached.y2
    local centerX = x1 + (x2 - x1) * 0.5

    -- Horizontal: center gap, 3% margin from right (right half)
    -- Center gap reduced by 1/3 twice (0.07 -> 0.0467 -> 0.0311 per side)
    local gx1 = centerX + (x2 - x1) * 0.0311
    local gx2 = x2 - (x2 - x1) * 0.03

    -- Vertical: from bottom + small pad to below stats row
    local bottomPad = 10
    local topPad    = 40
    local gy1 = y1 + bottomPad
    local gy2 = y2 - topPad

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1

    -- BACKGROUND
    -- Follows the detached window's OWN Default/Transparent toggle --
    -- see the matching comment in Detached_DrawMetalGraph() above.
    glColor(0, 0, 0, widget._detachedTransparentMode and 0 or 0.25)
    glRect(gx1, gy1, gx2, gy2)

    -- SCALE VALUES
    local maxT = data[#data].t
    local minT = maxT - cfg.historySeconds

    local minV, maxV = math.huge, -math.huge
    for i = 1, #data do
        local s = data[i]
        if s.income < minV then minV = s.income end
        if s.usage  < minV then minV = s.usage  end
        if s.income > maxV then maxV = s.income end
        if s.usage  > maxV then maxV = s.usage  end
    end

    if minV == maxV then
        maxV = maxV + 1
        minV = minV - 1
    end

    local padding = (maxV - minV) * cfg.yPaddingFraction
    minV = minV - padding
    maxV = maxV + padding

    local rangeV = maxV - minV
    local rangeT = cfg.historySeconds

    -- ZERO LINE
    local zeroY = gy1 + gh * ((0 - minV) / rangeV)
    glColor(cfg.gridColor)
    glLineWidth(1.0)
    glBeginEnd(GL_LINES, widget._zeroLineVerts, gx1, zeroY, gx2)

    -- INCOME CURVE
    glColor(cfg.energyIncomeColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, true)

    -- USAGE CURVE
    glColor(cfg.energyUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, widget._curveVerts, data, gx1, gw, gy1, gh, minT, rangeT, minV, rangeV, false)
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — HISTORY SECONDS SELECTOR (Exact same position as main)
--------------------------------------------------------------------------------
local function Detached_DrawHistorySelector()
    local x1, y1, x2, y2 = detached.x1, detached.y1, detached.x2, detached.y2
    local w = x2 - x1
    local h = y2 - y1

    -- EXACT same relative placement as main Eco Graph (D‑1)
    local centerX = x1 + w * 0.5

    ------------------------------------------------------------------------
    -- FIXED-WIDTH HISTORY SELECTOR (matches Energy dual-line graph width)
    ------------------------------------------------------------------------
    -- These are the SAME gx1/gx2 used by Detached_DrawEnergyGraph()
    local gx1 = centerX + (x2 - x1) * 0.07
    local gx2 = x2 - (x2 - x1) * 0.03

    -- History selector uses EXACT same width as Energy graph
    local hx1 = gx1
    local hx2 = gx2

    -- Vertical placement (unchanged)
    local hy1 = y1 + 8  --- vertial position of the history selector in detach window. it was + 30
    local hy2 = hy1 + 20

    -- Background
    glColor(0, 0, 0, 0.25)
    glRect(hx1, hy1, hx2, hy2)

    -- Options
    local opts  = cfg.historyOptions
    local count = #opts
    local wOpt  = (hx2 - hx1) / count

    for i = 1, count do
        local xA = hx1 + (i-1)*wOpt
        local xB = xA + wOpt
        local sec = opts[i]

        -- Highlight selected
        if sec == cfg.historySeconds then
            glColor(1,1,1,0.15)
            glRect(xA, hy1, xB, hy2)
        end


        -- Text
        -- glColor(1,1,1,1)  -- 20s 30s 40s 
        glColor(1,1,1,0.70) -- 20s 30s 40s 50s 60s brightness of the history selector in detach
        glText(sec.."s", xA + wOpt*0.5, hy1 + 3, 11 * FONT_SCALE, "oc")
    end

    -- Save hitbox for click detection
    detached.histX1 = hx1
    detached.histY1 = hy1
    detached.histX2 = hx2
    detached.histY2 = hy2
end

--------------------------------------------------------------------------------
-- MAIN DRAW FOR DETACHED WINDOW
--------------------------------------------------------------------------------
local function Detached_Draw()
    if not detached.visible then return end

    local x1, y1, x2, y2 = detached.x1, detached.y1, detached.x2, detached.y2

    -- Background (0.80 is this window's own original opacity -- kept as
    -- the "Default" value; drops to 0 when THIS window's own background-
    -- mode toggle is set to Transparent -- independent of the main/
    -- attached window's transparency flag)
    if widget._barSkinUi and not widget._detachedTransparentMode and WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
        -- Same Top Bar overlap hiding as the attached/compact window
        -- above -- the detached window can just as easily be dragged on
        -- top of Top Bar, and uses this identical FlowUI skin. Round 23:
        -- opaque backing drawn FIRST, behind FlowUI's own panel, so the
        -- skin's texture/gradient still shows on top instead of being
        -- flattened by it.
        if GetTopBarOverlap(x1, y1, x2, y2) then
            -- Round 32: same darkened-again warm-brown backing as the
            -- attached/compact window above (same 0.90 opacity, darker
            -- color).
            glColor(0.30, 0.25, 0.19, 0.90)
            glRect(x1, y1, x2, y2)
        end

        glColor(1, 1, 1, 1)
        WG.FlowUI.Draw.Element(x1, y1, x2, y2, 0, 0, 1, 1, nil, nil, nil, nil, nil, nil, nil, nil)
    elseif widget._barSkin and not widget._detachedTransparentMode then
        glBeginEnd(GL.TRIANGLE_FAN, widget._barSkinPanelVerts, x1, y1, x2, y2, 10,
            0.22, 0.07, 0.05, 0.80,
            0.04, 0.02, 0.02, 0.80)

        glColor(0.55, 0.32, 0.16, 0.75)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, widget._barSkinBorderVerts, x1, y1, x2, y2, 10)
    else
        glColor(0, 0, 0, widget._detachedTransparentMode and 0 or 0.80)
        glRect(x1, y1, x2, y2)

        -- Border
        glColor(1,1,1,0.4)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, widget._rectBorderVerts, x1, y1, x2, y2)
    end

    -- Clip to detached window
    gl.Scissor(true)
    gl.Scissor(x1, y1, x2 - x1, y2 - y1)


    -- Dual-line graphs (left/right)
    Detached_DrawMetalGraph()
    Detached_DrawEnergyGraph()
    Detached_DrawHistorySelector()

    ----------------------------------------------------------------------
    -- BACKGROUND MODE TOGGLE -- this window's OWN flag
    -- (widget._detachedTransparentMode), independent of the main/
    -- attached window's toggle -- each window can be set transparent or
    -- opaque on its own. Drawn inline rather than as its own local
    -- function -- this file's main chunk is already at Lua's 200-local
    -- ceiling. Sits in the narrow strip neither graph draws into (the
    -- same gap Detached_DrawMetalGraph/EnergyGraph leave empty between
    -- their gx2/gx1).
    ----------------------------------------------------------------------
    do
        local centerX = x1 + (x2 - x1) * 0.5
        local bottomPad = 10
        local topPad    = 40
        local gy1 = y1 + bottomPad
        local gy2 = y2 - topPad

        local gapHalf  = (x2 - x1) * 0.0311   -- matches the graphs' own gap math
        local tgW, tgH = 20, 18

        if gapHalf * 2 < tgW + 4 then
            -- Window resized too narrow to fit the button without
            -- overlapping a graph -- skip drawing it rather than crowd things.
            widget._detachedBgToggleRect = nil
        else
            local tgX1 = centerX - tgW * 0.5
            local tgX2 = centerX + tgW * 0.5
            local tgCenterY = (gy1 + gy2) * 0.5
            local tgY1 = tgCenterY - tgH * 0.5
            local tgY2 = tgCenterY + tgH * 0.5

            widget._detachedBgToggleRect = widget._setRect(widget._detachedBgToggleRect, tgX1, tgY1, tgX2, tgY2)

            glColor(0, 0, 0, widget._detachedTransparentMode and 0.35 or 0.55)
            glRect(tgX1, tgY1, tgX2, tgY2)

            glColor(1, 1, 1, 0.45)
            glLineWidth(1)
            glBeginEnd(GL_LINES, widget._rectBorderVerts, tgX1, tgY1, tgX2, tgY2)

            glColor(1, 1, 1, 0.9)
            glText(widget._detachedTransparentMode and "T" or "D", centerX, tgCenterY - 3, 10, "oc")
        end
    end

    -- Stats row at top (Metal / Energy, Option B style)
    Detached_DrawStatsRow()

    -- Disable scissor before drawing tooltips so tooltips may overflow
    -- the detached window borders instead of being clipped.
    gl.Scissor(false)

    --------------------------------------------------------------------
    -- DETACHED TOOLTIP DRAWING (Metal + Energy)
    --------------------------------------------------------------------
    do
        local mx, my = Spring.GetMouseState()

        local function ComputeTooltipPosition(mx, my, tw, th)
            local tipX = mx + 18
            local tipY = my - th - 18

            if tipX + tw > vsx then
                tipX = mx - tw - 18
            end
            if tipX < 4 then tipX = 4 end

            if tipY < 4 then
                tipY = my + 18
            end
            if tipY + th > vsy - 4 then
                tipY = my - th - 18
            end

            if tipY < 4 then tipY = 4 end
            if tipY + th > vsy - 4 then tipY = vsy - th - 4 end

            return tipX, tipY
        end

        -- Metal tooltip
        local r = detached.metalIncRect
        if r and mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2 then
            -- Reuse the main Metal tooltip logic
            -- (same code used in compact/full view)
            local rawTotal = (smoothMexIncome or 0)
                           + (smoothConversionIncome or 0)
                           + (smoothOtherIncome or 0)

            local label1 = "Mexes"
            local label2 = "E-Conv"
            local label3 = "Other"
            local label4 = "Raw Total"

            local value1 = string.format("= %6.1f", smoothMexIncome or 0)
            local value2 = string.format("= %6.1f", smoothConversionIncome or 0)
            local value3 = string.format("= %6.1f", smoothOtherIncome or 0)
            local value4 = string.format("= %6.1f", rawTotal)

            local pad = 6
            local labelW = math.max(
                glGetTextWidth(label1),
                glGetTextWidth(label2),
                glGetTextWidth(label3),
                glGetTextWidth(label4)
            ) * fontSize

            local valueW = math.max(
                glGetTextWidth(value1),
                glGetTextWidth(value2),
                glGetTextWidth(value3),
                glGetTextWidth(value4)
            ) * fontSize

            local tw = (labelW + valueW + pad * 3) * 1.5
            local th = fontSize * 4 + pad * 5

            local tipX = mx + 18
            local tipY = my + 18
            -- If below cursor goes off bottom, place above instead
            if tipY + th > vsy - 4 then
                tipY = my - th - 18
            end
            -- Final clamp to screen bounds
            if tipY < 4 then tipY = 4 end
            if tipY + th > vsy - 4 then tipY = vsy - th - 4 end

            glColor(1,1,1,0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            glColor(0,0,0,0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            glColor(0,0,0,1)
            glText(label1, tipX + pad, tipY + th - fontSize - pad, fontSize, "lo")
            glText(value1, tipX + tw - pad, tipY + th - fontSize - pad, fontSize, "ro")

            glText(label2, tipX + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")
            glText(value2, tipX + tw - pad, tipY + th - fontSize*2 - pad*2, fontSize, "ro")

            glText(label3, tipX + pad, tipY + th - fontSize*3 - pad*3, fontSize, "lo")
            glText(value3, tipX + tw - pad, tipY + th - fontSize*3 - pad*3, fontSize, "ro")

            glText(label4, tipX + pad, tipY + pad, fontSize, "lo")
            glText(value4, tipX + tw - pad, tipY + pad, fontSize, "ro")
        end

        -- Energy tooltip
        r = detached.energyIncRect
        if r and mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2 then
            local label1 = "Static Generators"
            local label2 = "Dynamic Generators"
            local label3 = "Total"

            local value1 = string.format("= %6.1f", smoothEnergyGen or 0)
            local value2 = string.format("= %6.1f", smoothEnergyReclaim or 0)
            local value3 = string.format("= %6.1f", (smoothEnergyGen or 0) + (smoothEnergyReclaim or 0))

            local pad = 6
            local labelW = math.max(
                glGetTextWidth(label1),
                glGetTextWidth(label2),
                glGetTextWidth(label3)
            ) * fontSize

            local valueW = math.max(
                glGetTextWidth(value1),
                glGetTextWidth(value2),
                glGetTextWidth(value3)
            ) * fontSize

            local tw = labelW + valueW + pad * 3
            local th = fontSize * 3 + pad * 4

            local tipX = mx + 18
            local tipY = my + 18
            -- If below cursor goes off bottom, place above instead
            if tipY + th > vsy - 4 then
                tipY = my - th - 18
            end
            -- Final clamp to screen bounds
            if tipY < 4 then tipY = 4 end
            if tipY + th > vsy - 4 then tipY = vsy - th - 4 end

            glColor(1,1,1,0.92)
            glRect(tipX, tipY, tipX + tw, tipY + th)

            glColor(0,0,0,0.25)
            glLineWidth(1.0)
            glBeginEnd(GL_LINES, function()
                glVertex(tipX, tipY); glVertex(tipX + tw, tipY)
                glVertex(tipX + tw, tipY); glVertex(tipX + tw, tipY + th)
                glVertex(tipX + tw, tipY + th); glVertex(tipX, tipY + th)
                glVertex(tipX, tipY + th); glVertex(tipX, tipY)
            end)

            glColor(0,0,0,1)
            glText(label1, tipX + pad, tipY + th - fontSize - pad, fontSize, "lo")
            glText(value1, tipX + tw - pad, tipY + th - fontSize - pad, fontSize, "ro")

            glText(label2, tipX + pad, tipY + th - fontSize*2 - pad*2, fontSize, "lo")
            glText(value2, tipX + tw - pad, tipY + th - fontSize*2 - pad*2, fontSize, "ro")

            glText(label3, tipX + pad, tipY + pad, fontSize, "lo")
            glText(value3, tipX + tw - pad, tipY + pad, fontSize, "ro")
        end
    end


        -- Resize handle (top-right corner)
        glColor(1,1,1,0.8)
        glRect(x2 - DETACHED_RESIZE, y1,
            x2, y1 + DETACHED_RESIZE)
end

-- INITIALIZE DETACHED WINDOW --------------------------------------------------
Detached_Load()

--------------------------------------------------------------------------------
-- INTEGRATION INTO MAIN WIDGET
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TOP-BAR ADDON MODE TOGGLE (shared) ------------------------------------------
--------------------------------------------------------------------------------
-- Round 15: factored out of the /ecographtopbaraddon console command's own
-- body so the new "[A]" button on the main panel itself (see
-- DrawCompactOverlay's own "[A]" button block, and its MousePress check in
-- the wrapper below) can call the exact same logic instead of duplicating
-- it. Has to live HERE -- textually after `local detached = {...}` -- since
-- the ON branch references `detached` directly; a function defined earlier
-- in the file (like the file's original, hand-written widget:MousePress)
-- has no way to see a `local` declared later, no matter when it actually
-- runs (same Lua scoping constraint documented in Round 13's notes).
function widget.ToggleTopBarAddonMode()
    widget._topAddonMode = not widget._topAddonMode
    Spring.SetConfigInt("eco_graph_top_addon_mode", widget._topAddonMode and 1 or 0)

    local vsx, vsy = Spring.GetViewGeometry()
    local topY = box.y2
    local centerX = (box.x1 + box.x2) * 0.5
    -- Round 18: captured so a "stuck" (magnet) detached window can be
    -- kept flush after this toggle resizes the main window -- see the
    -- stuck-mode sync block at the end of this function.
    local preY1 = box.y1

    if widget._topAddonMode then
        -- Shrink to just the top rows, anchored from the TOP edge (box.y2)
        -- so the title/status/button row doesn't jump -- same top-anchored
        -- resize math as the freeform drag-resize handler elsewhere in this
        -- file. Remembers the pre-addon height so turning this back off
        -- restores it, instead of staying tiny forever.
        widget._preAddonHeight = box.y2 - box.y1

        -- Round 17: height gets the same remembered-addon-size treatment
        -- width already had since Round 14 -- this used to hard-code
        -- newH = 95 unconditionally, so resizing the panel SHORTER while
        -- already in addon mode (e.g. dragging the resize handle down)
        -- would silently snap back to 95 the next time addon mode turned
        -- on, as if the manual resize had never happened. Now it restores
        -- whatever addon-mode height the user last resized to, falling
        -- back to 95 only the very first time (no remembered value yet).
        local newH = widget._addonHeight or 95
        box.y1 = topY - newH
        cfg.height = newH / vsy

        -- Round 14: width gets the same pre/post treatment as height,
        -- anchored from the panel's horizontal CENTER so it doesn't jump
        -- sideways. Remembers the normal-mode width so turning this back
        -- off restores it, and remembers the LAST addon-mode width the
        -- user resized to, so re-entering addon mode restores that narrow
        -- strip width instead of whatever width normal mode was at.
        widget._preAddonWidth = box.x2 - box.x1
        local newW = widget._addonWidth or (box.x2 - box.x1)
        -- Round 18: clamp against the same collision-safe floor the
        -- freeform resize handler now enforces in addon mode (its own
        -- "Round 18: addon-mode minimum width" comment there) -- in
        -- case a remembered widget._addonWidth predates that floor.
        -- (No shared named constant: this file's main chunk is already
        -- at Lua 5.1's 200-local ceiling -- see Round 15's notes -- so
        -- the literal 420 is duplicated at both sites instead, same as
        -- other paired magic numbers already are elsewhere in this
        -- file, e.g. Round 8's [X]/resize-handle margin.)
        newW = math.max(newW, 420)
        newW = math.min(newW, vsx * 0.95)
        box.x1 = centerX - newW * 0.5
        box.x2 = centerX + newW * 0.5
        cfg.width = newW / vsx
        if graphList then glDeleteList(graphList) graphList = nil end

        -- This mode's whole point is a slim Top-Bar-style strip -- make
        -- sure the detached dual-line window is open so the Metal/Energy
        -- income/usage numbers it hides are still visible somewhere.
        if not detached.visible then
            detached.visible = true
            widget._detachedVisible = true
            Spring.SetConfigInt("eco_detached_visible", 1)
        end

        Spring.Echo("[EcoGraph] Top-Bar addon mode: ON")
    else
        -- Round 17: remember the addon-mode height first (mirrors width's
        -- own widget._addonWidth capture right below), so the resize the
        -- user just made while in addon mode is what the ON branch above
        -- restores next time, instead of silently reverting to 95.
        widget._addonHeight = box.y2 - box.y1

        -- Restore whatever height this panel had before entering addon
        -- mode (falls back to a sane default if that was never recorded).
        local restoreH = widget._preAddonHeight or (vsy * 0.12)
        box.y1 = topY - restoreH
        cfg.height = restoreH / vsy

        -- Round 14: same restore for width, remembering the addon-mode
        -- width first so toggling back ON later picks up where this
        -- addon-mode session left off.
        widget._addonWidth = box.x2 - box.x1
        local restoreW = widget._preAddonWidth or (vsx * 0.70)
        box.x1 = centerX - restoreW * 0.5
        box.x2 = centerX + restoreW * 0.5
        cfg.width = restoreW / vsx
        if graphList then glDeleteList(graphList) graphList = nil end

        Spring.Echo("[EcoGraph] Top-Bar addon mode: OFF")
    end

    -- Round 18: keep a "stuck" (magnet) detached window visually flush
    -- after a resize from THIS toggle, not just after a drag (Round 13's
    -- own stuck-sync only fires from widget:MouseMove). The user can
    -- only ever enter stuck mode via detached.AttachBelowMain() (the
    -- "^" button), which docks it flush under the main window's bottom
    -- edge, centered on the main window's own center -- so at the
    -- moment stuck mode turns on, detached.y is always exactly
    -- box.y1 - gap, and its X is already centered on centerX. Since
    -- this toggle's width change is anchored on that SAME centerX (see
    -- above), the X relationship never needs correcting -- only box.y1
    -- moves (the height change is TOP-anchored), so only detached's Y
    -- needs to follow it, by the same delta, to stay flush instead of
    -- leaving a gap (shrinking into addon mode) or overlapping
    -- (expanding back out).
    if detached.visible and detached.stuck then
        local moveDY = box.y1 - preY1
        detached.y1 = detached.y1 + moveDY
        detached.y2 = detached.y2 + moveDY
        Detached_Save()
    end
end

-- 1. Inject into DrawScreen
local old_DrawScreen = widget.DrawScreen

function widget:DrawScreen()
    -- First draw the main widget
    if old_DrawScreen then
        old_DrawScreen(self)
    end

    -- Detached drawing is deferred to the safety wrapper below so the main
    -- widget can remain in the foreground over the detached backplate.
end

-- 2. Inject toggle into MousePress
local old_MousePress = widget.MousePress
function widget:MousePress(mx, my, button)
    local alt, ctrl = Spring.GetModKeyState()

-- CTRL + Left‑Click inside Eco Graph toggles detached window
if ctrl and button == 1 and PointInBox(mx, my) then
    detached.visible = not detached.visible
    widget._detachedVisible = detached.visible
    Spring.SetConfigInt("eco_detached_visible", detached.visible and 1 or 0)
    return true
end


if button == 1
and detached.closeX1 and mx >= detached.closeX1 and mx <= detached.closeX2
and my >= detached.closeY1 and my <= detached.closeY2 then
    detached.visible = false
    widget._detachedVisible = false
    Spring.SetConfigInt("eco_detached_visible", 0)
    Detached_Save()
    return true
end


-- HISTORY SELECTOR CLICK
if detached.visible and detached.histX1 then
    if mx >= detached.histX1 and mx <= detached.histX2
    and my >= detached.histY1 and my <= detached.histY2 then

        local opts  = cfg.historyOptions
        local count = #opts
        local wOpt  = (detached.histX2 - detached.histX1) / count

        for i = 1, count do
            local xA = detached.histX1 + (i-1)*wOpt
            local xB = xA + wOpt
            if mx >= xA and mx <= xB then
                cfg.historySeconds = opts[i]
                Spring.SetConfigInt("eco_graph_history_seconds", cfg.historySeconds)
                return true
            end
        end
    end
end


-- BACKGROUND MODE TOGGLE CLICK (checked before drag-start below so it
-- doesn't get swallowed as "start dragging the window"). Own flag/config
-- key -- toggling this no longer touches the main/attached window's
-- transparency or its cached graphList, since the two are independent now.
if detached.visible and button == 1 and widget._detachedBgToggleRect then
    local r = widget._detachedBgToggleRect
    if mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2 then
        widget._detachedTransparentMode = not widget._detachedTransparentMode
        Spring.SetConfigInt("eco_detached_transparent_mode", widget._detachedTransparentMode and 1 or 0)

        return true
    end
end


-- RE-ATTACH/UNSTICK BUTTON CLICK ("^" / "v"): same priority as the
-- close button and background toggle above -- checked before the
-- generic drag-start block below, which would otherwise swallow this
-- click as "start dragging the window" instead (same overlap-priority
-- lesson as the main window's resize-handle/close-button fix). Round
-- 13: branches on detached.stuck, since the button's own job swaps
-- between the two (see Detached_DrawStatsRow()'s own comment).
if detached.visible and button == 1
and detached.attachX1 and mx >= detached.attachX1 and mx <= detached.attachX2
and my >= detached.attachY1 and my <= detached.attachY2 then
    if detached.stuck then
        detached.Unstick()
    else
        detached.AttachBelowMain()
    end
    return true
end


-- "[A]" TOP-BAR ADDON MODE TOGGLE CLICK (main window's own button, Round
-- 15): same overlap-priority reasoning as the re-attach button above --
-- checked here, in the first wrapper that runs AFTER `detached`/
-- widget.ToggleTopBarAddonMode() exist and so can call it directly, and BEFORE
-- falling through to old_MousePress, whose own final step would
-- otherwise swallow this click as "start dragging the window" instead.
-- Lives on the MAIN window (not the detached one), but its hitbox is
-- only valid while the main panel is actually visible and drawing.
if WG.EcoGraph_UIVisible and button == 1
and widget._addonBtnX1 and mx >= widget._addonBtnX1 and mx <= widget._addonBtnX2
and my >= widget._addonBtnY1 and my <= widget._addonBtnY2 then
    widget.ToggleTopBarAddonMode()
    return true
end


    -- Detached window interactions
    if detached.visible and Detached_PointIn(mx, my) then
        -- Resize
        if button == 1 and Detached_PointInResize(mx, my) then
            detached.resizing = true
            detached.resizeStartX = mx
            detached.resizeStartY = my
            return true
        end

        -- Drag
        if button == 1 then
            detached.dragging = true
            detached.dragOffsetX = mx - detached.x1
            detached.dragOffsetY = my - detached.y1
            return true
        end
    end

    if old_MousePress then
        return old_MousePress(self, mx, my, button)
    end
    return false
end

-- Part 1 (end)

-- Part 2 
--------------------------------------------------------------------------------
-- DETACHED WINDOW — MOUSEMOVE INTEGRATION
--------------------------------------------------------------------------------
local old_MouseMove = widget.MouseMove
function widget:MouseMove(mx, my, dx, dy, button)
    -- If detached window is visible, handle drag/resize
    if detached.visible then

        ------------------------------------------------------------------------
        -- RESIZING
        ------------------------------------------------------------------------
        if detached.resizing and button == 1 then
            local newW = detached.x2 - detached.x1 + dx
            local newH = detached.y2 - detached.y1 - dy

            -- Minimum size
            if newW < 200 then newW = 200 end
            if newH < 60 then newH = 60 end   -- Height settings for detach graph    120 was default

            detached.x2 = detached.x1 + newW
            detached.y1 = detached.y2 - newH

            return true
        end

        ------------------------------------------------------------------------
        -- DRAGGING
        ------------------------------------------------------------------------
        if detached.dragging and button == 1 then
            local w = detached.x2 - detached.x1
            local h = detached.y2 - detached.y1

            local newX1 = mx - detached.dragOffsetX
            local newY1 = my - detached.dragOffsetY
            local newX2 = newX1 + w
            local newY2 = newY1 + h

            -- Clamp to screen
            local vsx, vsy = Spring.GetViewGeometry()
            if newX1 < 0 then newX1 = 0; newX2 = w end
            if newY1 < 0 then newY1 = 0; newY2 = h end
            if newX2 > vsx then newX2 = vsx; newX1 = vsx - w end
            if newY2 > vsy then newY2 = vsy; newY1 = vsy - h end

            -- Round 13: while magnet (stuck) mode is on, dragging the
            -- DETACHED window drags the main window along with it by the
            -- same delta -- "stick like a magnet", not a merge. Measured
            -- from the detached window's own pre-clamp position, so a
            -- screen-edge clamp on the detached window doesn't yank the
            -- main window further than the detached window itself
            -- actually moved.
            if detached.stuck then
                local moveDX = newX1 - detached.x1
                local moveDY = newY1 - detached.y1
                box.x1 = box.x1 + moveDX
                box.y1 = box.y1 + moveDY
                box.x2 = box.x2 + moveDX
                box.y2 = box.y2 + moveDY
                cfg.anchorX = (box.x1 + (box.x2 - box.x1) * 0.5) / vsx
                cfg.anchorY = box.y1 / vsy
                if graphList then glDeleteList(graphList) graphList = nil end
                BuildGraphList()
            end

            detached.x1, detached.y1, detached.x2, detached.y2 =
                newX1, newY1, newX2, newY2

            return true
        end
    end

    -- Round 13: capture the main window's position BEFORE handing off to
    -- the original handler below (which is what actually drags it) so a
    -- drag there can be detected afterward and mirrored onto the
    -- detached window while magnet (stuck) mode is on. old_MouseMove is
    -- defined earlier in the file, before `detached` exists as a local,
    -- so it can't reference `detached` itself -- this wrapper is the one
    -- place that safely can.
    local preBoxX1, preBoxY1 = box.x1, box.y1

    -- Fall back to original handler
    local handled = old_MouseMove(self, mx, my, dx, dy, button)

    if detached.stuck and detached.visible
    and (box.x1 ~= preBoxX1 or box.y1 ~= preBoxY1) then
        local moveDX = box.x1 - preBoxX1
        local moveDY = box.y1 - preBoxY1
        detached.x1 = detached.x1 + moveDX
        detached.y1 = detached.y1 + moveDY
        detached.x2 = detached.x2 + moveDX
        detached.y2 = detached.y2 + moveDY
    end

    return handled
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — MOUSERELEASE INTEGRATION
--------------------------------------------------------------------------------
local old_MouseRelease = widget.MouseRelease
function widget:MouseRelease(mx, my, button)
    if detached.visible then

        ------------------------------------------------------------------------
        -- STOP RESIZING
        ------------------------------------------------------------------------
        if detached.resizing and button == 1 then
            detached.resizing = false
            Detached_Save()
            return true
        end

        ------------------------------------------------------------------------
        -- STOP DRAGGING
        ------------------------------------------------------------------------
        if detached.dragging and button == 1 then
            detached.dragging = false
            Detached_Save()

            -- Round 13: dragging the detached window while stuck also
            -- moved the main window along with it (see the DRAGGING
            -- block in the MouseMove wrapper above) -- persist that too,
            -- since the main window's OWN "STOP DRAGGING" save (in
            -- old_MouseRelease below) never runs here: the main window's
            -- `dragging` flag was never true in this scenario, only
            -- `detached.dragging` was.
            if detached.stuck then
                Spring.SetConfigFloat("eco_graph_x", cfg.anchorX)
                Spring.SetConfigFloat("eco_graph_y", cfg.anchorY)
            end

            return true
        end
    end

    -- Round 13: `dragging` (the main window's OWN drag flag, a
    -- file-level local declared well before `detached` exists -- unlike
    -- `box`, it's an upvalue this wrapper can read directly) is about to
    -- be cleared by old_MouseRelease below if this release ends a main-
    -- window drag. In that case, while magnet (stuck) mode is on, the
    -- detached window moved along too (via MouseMove's stuck-shift logic)
    -- but has no release of its own to persist it here -- do that after
    -- old_MouseRelease runs.
    local wasMainDragging = dragging and button == 1

    local handled = old_MouseRelease(self, mx, my, button)

    if wasMainDragging and detached.stuck and detached.visible then
        Detached_Save()
    end

    return handled
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — ISABOVE INTEGRATION
--------------------------------------------------------------------------------
local old_IsAbove = widget.IsAbove
function widget:IsAbove(mx, my)
    -- Detached window hover
    if detached.visible and Detached_PointIn(mx, my) then
        return true
    end

    -- Otherwise defer to original
    return old_IsAbove(self, mx, my)
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — SAFETY WRAPPERS
--------------------------------------------------------------------------------

-- Ensure detached window never draws when GUI is hidden
local old_DrawScreen2 = widget.DrawScreen

function widget:DrawScreen()
    -- FONT_SCALE FIX: `fontSize`/`titleSize` (declared near the top of the
    -- file) are the two values almost every glText(...) call in this widget
    -- reads, but they were only ever computed ONCE, at chunk-load time, from
    -- whatever FONT_SCALE was at that instant -- so /ecographfont+/- (which
    -- just reassigns the FONT_SCALE upvalue) never reached them, and most of
    -- the widget's text stayed locked at the load-time size. Re-deriving
    -- them here, every frame, before anything draws, is a plain assignment
    -- to the existing upvalues (not a new local), so it's free under the
    -- 200-local ceiling and now the font commands actually control "most of
    -- the text size in the widget" as originally intended.
    fontSize  = 14 * FONT_SCALE
    titleSize = 12 * FONT_SCALE

    if spIsGUIHidden() then
        return
    end

    -- Draw detached window first (second-level)
    Detached_Draw()

    -- Then draw main widget on top so its tooltips hover above detached
    old_DrawScreen2(self)
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — VIEW RESIZE HANDLING
--------------------------------------------------------------------------------
local old_ViewResize = widget.ViewResize
function widget:ViewResize(vsx, vsy)
    if old_ViewResize then
        old_ViewResize(self, vsx, vsy)
    end

    -- Re‑clamp detached window to screen
    local w = detached.x2 - detached.x1
    local h = detached.y2 - detached.y1

    if detached.x1 < 0 then detached.x1 = 0; detached.x2 = w end
    if detached.y1 < 0 then detached.y1 = 0; detached.y2 = h end
    if detached.x2 > vsx then detached.x2 = vsx; detached.x1 = vsx - w end
    if detached.y2 > vsy then detached.y2 = vsy; detached.y1 = vsy - h end
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — SHUTDOWN SAVE
--------------------------------------------------------------------------------
local old_Shutdown = widget.Shutdown
function widget:Shutdown()
    Spring.SetConfigInt("eco_graph_hide_graphs", hideGraphs and 1 or 0)
    Spring.SetConfigInt("eco_detached_visible", detached.visible and 1 or 0)
    Detached_Save()
    if old_Shutdown then
        old_Shutdown(self)
    end
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — KEYBOARD SAFETY
--------------------------------------------------------------------------------
local old_KeyPress = widget.KeyPress
function widget:KeyPress(key, mods, isRepeat)
    -- If user presses Ctrl+L (lock dragging), ensure detached window stops dragging
    if mods.ctrl and (key == string.byte("l") or key == string.byte("L")) then
        detached.dragging = false
        detached.resizing = false
    end

    if old_KeyPress then
        return old_KeyPress(self, key, mods, isRepeat)
    end
end

--------------------------------------------------------------------------------
-- DETACHED WINDOW — FINAL SAFETY: NO INTERFERENCE WITH DROPDOWNS
--------------------------------------------------------------------------------

-- Capture the REAL main MousePress BEFORE overriding it
local original_MousePress = widget.MousePress

function widget:MousePress(mx, my, button)
    local alt, ctrl = Spring.GetModKeyState()

    --------------------------------------------------------------------
    -- 1. ALWAYS allow CTRL+RMB toggle for MAIN window
    --------------------------------------------------------------------
    if ctrl and button == 3 and box then
        if mx >= box.x1 and mx <= box.x2 and my >= box.y1 and my <= box.y2 then
            hideGraphs = not hideGraphs
            Spring.SetConfigInt("eco_graph_hide_graphs", hideGraphs and 1 or 0)
            Spring.Echo("Dual-line graphs toggled:", hideGraphs)
            return true
        end
    end

    --------------------------------------------------------------------
    -- 2. DROPDOWN SAFETY
    --------------------------------------------------------------------
    if metalShareDropdownOpen or energyShareDropdown then
        return original_MousePress(self, mx, my, button)
    end

    --------------------------------------------------------------------
    -- 3. FALLBACK TO REAL MAIN MOUSEPRESS
    --------------------------------------------------------------------
    return original_MousePress(self, mx, my, button)
end



--------------------------------------------------------------------------------
-- DETACHED WINDOW — FINAL SAFETY: NO INTERFERENCE WITH COMPACT MODE
--------------------------------------------------------------------------------
-- Compact mode uses its own hitboxes; detached window must not override them
local old_IsAbove2 = widget.IsAbove
function widget:IsAbove(mx, my)
    -- Recreate the original main IsAbove logic so we can prefer main
    -- hit-testing even if earlier wrappers changed widget.IsAbove.
    local function mainIsAbove(mx, my)
        if fullyHidden then
            return PointInUnhideButton(mx, my)
        end
        if not showWidget then return false end
        return PointInBox(mx, my)
    end

    -- If mouse is over main, prefer main so its tooltips render on top.
    if mainIsAbove(mx, my) then
        return true
    end

    -- Else, if detached contains the point, report it as above.
    if detached.visible and Detached_PointIn(mx, my) then
        return true
    end

    return false
end


--------------------------------------------------------------------------------
-- TOGGLE-MENU SAFETY NET — SHUTDOWN (REMOVED, Round 19, 2026-10-18)
--------------------------------------------------------------------------------
-- This used to auto-restore "Top Bar" on Shutdown if it was off, as a
-- fallback for a new/casual player who disabled it and might not know
-- how to turn it back on (see the NOTE this replaced, dated 2026-10-17,
-- for the full original reasoning -- that reasoning is unchanged, only
-- the mechanism is gone).
--
-- Removed for the incoming BAR user-widget sandbox: it worked by
-- Spring.SendCommands("luaui enablewidget Top Bar"), and "enablewidget"
-- is one of the sandbox's blocked command substrings -- the exact same
-- root cause already documented for the Top Bar toggle BUTTON's own
-- removal (2026-10-17, see EcoToggleMenu above). Unlike that case,
-- there's no reword or replacement to swap in here either: the gist's
-- migration rules list widgetHandler:EnableWidget/DisableWidget/
-- ToggleWidget (and the Raw forms) as unsupported no-ops too, so no
-- user widget can re-enable another widget under the sandbox, by any
-- API. Keeping this as silently-dead code would only leave a false
-- sense of safety (it would still set the config flag to 1 without the
-- widget actually being re-enabled), so it's deleted outright instead.
-- Full writeup: claude/bar-widget-sandbox-notes.md.

--------------------------------------------------------------------------------
-- CONSOLE COMMANDS
--------------------------------------------------------------------------------
-- Registered from here (end of file, chained onto whatever Initialize
-- already exists), not from the main widget:Initialize() above -- these
-- handlers close over `EcoToggleMenu`, `detached` and `hideGraphs`, and
-- `detached` in particular isn't declared as a local until further down
-- the file than widget:Initialize() sits. A Lua chunk only sees a local
-- as an upvalue if the `local` declaration is lexically ABOVE the
-- function capturing it, so these have to live below that declaration --
-- same reasoning, and the same chain-onto-the-existing-handler pattern,
-- as every other Shutdown hook already added onto this file.
--
-- Stored on `widget` rather than a new local, same 200-local-ceiling
-- reason as everywhere else in this file.
widget._FONT_SCALE_STEP = 0.05
widget._FONT_SCALE_MIN, widget._FONT_SCALE_MAX = 0.5, 2.5

-- Stored on `widget` rather than a new local -- see the 200-local-ceiling
-- note above; this file has no headroom left for another top-level local.
widget._old_Initialize_Commands = widget.Initialize
function widget:Initialize()
    if widget._old_Initialize_Commands then
        widget._old_Initialize_Commands(self)
    end

    -- /ecographcenter -- re-centers the draggable Top Bar/Eco Graph
    -- toggle panel (and the detached dual-line window, if it's open) on
    -- the CURRENT screen. Both remember a dragged pixel position across
    -- sessions, which is exactly the problem: a position saved on one
    -- resolution (e.g. this widget built and tested at 3440x1440) can
    -- land off-screen entirely on someone else's smaller monitor after
    -- they download the release, with nothing visible left to drag back
    -- into view.
    widgetHandler:AddAction("ecographcenter", function()
        -- Main Eco Graph window: re-center on the CURRENT screen,
        -- keeping its existing size -- same off-screen-after-resolution-
        -- change reasoning as EcoToggleMenu.Center()/detached.Center()
        -- below, just applied to the box this command previously missed.
        local curVsx, curVsy = Spring.GetViewGeometry()
        local mw = box.x2 - box.x1
        local mh = box.y2 - box.y1

        box.x1 = (curVsx - mw) * 0.5
        box.y1 = (curVsy - mh) * 0.5
        box.x2 = box.x1 + mw
        box.y2 = box.y1 + mh

        cfg.anchorX = (box.x1 + mw * 0.5) / curVsx
        cfg.anchorY = box.y1 / curVsy
        Spring.SetConfigFloat("eco_graph_x", cfg.anchorX)
        Spring.SetConfigFloat("eco_graph_y", cfg.anchorY)

        if graphList then
            glDeleteList(graphList)
            graphList = nil
        end

        EcoToggleMenu.Center()
        if detached.visible then
            detached.Center()
        end
        Spring.Echo("[EcoGraph] Main window, toggle menu" ..
            (detached.visible and ", and detached window" or "") .. " re-centered.")
        return true
    end, nil, "t")

    -- /ecographdual1 -- toggles the dual-line graph's OWN detached
    -- window, same as CTRL+Left-Click on the main Eco Graph window.
    widgetHandler:AddAction("ecographdual1", function()
        detached.visible = not detached.visible
        widget._detachedVisible = detached.visible
        Spring.SetConfigInt("eco_detached_visible", detached.visible and 1 or 0)
        Spring.Echo("[EcoGraph] Detached dual-line window: " ..
            (detached.visible and "ON" or "OFF"))
        return true
    end, nil, "t")

    -- /ecographdual2 -- toggles the dual-line graph drawn INSIDE the
    -- main Eco Graph window, same as CTRL+Right-Click on the main window.
    widgetHandler:AddAction("ecographdual2", function()
        hideGraphs = not hideGraphs
        Spring.SetConfigInt("eco_graph_hide_graphs", hideGraphs and 1 or 0)
        Spring.Echo("[EcoGraph] Dual-line graphs in main window: " ..
            (hideGraphs and "OFF" or "ON"))
        return true
    end, nil, "t")

    -- /ecographfont+ / /ecographfont- -- adjusts FONT_SCALE, which
    -- drives nearly every text size in the widget (see its declaration
    -- near the top of the file). Clamped to a range that stays readable
    -- at either end; the graph display list is invalidated the same way
    -- the compact/full toggle already does, in case any font-scaled
    -- geometry got baked into it.
    widgetHandler:AddAction("ecographfont+", function()
        FONT_SCALE = math.min(widget._FONT_SCALE_MAX, FONT_SCALE + widget._FONT_SCALE_STEP)
        Spring.SetConfigFloat("eco_graph_font_scale", FONT_SCALE)
        if graphList then glDeleteList(graphList) graphList = nil end
        Spring.Echo(string.format("[EcoGraph] Font scale: %.2f", FONT_SCALE))
        return true
    end, nil, "t")

    widgetHandler:AddAction("ecographfont-", function()
        FONT_SCALE = math.max(widget._FONT_SCALE_MIN, FONT_SCALE - widget._FONT_SCALE_STEP)
        Spring.SetConfigFloat("eco_graph_font_scale", FONT_SCALE)
        if graphList then glDeleteList(graphList) graphList = nil end
        Spring.Echo(string.format("[EcoGraph] Font scale: %.2f", FONT_SCALE))
        return true
    end, nil, "t")

    -- /ecographt / /ecographd -- explicitly SET (not toggle) the
    -- background mode, matching the existing [T]/[D] buttons on both the
    -- main window and the detached window. Both windows are driven
    -- together here since there's no way to name "just the detached one"
    -- from a single command name -- use the two [T]/[D] buttons
    -- in-game if you want them set differently from each other.
    widgetHandler:AddAction("ecographt", function()
        widget._transparentMode = true
        widget._detachedTransparentMode = true
        Spring.SetConfigInt("eco_graph_transparent_mode", 1)
        Spring.SetConfigInt("eco_detached_transparent_mode", 1)
        Spring.Echo("[EcoGraph] Background: Transparent")
        return true
    end, nil, "t")

    widgetHandler:AddAction("ecographd", function()
        widget._transparentMode = false
        widget._detachedTransparentMode = false
        Spring.SetConfigInt("eco_graph_transparent_mode", 0)
        Spring.SetConfigInt("eco_detached_transparent_mode", 0)
        Spring.Echo("[EcoGraph] Background: Dark/opaque")
        return true
    end, nil, "t")

    -- /ecographbar -- toggles the "Top Bar"-style panel skin (chamfered
    -- corners, dark warm-brown gradient, bronze border) on both windows
    -- at once. Purely cosmetic: the panel's background/border is the
    -- only thing that changes -- layout, text, and graphs are untouched.
    widgetHandler:AddAction("ecographbar", function()
        widget._barSkin = not widget._barSkin
        Spring.SetConfigInt("eco_graph_bar_skin", widget._barSkin and 1 or 0)
        Spring.Echo("[EcoGraph] Top Bar-style skin: " .. (widget._barSkin and "ON" or "OFF"))
        return true
    end, nil, "t")

    -- /ecographbarui -- the OTHER "Top Bar"-style skin: draws the panel
    -- via WG.FlowUI.Draw.Element, the exact same shared function Top
    -- Bar's own panels use (confirmed from its source), instead of
    -- Round 10's hand-approximated shape. Independent of /ecographbar --
    -- both exist as separate options, not a replacement.
    widgetHandler:AddAction("ecographbarui", function()
        widget._barSkinUi = not widget._barSkinUi
        Spring.SetConfigInt("eco_graph_bar_skin_ui", widget._barSkinUi and 1 or 0)
        Spring.Echo("[EcoGraph] Top Bar UI skin (FlowUI): " .. (widget._barSkinUi and "ON" or "OFF"))
        return true
    end, nil, "t")

    -- /ecographtopbardebug -- DIAGNOSTIC ONLY (Round 21 investigation).
    -- Prints exactly what GetTopBarOverlap() sees: the widget_Top Bar
    -- config flag it now gates on first, whether WG['topbar'] still
    -- exists, what it reports for its own position, and this panel's
    -- own box.
    widgetHandler:AddAction("ecographtopbardebug", function()
        Spring.Echo(string.format("[EcoGraph] widget_Top Bar config = %d (0 = off)",
            Spring.GetConfigInt("widget_Top Bar", 1)))
        local topbar = WG['topbar']
        if not topbar then
            Spring.Echo("[EcoGraph] WG['topbar'] is nil (Top Bar not loaded)")
        elseif not topbar.GetPosition then
            Spring.Echo("[EcoGraph] WG['topbar'] exists but has no GetPosition function")
        else
            local tb = topbar.GetPosition()
            if tb then
                Spring.Echo(string.format("[EcoGraph] WG['topbar'] exists, rect: %.0f,%.0f,%.0f,%.0f",
                    tb[1], tb[2], tb[3], tb[4]))
            else
                Spring.Echo("[EcoGraph] WG['topbar'] exists, GetPosition() returned nil")
            end
        end
        Spring.Echo(string.format("[EcoGraph] Eco Graph box: %.0f,%.0f,%.0f,%.0f  barSkinUi=%s  overlap=%s",
            box.x1, box.y1, box.x2, box.y2,
            tostring(widget._barSkinUi),
            tostring(GetTopBarOverlap(box.x1, box.y1, box.x2, box.y2))))
        return true
    end, nil, "t")

    -- /ecographorig -- back to the original plain panel (flat color +
    -- straight-edge border), from before either skin existed. Added in
    -- Round 12 once /ecographbarui became the new default look, so
    -- there's still a one-word way to get the original back. Not a
    -- toggle like the others -- there's no separate "orig" flag, it just
    -- forces both skin flags off.
    widgetHandler:AddAction("ecographorig", function()
        widget._barSkin = false
        widget._barSkinUi = false
        Spring.SetConfigInt("eco_graph_bar_skin", 0)
        Spring.SetConfigInt("eco_graph_bar_skin_ui", 0)
        Spring.Echo("[EcoGraph] Reverted to the original plain panel.")
        return true
    end, nil, "t")

    -- /ecographtopbaraddon -- a minimal "Top Bar replacement" layout.
    -- Hides the storage bars (and their draggable auto-share thumbs),
    -- the Big Metal/Energy Available readout, the commander count, the
    -- Tidal stat, and the income/usage graphs + history selector --
    -- leaving just the title/status row, [Pause]/[D]/[X], the
    -- energy-to-metal stats bracket, [Intel], the M:E ratio, and the
    -- Wind text + bar (see DrawCompactOverlay's own `if not
    -- widget._topAddonMode then` guards for exactly what that covers).
    -- [Intel] and the M:E ratio move up onto the Wind text's row since
    -- their usual spot near the bottom has nothing left down there to
    -- sit next to any more.
    --
    -- The Metal/Energy income/usage numbers this hides from the main
    -- panel are not lost -- they already have a second home: the
    -- detached dual-line window shows its own copy of them, and the
    -- main panel's copy already hides itself whenever that window is
    -- visible (see the `widget._detachedVisible` check near the top of
    -- DrawCompactOverlay -- pre-existing, not new this round). So this
    -- command also force-opens the detached window, rather than
    -- leaving those numbers with nowhere to go.
    -- Round 15: body now lives in the shared widget.ToggleTopBarAddonMode(),
    -- so this command and the new "[A]" button on the main panel (see
    -- DrawCompactOverlay and its MousePress check) stay in sync by
    -- construction instead of by hand.
    widgetHandler:AddAction("ecographtopbaraddon", function()
        widget.ToggleTopBarAddonMode()
        return true
    end, nil, "t")
end

widget._old_Shutdown_Commands = widget.Shutdown
function widget:Shutdown()
    widgetHandler:RemoveAction("ecographcenter")
    widgetHandler:RemoveAction("ecographdual1")
    widgetHandler:RemoveAction("ecographdual2")
    widgetHandler:RemoveAction("ecographfont+")
    widgetHandler:RemoveAction("ecographfont-")
    widgetHandler:RemoveAction("ecographt")
    widgetHandler:RemoveAction("ecographd")
    widgetHandler:RemoveAction("ecographbar")
    widgetHandler:RemoveAction("ecographbarui")
    widgetHandler:RemoveAction("ecographtopbardebug")
    widgetHandler:RemoveAction("ecographorig")
    widgetHandler:RemoveAction("ecographtopbaraddon")

    if widget._old_Shutdown_Commands then
        widget._old_Shutdown_Commands(self)
    end
end

--------------------------------------------------------------------------------
-- End of Widget
--------------------------------------------------------------------------------
