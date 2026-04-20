function widget:GetInfo()
    return {
        name      = "Eco Graph",
        desc      = "Top Bar widget replacement. Tracks your Metal and Energy economy in real time, helping you monitor income, storage, and usage so you can make better macro decisions.",
        author    = "Copilot + Armis71",
        date      = "2026-01-05",
        version   = "v3.0",
        license   = "GPL v2 or later",
        layer     = -999999,
        enabled   = true,
    }
end

-- GLOBAL FONT SCALE (shrink everything proportionally)
local FONT_SCALE = 0.9  -- try 0.85 first; 0.80 or 0.75 if you want it even shorter

-- Get's Wind Average Information
local windFunctions = VFS.Include('common/wind_functions.lua')


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
energyConversionPercent   = energyConversionPercent or 0
energyShareButton         = energyShareButton or {x1=0,y1=0,x2=0,y2=0}

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


-- Compact number formatter (10K+ → K, 1M+ → M)
local function FormatCompact(n)
    if n >= 1e6 then
        return string.format("%.2fM", n / 1e6)
    elseif n >= 1e4 then
        return string.format("%.2fK", n / 1e3)
    else
        return string.format("%.0f", n)
    end
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
local STATUS_HOLD_TIME     = 10  -- seconds

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
	bgColor     = {0, 0, 0, 0.99},
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

-- STATUS COLORS
local statusColors = {
    ["STALLING"]        = {1.0, 0.2, 0.2, 1.0},  -- red
    ["METAL STARVED"]   = {1.0, 0.5, 0.0, 1.0},  -- orange
    ["ENERGY STARVED"]  = {1.0, 0.5, 0.0, 1.0},  -- orange

    ["ECO WEAK"]        = {1.0, 0.9, 0.2, 1.0},  -- yellow
    ["ECO STABLE"]      = {0.3, 1.0, 0.3, 1.0},  -- green
    ["ECO STRONG"]      = {0.1, 1.0, 0.1, 1.0},  -- bright green

    ["OVERFLOWING"]     = {0.7, 0.3, 1.0, 1.0},  -- purple
    ["SURGING"]         = {0.3, 0.6, 1.0, 1.0},  -- blue
    ["BURNING"]         = {0.6, 0.3, 0.0, 1.0},  -- brown

    ["DEPLETED"]        = {0.1, 0.1, 0.1, 1.0},  -- dark
    ["FLOATING"]        = {0.9, 0.9, 0.9, 1.0},  -- light
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
    local function GetPlayerNameFromTeam(teamID)
        local players = spGetPlayerList(teamID, true)
        for _, pid in ipairs(players) do
            local name, active, spec, team = spGetPlayerInfo(pid)
            if team == teamID then return name end
        end
        return "Unknown"
    end

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

-- SMOOTHED ECO STATUS (5-second stability window)
local function GetEcoStatus(mNet, eNet, mIncome, eIncome, mCur, eCur, mStorage, eStorage)
    
    -- 1. RAW STATUS DETECTION (instantaneous)
        local rawStatus

    -- Hard failures first
    if mNet < 0 and eNet < 0 then
        rawStatus = "STALLING"

    elseif mNet < 0 then
        rawStatus = "METAL STARVED"

    elseif eNet < 0 then
        rawStatus = "ENERGY STARVED"

    -- Storage-based advanced states
    elseif mStorage == 0 or eStorage == 0 then
        rawStatus = "DEPLETED"

    elseif mCur >= mStorage * 0.95 or eCur >= eStorage * 0.95 then
        rawStatus = "OVERFLOWING"

    else
        -- Ratio-based eco health
        local mRatio = (mIncome > 0) and (mNet / mIncome) or 0
        local eRatio = (eIncome > 0) and (eNet / eIncome) or 0
        local r      = math.min(mRatio, eRatio)

        if r < 0.15 then
            rawStatus = "ECO WEAK"
        elseif r < 0.35 then
            rawStatus = "ECO STABLE"
        else
            rawStatus = "ECO STRONG"
        end
    end

    -- 2. STATUS SMOOTHING LOGIC (5-second hold)
    local now = spGetTimer()

    -- If raw status matches current → accept immediately
    if rawStatus == currentStatus then
        pendingStatus = nil
        return currentStatus
    end

    -- If raw status differs and no pending status → start pending
    if pendingStatus ~= rawStatus then
        pendingStatus    = rawStatus
        pendingStartTime = now
        return currentStatus
    end

    -- If pending status has lasted long enough → commit
    local dt = spDiffTimers(now, pendingStartTime)
    if dt >= STATUS_HOLD_TIME then
        currentStatus        = pendingStatus
        pendingStatus        = nil
        lastStatusChangeTime = now
        return currentStatus
    end

    -- Otherwise → still holding old status
    return currentStatus
end

-- REPLAY-AWARE VIEWED TEAM DETECTOR (SAFE FOR LIVE GAMES)
local function GetViewedTeamID()
    -- Get local player info
    local myPlayerID = Spring.GetMyPlayerID()
    local name, active, spectator, teamID = Spring.GetPlayerInfo(myPlayerID, false)

    
    -- CASE A: LIVE GAME (not spectator)
        if not spectator then
        -- Must NOT reveal enemy eco
        return teamID
    end

    
    -- CASE B: REPLAY POV TEAM
    -- In replays, the engine sets a POV team for the camera
    local _, _, _, povTeam = Spring.GetPlayerInfo(Spring.GetMyPlayerID(), false)
    if povTeam then
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

    local teamID = GetViewedTeamID()
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

--[[ local function BuildEnergyTooltip()
    if not smoothEnergyGen then
        return ""
    end

    local t1 = string.format("Static Generators     =  %-6.1f", smoothEnergyGen)
    local t2 = string.format("Dynamic Generators    =  %-6.1f", smoothEnergyReclaim)

    local d1 = "Static: Commander, T1/T2 Construction Bots,"
    local d2 = "            Adv. Solar, Fusion, Adv. Fusion, etc."
    local d3 = "Dynamic: T1 Solar, Turbines, Share, Reclaim,"
    local d4 = "                 Tidal generators, etc."

    return table.concat({
        t1,
        t2,
        "",
        d1,
        d2,
        d3,
        d4,
    }, "\n")
end ]]

function DrawPanelStats(label, income, usage, xCenter, yTop, incomeColor, usageColor)
    ------------------------------------------------------------
    -- SINGLE-LINE PANEL STATS:  Use   Net   Income
    ------------------------------------------------------------
    local net = income - usage

    -- Build strings (patched with K/M formatting)
    local useStr = "Use: " .. FormatIncome(usage)
    local incStr = "Income: " .. FormatIncome(income)
    local netStr = "Net: " .. FormatIncome(net)

    local useW = glGetTextWidth(useStr) * fontSize
    local incW = glGetTextWidth(incStr) * fontSize
    local netW = glGetTextWidth(netStr) * fontSize

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
        energyIncRect = { x1 = lineX1, y1 = lineY1, x2 = lineX2, y2 = lineY2 }
    elseif label == "Metal" then
        metalIncRect = { x1 = lineX1, y1 = lineY1, x2 = lineX2, y2 = lineY2 }
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


-- GRAPH BUILDING (CLEAN, OPTION B, FULL FUNCTION
local function BuildGraphList()

local graphMarginLeft  = 0.10   -- pushes Energy graph right
local graphMarginRight = 0.10  -- pushes Metal graph left


    if compactMode then
        if graphList then glDeleteList(graphList) graphList = nil end
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
        glColor(cfg.bgColor)
        glRect(x1,y1,x2,y2)

        glColor(cfg.borderColor)
        glLineWidth(1.5)
        glBeginEnd(GL_LINES, function()
            glVertex(x1,y1); glVertex(x2,y1)
            glVertex(x2,y1); glVertex(x2,y2)
            glVertex(x2,y2); glVertex(x1,y2)
            glVertex(x1,y2); glVertex(x1,y1)
        end)

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

			-- INCOME CURVE
			glColor(panel.incomeColor)
			glLineWidth(2.0)
			glBeginEnd(GL_LINE_STRIP, function()
				for i = 1, #data, 2 do   -- ← was 1, #data
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
				for i = 1, #data, 2 do   -- ← was 1, #data
					local s  = data[i]
					local tf = (s.t - minT) / rangeT
					local vf = (s.usage - minV) / rangeV
					glVertex(gx1 + gw * tf, gy1 + gh * vf)
				end
			end)

-- METAL STORAGE BAR
if panel.name == "Metal" then
    local teamID = Spring.GetMyTeamID()
local mCur, _ = spGetTeamResources(teamID, "metal")
local _, mStorage = spGetTeamResources(teamID, "metal")

    mCur     = mCur or 0
    mStorage = mStorage or 1

--[[ local frac
if not metalShareEnabled or metalSharePercent == 0 then
    -- Auto-share OFF → show actual storage fill
    frac = math.max(0, math.min(1, mCur / mStorage))
else
    -- Auto-share ON → show KEEP threshold (NOT excess)
    local keepFraction = 1 - metalSharePercent
    frac = keepFraction
end
 ]]

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

                
                -- BAR FILL
                local fillW = barW * frac
                if fillW > 0 then
                    glColor(1,1,0,0.90)
                    glRect(barLeft, barY, barLeft + fillW, barY + barH)
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
do
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

        -- Text
        glColor(1,1,1,0.75)
        glText(sec.."s", x1 + w*0.5, hy1 + 3, 11, "oc")
    end
end
     
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

    -- NEW: Update commander counts only every 15 frames
    local gf = spGetGameFrame()
    if gf % 15 == 0 then
        commanderC1, commanderC2 = GetCommanderCounts()
    end

    UpdateFade()
    SampleEco()
    BuildGraphList()
end

--[[ local function GetMetalShareLabel()
    -- Disabled → always show 0 metal, no minus
    if not metalShareEnabled or metalSharePercent == 0 then
        return "[Share: 0%, 0]"
    end

    -- metalSharePercent is KEEP fraction (0.90, 0.80, etc.)
    local keep = metalSharePercent
    local shareFraction = 1 - keep

    local cur = select(1, spGetTeamResources(Spring.GetMyTeamID(), "metal")) or 0
    local shareAmount = math.floor(cur * shareFraction)

    local pct = math.floor(shareFraction * 100 + 0.5)

    -- Active → always show minus, formatted
    return string.format(
        "[Share: %d%%, -%s]",
        pct,
        FormatNumber(shareAmount)
    )
end  ]]



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


    -- CLOSE BUTTON GEOMETRY (needed for Pause midpoint)
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = glGetTextWidth(hideLabel) * hideSize
    local hx1       = box.x2 - hideWidth - 6
    local hy1       = box.y2 - 20

------------------------------------------------------------
-- PAUSE BUTTON (directly left of [X])
------------------------------------------------------------
do
    local pauseLabel = "[Pause]"
    local pauseSize  = 14 * FONT_SCALE
    local pauseWidth = glGetTextWidth(pauseLabel) * pauseSize

    -- Position Pause directly left of the close button
    local px = hx1 - pauseWidth - 8   -- 8px gap between Pause and [X]
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
        local metalTextX = bx1 - 120   -- fixed position of metal availability 140 original
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



-- DRAW OVERLAY (COMPACT MODE)
local function DrawCompactOverlay()

UpdateConverterStats()

    local teamID     = Spring.GetMyTeamID()
    local playerName = GetPlayerNameFromTeam(teamID)
    local faction    = DetectFaction(teamID)  -- currently unused in compact mode

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

    glColor(cfg.bgColor)
    glRect(box.x1, box.y1, box.x2, box.y2)

    glColor(cfg.borderColor)
    glLineWidth(1.5)
    glBeginEnd(GL_LINES, function()
        glVertex(box.x1,box.y1); glVertex(box.x2,box.y1)
        glVertex(box.x2,box.y1); glVertex(box.x2,box.y2)
        glVertex(box.x2,box.y2); glVertex(box.x1,box.y2)
        glVertex(box.x1,box.y2); glVertex(box.x1,box.y1)
    end)

-- Title + Player Name (single row, Compact View)
glColor(cfg.titleColor)

local title = "Eco Graph: "
local titleFont = titleSize + 8
local titleW = glGetTextWidth(title) * titleFont

-- Draw "Eco Graph: "
glText(title, box.x1 + 6, box.y2 - 20, titleFont, "o")

-- Draw player name immediately after title
local teamID = viewedTeamID or Spring.GetMyTeamID()
local r, g, b = Spring.GetTeamColor(teamID)
glColor(r, g, b, 1)

-- ⭐ NEW: shorten the name
local shortName = ShortenPlayerName(playerName)

glText(shortName, box.x1 + 6 + titleW, box.y2 - 20, titleFont, "o")

-- METAL / ENERGY STATS (match Full Mode layout)
local teamID = Spring.GetMyTeamID()
local mid = (box.x1 + box.x2) * 0.5

local metalStatsX  = (box.x1 + mid) * 0.5
local energyStatsX = (mid + box.x2) * 0.5

local statsY = box.y2 - 20

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

    local centerX = (box.x1 + box.x2) * 0.5

    -- Status color (compact mode)
    local col = statusColors[status] or {1,1,1,1}
    glColor(col)
    glText(string.format("Status: %s", status),
        centerX + 35, box.y2 - 20, (fontSize + 4 * FONT_SCALE), "oc")


-- COMMANDERS ONLY (same column, resize‑safe)
do
    local c1, c2 = commanderC1, commanderC2

    -- X anchor for BOTH the label and the numbers
    -- local commandersX = metalStatsX + 105
	local commandersX = (metalStatsX + centerX) * 0.5 - 15

    -- Y positions
    local commandersLabelY = statsY
    local countY = commandersLabelY   -- same line as label

    local baseX = commandersX + 70

    -- Horizontal spacing for the numbers
    local offset = 18

    local coldColor = {0.2, 1.0, 0.2, 1.0}
    local warmColor = {1.0, 0.35, 0.2, 1.0}

    -- Label
    glColor(cfg.titleColor)
    glText("Commanders:", commandersX, commandersLabelY, fontSize, "oc")
	

    -- Numbers (same column, centered around commandersX)
    glColor(coldColor)
    glText(string.format("%d", c1), baseX - offset, countY, (fontSize + 7 * FONT_SCALE), "oc")

    glColor(1, 1, 1, 1)
    glText("vs", baseX, countY, fontSize, "oc")

    glColor(warmColor)
    glText(string.format("%d", c2), baseX + offset, countY, (fontSize + 7 * FONT_SCALE), "oc")

end
			
-- METAL INCOME/USAGE GRAPH (Compact Mode, full auto-scaling)
do
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
    local storageBarTop = box.y1 + 18      -- was + 30
    local graphTopLimit = box.y2 - 22   -- leave 60px buffer below Net: line. Top ceiling of the Metal Dual Graph

    local gy1 = storageBarTop
    local gy2 = graphTopLimit

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1

    -- BACKGROUND
    glColor(0, 0, 0, 0.25)
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
    glBeginEnd(GL_LINES, function()
        glVertex(gx1, zeroY)
        glVertex(gx2, zeroY)
    end)

    -- INCOME CURVE
    glColor(cfg.metalIncomeColor)
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
    glColor(cfg.metalUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, function()
        for i = 1, #data, 2 do
            local s  = data[i]
            local tf = (s.t - minT) / rangeT
            local vf = (s.usage - minV) / rangeV
            glVertex(gx1 + gw * tf, gy1 + gh * vf)
        end
    end)

    -- EXPOSE BOTTOM FOR STORAGE BAR
    compactGraphBottom = gy1
end

-- HISTORY SECONDS SELECTOR (Compact Mode, right side)
do
    local hx1 = centerX + 220
    local hx2 = box.x2 - 10
	local hy1 = box.y1 + 30
	local hy2 = hy1 + 20

    -- Background
    glColor(0, 0, 0, 0.25)
    glRect(hx1, hy1, hx2, hy2)

    -- Options
    local opts = cfg.historyOptions  -- {20,30,40,50,60}
    local count = #opts
    local w = (hx2 - hx1) / count

    for i = 1, count do
        local x1 = hx1 + (i-1)*w
        local x2 = x1 + w
        local sec = opts[i]

        -- Highlight selected
        if sec == cfg.historySeconds then
            glColor(1,1,1,0.15)
            glRect(x1, hy1, x2, hy2)
        end

        -- Text
        glColor(1,1,1,1)
        glText(sec.."s", x1 + w*0.5, hy1 + 3, 11, "oc")
    end
						

end

-- ENERGY INCOME/USAGE GRAPH (Compact Mode, full auto-scaling)
do
    local data = history.energy
    if #data < 2 then return end

    -- Compute center
    local centerX = box.x1 + (box.x2 - box.x1) * 0.5

    
    -- AUTO-SCALING GEOMETRY (Option A + full vertical stretch)
    -- Horizontal: 1% gap from center, 3% margin from right
    local gx1 = centerX + (box.x2 - box.x1) * 0.12
    local gx2 = box.x2 - (box.x2 - box.x1) * 0.03

    -- Vertical: stretch from top of storage bar to just below Net: line
    local storageBarTop = box.y1 + 30
    local graphTopLimit = box.y2 - 24   -- buffer below Net: line  Top ceiling for the Energy dual graph

    local gy1 = storageBarTop
    local gy2 = graphTopLimit

    local gw  = gx2 - gx1
    local gh  = gy2 - gy1

    -- BACKGROUND
    glColor(0, 0, 0, 0.25)
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
    glBeginEnd(GL_LINES, function()
        glVertex(gx1, zeroY)
        glVertex(gx2, zeroY)
    end)

    -- INCOME CURVE
    glColor(cfg.energyIncomeColor)
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
    glColor(cfg.energyUsageColor)
    glLineWidth(2.0)
    glBeginEnd(GL_LINE_STRIP, function()
        for i = 1, #data, 2 do
            local s  = data[i]
            local tf = (s.t - minT) / rangeT
            local vf = (s.usage - minV) / rangeV
            glVertex(gx1 + gw * tf, gy1 + gh * vf)
        end
    end)

    -- EXPOSE BOTTOM FOR FUTURE ELEMENTS
    compactEnergyGraphBottom = gy1
end

-- METAL STORAGE BAR (Compact Mode, bottom-anchored, layered)
do
	-- This controls left and right length of bar nudge left or right
	local barX1 = box.x1 + 150
    local barX2 = centerX - 240
    local barH  = 12
	-- Nudge the Storage bar up or down.
    local barY1 = box.y1 + 5
    local barY2 = barY1 + barH

    -- Values
    local cur   = mCur or 0
    local max   = mStorage or 1
    local share = metalShare or 0

    -- Background bar (dark base)
    -- glColor(0, 0, 0, 0.35)
	glColor(0, 1, 1, 0.20)
    glRect(barX1, barY1, barX2, barY2)

    -- Fill overlay (Metal Inc color)
    local fillX = barX1 + (cur / max) * (barX2 - barX1)
    glColor(cfg.metalIncomeColor)
    glRect(barX1, barY1, fillX, barY2)

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
    local sliderHalfWidth = barH * 0.9
    local sliderHeightAdd = barH * 1.2

    shareIndicatorArea[res] = {
        barX1 + (value * barWidth) - sliderHalfWidth,
        barY1 - sliderHeightAdd,
        barX1 + (value * barWidth) + sliderHalfWidth,
        barY2 + sliderHeightAdd
    }

    glColor(1, 0.2, 0.2, 1)
    local cx = (shareIndicatorArea[res][1] + shareIndicatorArea[res][3]) * 0.5
    local cy = (shareIndicatorArea[res][2] + shareIndicatorArea[res][4]) * 0.5
    local r  = sliderHalfWidth
    glRect(cx - r, cy - r, cx + r, cy + r)
end


    -- Text label
-- Storage total (aligned with PP: No)
glColor(1, 1, 1, 1)
local text = string.format("[%.1fK]", max/1000)

local textY = box.y1 + 8   -- EXACT same Y as PP: No
glText(text, barX2 + 60, textY, fontSize, "or")

end

-- ENERGY STORAGE BAR (Compact Mode, bottom‑anchored, mirrored)
do
    -- Values
    local cur   = eCur or 0
    local max   = eStorage or 1
    local frac  = math.max(0, math.min(1, cur / max))

    --------------------------------------------------------
    -- GEOMETRY (mirrored from Metal side)
    --------------------------------------------------------
    -- Metal uses:
    --   barX1 = box.x1 + 150
    --   barX2 = centerX - 240
    --
    -- So Energy mirrors to the right:
    local barX1 = centerX + 240
    local barX2 = box.x2 - 150

    local barH  = 12
    local barY1 = box.y1 + 5
    local barY2 = barY1 + barH

    -- BAR BACKGROUND (Full View yellow tint)
    glColor(1, 1, 0, 0.20)
    glRect(barX1, barY1, barX2, barY2)

    
    -- BAR FILL (Full View bright yellow)
    local fillX = barX1 + frac * (barX2 - barX1)
    if frac > 0 then
        glColor(1, 1, 0, 0.90)
        glRect(barX1, barY1, fillX, barY2)
    end

    -- WHITE TICK (current energy)
    if frac > 0 then
        glColor(1, 1, 1, 1)
        glRect(fillX - 1, barY1 - 2, fillX + 1, barY2 + 2)
    end


------------------------------------------------------------
-- ENERGY → METAL CONVERSION SLIDER (Compact View)
------------------------------------------------------------
do
    -- read mmLevel (0–1)
    local mm = draggingConversionIndicatorValue
    if mm == nil then
        mm = (Spring.GetTeamRulesParam(Spring.GetMyTeamID(), "mmLevel") or 1)
    end

    -- same bar geometry as auto‑share slider
    local barWidth = barX2 - barX1
    local sliderHalfWidth = barH * 0.9
    local sliderHeightAdd = barH * 1.2

    -- position: immediately LEFT of the red auto‑share slider
    local convX = barX1 + (mm * barWidth)

    conversionIndicatorArea = {
        convX - sliderHalfWidth,
        barY1 - sliderHeightAdd,
        convX + sliderHalfWidth,
        barY2 + sliderHeightAdd
    }

    -- beige knob (Top Bar color)
    glColor(0.95, 0.95, 0.7, 1)
    local cx = (conversionIndicatorArea[1] + conversionIndicatorArea[3]) * 0.5
    local cy = (conversionIndicatorArea[2] + conversionIndicatorArea[4]) * 0.5
    local r  = sliderHalfWidth
    glRect(cx - r, cy - r, cx + r, cy + r)
end


------------------------------------------------------------
-- AUTO‑SHARE SLIDER (ENERGY) — Compact View
------------------------------------------------------------
do
    local res = "energy"

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
    local sliderHalfWidth = barH * 0.9
    local sliderHeightAdd = barH * 1.2

    shareIndicatorArea[res] = {
        barX1 + (value * barWidth) - sliderHalfWidth,
        barY1 - sliderHeightAdd,
        barX1 + (value * barWidth) + sliderHalfWidth,
        barY2 + sliderHeightAdd
    }

    glColor(1, 0.2, 0.2, 1)
    local cx = (shareIndicatorArea[res][1] + shareIndicatorArea[res][3]) * 0.5
    local cy = (shareIndicatorArea[res][2] + shareIndicatorArea[res][4]) * 0.5
    local r  = sliderHalfWidth
    glRect(cx - r, cy - r, cx + r, cy + r)
end


    -- STORAGE TOTAL TEXT (mirrors Metal side)
    glColor(1, 1, 1, 1)
    local text = string.format("[%.1fK]", max / 1000)

    -- Same vertical alignment as Metal
    local textY = box.y1 + 8

    -- Same horizontal offset as Metal: +45
    glText(text, barX2 + 55, textY, fontSize, "or")
end

-- BIG METAL AVAILABLE (Compact Mode, Full View style)
do
    local myTeamID = Spring.GetMyTeamID()
    if myTeamID then
        local mCur = select(1, Spring.GetTeamResources(myTeamID, "metal")) or 0
    local metalText = "Metal: " .. FormatCompact(mCur)

        -- Full View font size
        local metalFont = (fontSize + 6 * FONT_SCALE)

        -- Full View color (lighter aqua)
        glColor(0.6, 0.9, 1.0, 1.0)

        -- Recompute bar geometry
        local barX1 = box.x1 + 150
        local barX2 = centerX - 240
        local barY1 = box.y1 + 5

        -- Position: nicely to the right of the storage bar
        local metalTextX = barX2 + 90     -- ← adjust this if needed
        local metalTextY = barY1 - 2

        glText(metalText, metalTextX, metalTextY, metalFont, "l")
        ------------------------------------------------------------
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
gl.Texture(false)

    end
end

-- BIG ENERGY AVAILABLE (Compact Mode, bottom-aligned)
do
    local myTeamID = Spring.GetMyTeamID()
    if myTeamID then
        local eCur = select(1, Spring.GetTeamResources(myTeamID, "energy")) or 0
        local energyText = "Energy: " .. FormatCompact(eCur)

        -- Full View font size
        local energyFont = (fontSize + 6 * FONT_SCALE)

        -- Full View energy color
        glColor(1, 1, 0, 0.90)

        -- Recompute Energy bar geometry (must match your actual bar)
        local barX1 = centerX + 300
        local barX2 = box.x2 - 150
        local barY1 = box.y1 + 5

        -- Mirror Metal placement:
        -- Metal uses: barX2 + 90
        -- So Energy uses: barX1 - 90
        local energyTextX = barX1 - 90
        local energyTextY = barY1 - 2

        glText(energyText, energyTextX, energyTextY, energyFont, "r")

------------------------------------------------------------
-- ENERGY ICON ABOVE ENERGY AVAILABLE (Compact View)
------------------------------------------------------------
local iconSize = 38

-- Center icon horizontally over the Energy Available text
local iconX = energyTextX - (iconSize * 0.5) - 38  -- Higher moves left

-- Place icon above the text
local iconY = energyTextY + energyFont + 6 - 15

gl.Texture(energyIconPath)
gl.Color(1,1,1,1)
gl.TexRect(iconX, iconY, iconX + iconSize, iconY + iconSize)
gl.Texture(false)


    end
end

-- TIDAL ONLY (Compact View — single line)
do
    local tidal = Game.tidal or 0

    -- X anchor centered between Status and Energy Inc
    local tidalX = (centerX + energyStatsX) * 0.5 + 15

    -- Same Y as Energy Inc (top row)
    local tidalY = statsY

    local tidalText = string.format("Tidal: %.1f", tidal)

    glColor(1, 1, 1, 1)
    glText(tidalText, tidalX, tidalY, fontSize, "oc")
end

-- GAME SPEED + PINPOINTER + BUILD POWER (Compact Mode, lower-left corner)
do
    local px = box.x1 + 8
    local py = box.y1 + 8

    -------------------------------------------------
    -- Sp: (game speed)
    -------------------------------------------------
    local speed = Spring.GetGameSpeed() or 1
    local spText = string.format("Sp: %.1f", speed)

    glColor(1, 1, 1, 1)
    glText(spText, px, py + 16, font_scale, "o")

    -------------------------------------------------
    -- PP: (pinpointer)
    -------------------------------------------------
local currentAlly = GetCurrentViewedAllyTeamID()
local count = allyPinCount[currentAlly] or 0
    local has = (count > 0)
    local ppText = has and string.format("PP: Yes(%d)", count) or "PP: None"

    -------------------------------------------------
    -- BP: (build power)
    -------------------------------------------------
    local bp = GetTotalBuildPower(Spring.GetMyTeamID())
    local bpText = "BP: " .. FormatIncome(bp)

    -------------------------------------------------
    -- Combined PP + BP row
    -------------------------------------------------
    local rowText = ppText .. " | " .. bpText
    glText(rowText, px, py, font_scale, "o")

    -------------------------------------------------
    -- Hover rect (covers Sp + PP + BP)
    -------------------------------------------------
    ppRect = {
        x1 = px - 4,
        y1 = py - 4,
        x2 = px + 180,   -- widened for BP
        y2 = py + 36,
    }
end

-- TOOLTIP FOR SP / PP / BP (Compact View)
do
    local mx, my = Spring.GetMouseState()
    if ppRect and mx >= ppRect.x1 and mx <= ppRect.x2 and my >= ppRect.y1 and my <= ppRect.y2 then

        -- Left column (labels)
        local label1 = "SP:"
        local label2 = "PP:"
        local label3 = "BP:"

        -- Right column (descriptions)
        local desc1 = "= Game Speed"
        local desc2 = "= Team Pinpointer Count"
        local desc3 = "= Total Build Power"

        local pad = 6

        -- Measure column widths
        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3)
        ) * fontSize

        local descW = math.max(
            glGetTextWidth(desc1),
            glGetTextWidth(desc2),
            glGetTextWidth(desc3)
        ) * fontSize

        -- Total width
        local tw = labelW + descW + pad * 3

        -- Height for 3 rows
        local th = fontSize * 3 + pad * 4

        -- LOWER-RIGHT of mouse
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

        -- Text (two columns)
        glColor(0, 0, 0, 1)

        -- Row 1
        glText(label1, tipX + pad,                     tipY + th - fontSize - pad, fontSize, "lo")
        glText(desc1,  tipX + pad + labelW + pad,      tipY + th - fontSize - pad, fontSize, "lo")

        -- Row 2
        glText(label2, tipX + pad,                     tipY + th - fontSize*2 - pad*2, fontSize, "lo")
        glText(desc2,  tipX + pad + labelW + pad,      tipY + th - fontSize*2 - pad*2, fontSize, "lo")

        -- Row 3
        glText(label3, tipX + pad,                     tipY + pad, fontSize, "lo")
        glText(desc3,  tipX + pad + labelW + pad,      tipY + pad, fontSize, "lo")
    end
end


    glColor(1,1,1,0.8)
    glRect(box.x2 - resizeHandleSize, box.y1,
           box.x2, box.y1 + resizeHandleSize)         

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

------------------------------------------------------------
-- PAUSE BUTTON (Compact View, directly left of [X])
------------------------------------------------------------
do
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = glGetTextWidth(hideLabel) * hideSize

    -- Same geometry as DrawHideButton()
    local hx1 = box.x2 - hideWidth - 6
    local hy1 = box.y2 - 20

    -- Pause button
    local pauseLabel = "[Pause]"
    local pauseSize  = 14 * FONT_SCALE
    local pauseWidth = glGetTextWidth(pauseLabel) * pauseSize

    -- Position Pause directly left of [X]
    local px = hx1 - pauseWidth - 8
    local py = hy1

    -- Save hitbox for click detection
    pauseButtonRect = {
        x1 = px,
        y1 = py - pauseSize,
        x2 = px + pauseWidth,
        y2 = py + pauseSize
    }

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

local eText = "-" .. formatK(math.abs(eVal or 0), "e")
local mText = "+" .. formatK(math.abs(mVal or 0), "m")
local uText = string.format("%d%%", convUtil or 0)

    -- ultra-compact reserved widths
    local eW = glGetTextWidth("-99.9ke") * pauseSize
    local mW = glGetTextWidth("+99.9km") * pauseSize
    local uW = glGetTextWidth("100%")    * pauseSize
    local bracketW = glGetTextWidth("[") * pauseSize * 0.9

    local totalW = bracketW + eW + mW + uW + bracketW

    -- position: LEFT of Pause button
    local sx = px - 4 - totalW
    local sy = py

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
    convStatRect = {
        x1 = sx,
        y1 = sy - pauseSize,
        x2 = sx + totalW,
        y2 = sy + pauseSize
    }
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

------------------------------------------------------------
-- ENERGY → METAL CONVERSION TOOLTIP (Compact View)
------------------------------------------------------------
do
    local mx, my = Spring.GetMouseState()

    if convStatRect
    and mx >= convStatRect.x1 and mx <= convStatRect.x2
    and my >= convStatRect.y1 and my <= convStatRect.y2 then

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

        local tw = math.max(titleW, labelW + valueW + pad * 3) + pad * 2
        local th = titleSize + (fontSize * 3) + pad * 6

        local tipX = mx + 18
        local tipY = my - th - 18

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
    end
end


end  -- end of DrawCompactOverlay()

-- WIDGET CALLINS
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
    local hx1 = box.x2 - hideWidth - 6
    local hy1 = box.y2 - 20



    
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

    
    -- BAR-SAFE DISABLE HANDLING
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
        if graphList then glCallList(graphList) end
        DrawOverlay()

-- PINPOINTER STATUS + GAME SPEED (lower-left corner)
do
local currentAlly = GetCurrentViewedAllyTeamID()
local count = allyPinCount[currentAlly] or 0
    local has = (count > 0)
    local ppText = has and string.format("PP: Yes(%d)", count) or "PP: None"

    -- Game speed
    local speed = Spring.GetGameSpeed() or 1
    local spText = string.format("Sp: %.1f", speed)

    -- Base position
    local px = box.x1 + 8
    local py = box.y1 + 8

    glColor(1, 1, 1, 1)

    -- Draw speed ABOVE PP
    glText(spText, px, py + 16, font_scale, "o")

    -- Build Power (dynamic)
    local bp = GetTotalBuildPower(Spring.GetMyTeamID())
    local bpText = "BP: " .. FormatIncome(bp)

    -- Combined PP + BP row
    local rowText = ppText .. " | " .. bpText
    glText(rowText, px, py, font_scale, "o")

    -- hover rect for PP + BP + Sp tooltip
    ppRect = {
        x1 = box.x1 + 4,
        y1 = box.y1 + 4,
        x2 = box.x1 + 160,   -- widened for BP
        y2 = box.y1 + 40,
    }
end

-- PINPOINTER + BUILD POWER + SPEED TOOLTIP (Two-Column)
do
    local mx, my = Spring.GetMouseState()
    if ppRect and mx >= ppRect.x1 and mx <= ppRect.x2 and my >= ppRect.y1 and my <= ppRect.y2 then

        -- Left column (labels)
        local label1 = "SP:"
        local label2 = "PP:"
        local label3 = "BP:"

        -- Right column (descriptions)
        local desc1 = "= Game Speed"
        local desc2 = "= Team Pinpointer Count"
        local desc3 = "= Total Build Power"

        local pad = 6

        -- Measure column widths
        local labelW = math.max(
            glGetTextWidth(label1),
            glGetTextWidth(label2),
            glGetTextWidth(label3)
        ) * fontSize

        local descW = math.max(
            glGetTextWidth(desc1),
            glGetTextWidth(desc2),
            glGetTextWidth(desc3)
        ) * fontSize

        -- Total width
        local tw = labelW + descW + pad * 3

        -- Height for 3 rows
        local th = fontSize * 3 + pad * 4

        -- LOWER-RIGHT of mouse cursor (matches income tooltips)
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

        -- Text (two columns)
        glColor(0, 0, 0, 1)

        -- Row 1
        glText(label1, tipX + pad,                     tipY + th - fontSize - pad, fontSize, "lo")
        glText(desc1,  tipX + pad + labelW + pad,      tipY + th - fontSize - pad, fontSize, "lo")

        -- Row 2
        glText(label2, tipX + pad,                     tipY + th - fontSize*2 - pad*2, fontSize, "lo")
        glText(desc2,  tipX + pad + labelW + pad,      tipY + th - fontSize*2 - pad*2, fontSize, "lo")

        -- Row 3
        glText(label3, tipX + pad,                     tipY + pad, fontSize, "lo")
        glText(desc3,  tipX + pad + labelW + pad,      tipY + pad, fontSize, "lo")
    end
end


-- METAL INC TOOLTIP (50% wider, tight vertical spacing)
do
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
    end
end

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

            -- LOWER‑RIGHT of mouse cursor
            local tipX = mx + 18
            local tipY = my - th - 18

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

    -- 1. FLOATING UNHIDE BUTTON (must be FIRST)
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

    -- 3. METAL DROPDOWN OPTION CLICK (CHECK FIRST)
    if metalShareDropdownOpen and metalShareOptionRects then
        for i, r in ipairs(metalShareOptionRects) do
            if PointInRect(mx, my, r.x1, r.y1, r.x2, r.y2) then

                local opt = metalShareOptions[i]

                -- Disable option
                if opt == "Disable" then
                    metalShareEnabled = false
                    metalSharePercent = 0
                    metalShareDropdownOpen = false
                    if graphList then glDeleteList(graphList) graphList = nil end
                    return true
                end

					metalShareEnabled = true
                    metalSharePercent = opt   -- opt is already share fraction
					Spring.SetConfigFloat("eco_metal_share_keep_percent", metalSharePercent)

                metalShareDropdownOpen = false
                if graphList then glDeleteList(graphList) graphList = nil end
                return true
            end
        end
    end

-- Click outside dropdown closes it (but NOT when clicking the button)
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

-- 4. ENERGY DROPDOWN OPTION CLICK (CHECK SECOND)
if energyShareDropdown and energyShareOptionRects then
    for i, r in ipairs(energyShareOptionRects) do
        if PointInRect(mx, my, r.x1, r.y1, r.x2, r.y2) then
            local opt = energyShareOptions[i]

            if opt == "Disable" then
                energyShareEnabled = false
                energySharePercent = 0
            else
                energyShareEnabled = true
                energySharePercent = opt   -- opt is share%
            end

            -- Save to config (MATCHES METAL)
            Spring.SetConfigFloat("eco_energy_share_percent", energySharePercent)

            energyShareDropdown = false
            return true
        end
    end

    -- Click outside dropdown closes it
    if not PointInRect(mx, my,
        energyShareButton.x1,
        energyShareButton.y1,
        energyShareButton.x2,
        energyShareButton.y2)
    then
        energyShareDropdown = false
    end
end

    -- 5. CLICK OUTSIDE MAIN BOX (but allow dropdown clicks)
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

        -- Energy dropdown already handled above
        return false
    end

-- Pause button click
if pauseButtonRect
and mx >= pauseButtonRect.x1 and mx <= pauseButtonRect.x2
and my >= pauseButtonRect.y1 and my <= pauseButtonRect.y2 then
    Spring.SendCommands("pause")
    return true
end
 
    -- 6. CLOSE BUTTON [X]
    local hideLabel = "[X]"
    local hideSize  = 14 * FONT_SCALE
    local hideWidth = gl.GetTextWidth(hideLabel) * hideSize
    local hx1       = box.x2 - hideWidth - 6
    local hy1       = box.y2 - 20

    if mx >= hx1 and mx <= hx1 + hideWidth
    and my >= hy1 - hideSize and my <= hy1 + hideSize then

        if widgetHandler and widgetHandler.RemoveWidget then
            widgetHandler:RemoveWidget(widget)
        end
        return true
    end

--[[     -- 7. COMPACT TOGGLE (Ctrl + LMB)
    if button == 1 and ctrl then
        compactMode = not compactMode
        if graphList then glDeleteList(graphList) graphList = nil end
        return true
    end
 ]]
    
    -- 8. PAUSE / RESET (MMB)
    if button == 2 then
        if ctrl then
            ResetHistory()
        else
            paused = not paused
        end
        return true
    end

    -- 9. METAL SHARE BUTTON (ONLY WHEN DROPDOWN CLOSED)
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
-- HISTORY SECONDS SELECTOR CLICK (Compact + Full View)
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

    -- ENERGY → METAL conversion slider
    if conversionIndicatorArea and conversionIndicatorArea[1] then
        if mx >= conversionIndicatorArea[1]
        and mx <= conversionIndicatorArea[3]
        and my >= conversionIndicatorArea[2]
        and my <= conversionIndicatorArea[4] then
            draggingConversionIndicator = true
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

function widget:MouseMove(mx,my,dx,dy,button)
    if not showWidget then return false end

    ------------------------------------------------------------
    -- AUTO‑SHARE SLIDER DRAGGING (Compact View)
    ------------------------------------------------------------
    if compactMode and draggingShareIndicator then
        local res = draggingShareIndicator

        -- get bar geometry
        local barX1, barX2
        if res == "metal" then
            barX1 = box.x1 + 150
            barX2 = (box.x1 + (box.x2 - box.x1) * 0.5) - 240
        else
            barX1 = (box.x1 + (box.x2 - box.x1) * 0.5) + 240
            barX2 = box.x2 - 150
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

    -- compute bar geometry (same as energy auto-share bar)
    local barX1 = (box.x1 + (box.x2 - box.x1) * 0.5) + 240
    local barX2 = box.x2 - 150
    local barWidth = barX2 - barX1

    -- mouse X → mmLevel (0 on left, 1 on right)
    local mm = (mx - barX1) / barWidth
    if mm < 0 then mm = 0 end
    if mm > 1 then mm = 1 end

    -- clamp to 10%–90% keep (same visual limits as Top Bar)
    if mm < 0.10 then mm = 0.10 end
    if mm > 0.90 then mm = 0.90 end

    draggingConversionIndicatorValue = mm

    -- ⭐ engine treats this as "percent to KEEP"
    local convValue = math.floor(mm * 100 + 0.5)
    Spring.SendLuaRulesMsg(string.format("%c%i", 137, convValue))

    return true
end

    ------------------------------------------------------------
    -- FREEFORM RESIZING
    ------------------------------------------------------------
    if resizing and button == 1 then
        local w = mx - box.x1

        local minW = vsx * 0.45
        local maxW = vsx * 0.95
        if w < minW then w = minW end
        if w > maxW then w = maxW end

        local top = box.y2
        local h   = top - my

        local minH = vsy * 0.052
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


function widget:MouseRelease(mx,my,button)

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