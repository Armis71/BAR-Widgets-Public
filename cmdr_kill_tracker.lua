------------------------------------------------------------
-- Commander Kill Tracker v1.50 (Scroll Fix)
-- Correct scroll range + global maxScroll + standard wheel
------------------------------------------------------------

function widget:GetInfo()
    return {
        name      = "Commander Kill Tracker",
        desc      = "Tracks commander kills with icons, team colors, tooltips, AI labels, totals, sorting, draggable/resizable, replay-safe. Scrollbar appears only when needed.",
        date      = "2026-01-03",
        license   = "GPLv2",
        layer     = 0,
        enabled   = true,
    }
end

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local cfg = {
    x = 0.02,
    y = 0.70,
    w = 0.24,
    h = 0.30,
}

local BASE_ICON_SIZE = 48
local ICON_SIZE      = math.floor(BASE_ICON_SIZE * 1.2)
local RESIZE_HANDLE  = 18

------------------------------------------------------------
-- SHORTCUTS
------------------------------------------------------------

local spGetUnitTeam        = Spring.GetUnitTeam
local spGetUnitDefID       = Spring.GetUnitDefID
local spGetPlayerInfo      = Spring.GetPlayerInfo
local spGetPlayerList      = Spring.GetPlayerList
local spGetTeamInfo        = Spring.GetTeamInfo
local spGetTeamList        = Spring.GetTeamList
local spGetSpectatingState = Spring.GetSpectatingState
local spGetGameFrame       = Spring.GetGameFrame
local spGetViewGeometry    = Spring.GetViewGeometry
local spGetTeamColor       = Spring.GetTeamColor
local spGetMouseState      = Spring.GetMouseState

local glColor        = gl.Color
local glText         = gl.Text
local glRect         = gl.Rect
local glTexture      = gl.Texture
local glTexRect      = gl.TexRect
local glGetTextWidth = gl.GetTextWidth
local glScissor      = gl.Scissor

------------------------------------------------------------
-- STATE
------------------------------------------------------------
-- Track last weapon used by the final attacker
local lastWeaponByAttacker = {}

local commanderKills       = {}
local commanderKillReasons = {}
local commanderUnitDefIDs  = {}

local lastFrame = 0
local dragging   = false
local resizing   = false
local dragOffsetX = 0
local dragOffsetY = 0

widget.box          = {}
widget.iconHitboxes = {}

local tooltipText   = nil
local tooltipMouseX = nil
local tooltipMouseY = nil

local aiTeamNameMap = {}
local widgetFlashFrame = nil

-- Scroll state
local scrollOffset = 0
local scrollStep   = 40
local contentHeight = 0
local maxScroll = 0   -- GLOBAL maxScroll (fixes early clamp)

-- Thick scrollbar width
local scrollbarWidth = 12

-- Drag-scroll state
local draggingScrollbar = false
local scrollbarDragOffset = 0

--------------------------------------------------------------
-- To Capture Weapon Hits
--------------------------------------------------------------
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, attackerID, attackerDefID, attackerTeam)
    if not attackerID then
        return
    end

    -- BAR uses -1 for beam/continuous weapons; ignore those
    if weaponDefID and weaponDefID >= 0 then
        lastWeaponByAttacker[attackerID] = weaponDefID
    end
	
	Spring.Echo("DMG", unitID, "weaponDefID=", weaponDefID)
end

------------------------------------------------------------
-- UTILS
------------------------------------------------------------

local function DetectCommanderDefs()
    if not UnitDefs then return end
    for udid, ud in pairs(UnitDefs) do
        if ud then
            local name = ud.name or ""
            if (ud.customParams and ud.customParams.iscommander)
            or ud.deathExplosion == "commanderexplosion"
            or name:find("armcom") or name:find("corcom") or name:find("legcom")
            then
                commanderUnitDefIDs[udid] = true
            end
        end
    end
end

local function FormatTimestamp(frame)
    if not frame then return "" end
    local seconds = math.floor(frame / 30)
    return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
end

local function AssignCustomAINames()
    if next(aiTeamNameMap) ~= nil then return end
    local teams = spGetTeamList()
    if not teams then return end
    for _, teamID in ipairs(teams) do
        local _, _, _, isAI = spGetTeamInfo(teamID)
        if isAI then
            aiTeamNameMap[teamID] = "Player (AI)"
        end
    end
end

local function GetKillerLabel(attackerID)
    if not attackerID then return nil,nil,nil end
    local team = spGetUnitTeam(attackerID)
    if not team then return nil,nil,nil end

    if aiTeamNameMap[team] then
        return "T"..team, aiTeamNameMap[team], team
    end

    local players = spGetPlayerList(team, true)
    if players then
        for _, pid in ipairs(players) do
            local name, active, spec, pTeam = spGetPlayerInfo(pid)
            if pTeam == team and not spec and name then
                return "P"..pid, tostring(name), team
            end
        end
    end

    return "T"..team, "Team "..team, team
end

local function GetVictimName(teamID)
    if aiTeamNameMap[teamID] then return aiTeamNameMap[teamID] end
    local players = spGetPlayerList(teamID, true)
    if players then
        for _, pid in ipairs(players) do
            local name, _, _, pTeam = spGetPlayerInfo(pid)
            if pTeam == teamID and name then return tostring(name) end
        end
    end
    return "Disconnected"
end

------------------------------------------------------------
-- RESET ON REPLAY JUMP
------------------------------------------------------------

local function ResetAll()
    commanderKills       = {}
    commanderKillReasons = {}
end

------------------------------------------------------------
-- ICON DRAW
------------------------------------------------------------

local function DrawUnitIcon(unitDefID, x, y, size)
    if not unitDefID then return end
    glTexture("#"..unitDefID)
    glTexRect(x, y, x+size, y+size)
    glTexture(false)
end

------------------------------------------------------------
-- WIDGET EVENTS
------------------------------------------------------------

function widget:Initialize()
    DetectCommanderDefs()
    AssignCustomAINames()
end

function widget:GameFrame(frame)
    if frame < lastFrame then ResetAll() end
    lastFrame = frame
    if frame < 90 then AssignCustomAINames() end
end

--------------------------------------------------------------------------------
-- CHUNK 1 — TOP BAR COMMANDER DETECTION
--------------------------------------------------------------------------------

local function IsCommanderDef(unitDefID)
    if not unitDefID then return false end
    local ud = UnitDefs[unitDefID]
    if not ud then return false end
    local cp = ud.customParams or {}

    -- Top Bar commander detection logic (full)
    if cp.iscommander then return true end
    if cp.commtype then return true end
    if cp.dynamic_comm then return true end
    if cp.iscommandervariant then return true end
    if cp.iscommanderupgrade then return true end
    if cp.iscommanderbase then return true end
    if cp.iscommanderbuild then return true end
    if cp.iscommanderfactory then return true end
    if cp.iscommander_morph then return true end
    if cp.iscommanderform then return true end
    if cp.iscommanderunit then return true end
    if cp.iscommanderclass then return true end
    if cp.iscommanderhero then return true end
    if cp.iscommanderboss then return true end
    if cp.iscommanderelite then return true end
    if cp.iscommanderprototype then return true end
    if cp.iscommanderexperimental then return true end
    if cp.iscommanderflagship then return true end
    if cp.iscommanderflagshipvariant then return true end

    -- Explosion-based detection
    if ud.deathExplosion == "commanderexplosion" then return true end

    return false
end

--------------------------------------------------------------------------------
-- CHUNK 2 — SELF-DESTRUCT DETECTION
--------------------------------------------------------------------------------

local function IsSelfDestruct(unitID, unitTeam)
    if not unitID then return false end

    -- Rules params used by BAR gadgets
    local sd1 = Spring.GetUnitRulesParam(unitID, "selfDestruct")
    local sd2 = Spring.GetUnitRulesParam(unitID, "selfdCountdown")
    local sd3 = Spring.GetUnitRulesParam(unitID, "selfdTimer")

    if sd1 or sd2 or sd3 then
        return true
    end

    -- Engine sometimes reports attackerID = victimID for self-D
    -- But since we removed attackerID from signature, we detect via rules params only.
    return false
end

--------------------------------------------------------------------------------
-- CHUNK 3 — ATTACKER RESOLUTION (TOP BAR LOGIC)
--------------------------------------------------------------------------------

local function ResolveAttacker(unitID, unitTeam)
    -- 1. BAR gadgets store the REAL attacker for nukes and AOE
    local lastID   = Spring.GetUnitRulesParam(unitID, "lastAttacker")
    local lastTeam = Spring.GetUnitRulesParam(unitID, "lastDamageTeam")
    local lastDef  = Spring.GetUnitRulesParam(unitID, "lastDamageDefID")

    if lastID and lastTeam and lastDef and lastID ~= unitID then
        return lastID, lastTeam, lastDef
    end

    -- 2. Fallback: engine's last attacker (may be nil for nukes)
    local last = Spring.GetUnitLastAttacker(unitID)
    if last and last ~= unitID then
        local team = Spring.GetUnitTeam(last)
        local def  = Spring.GetUnitDefID(last)
        if team and def then
            return last, team, def
        end
    end

    return nil, nil, nil
end

--------------------------------------------------------------------------------
-- CHUNK 4 — CHAIN-EXPLOSION ROOT TRACING
--------------------------------------------------------------------------------

local function ResolveChainExplosionRoot(unitID, attackerID, attackerTeam, attackerDefID)
    -- BAR gadgets store the root attacker for commander explosions
    local rootID   = Spring.GetUnitRulesParam(unitID, "commanderExplosionRoot")
    local rootTeam = Spring.GetUnitRulesParam(unitID, "commanderExplosionRootTeam")
    local rootDef  = Spring.GetUnitRulesParam(unitID, "commanderExplosionRootDef")

    if rootID and rootTeam and rootDef then
        return rootID, rootTeam, rootDef
    end

    -- If no chain root, return original attacker
    return attackerID, attackerTeam, attackerDefID
end

--------------------------------------------------------------------------------
-- CHUNK 5 — FINAL KILL-RECORDING INTEGRATION
--------------------------------------------------------------------------------

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID_raw, attackerDefID_raw, attackerTeam_raw, weaponDefID_raw)

    -- Capture raw engine weaponDefID BEFORE Top Bar overrides it
    local rawWeaponDefID = weaponDefID_raw

    if not IsCommanderDef(unitDefID) then
        return
    end

    -- Ignore self-destruct (Ctrl+B)
    if IsSelfDestruct(unitID, unitTeam) then
        return
    end

    ------------------------------------------------------
    -- Resolve attacker using Top Bar logic
    ------------------------------------------------------
    local attackerID, attackerTeam, attackerDefID = ResolveAttacker(unitID, unitTeam)

    if not attackerID or not attackerTeam or attackerTeam == unitTeam then
        return
    end

    -- Chain-explosion root tracing
    attackerID, attackerTeam, attackerDefID =
        ResolveChainExplosionRoot(unitID, attackerID, attackerTeam, attackerDefID)

    if not attackerID or not attackerTeam or attackerTeam == unitTeam then
        return
    end

    ------------------------------------------------------
    -- Killer label + victim name
    ------------------------------------------------------
    local killerKey, killerName, killerTeamID = GetKillerLabel(attackerID)
    if not killerKey then return end

    local victimName = GetVictimName(unitTeam)

    ------------------------------------------------------
    -- FINAL WEAPON RESOLUTION (Unified logic)
    ------------------------------------------------------
    local weaponName = "Explosion"

    -- 1. Prefer raw engine weaponDefID (old working behavior)
    if rawWeaponDefID and rawWeaponDefID >= 0 and WeaponDefs[rawWeaponDefID] then
        weaponName = WeaponDefs[rawWeaponDefID].description or weaponName
    end

    -- 2. Fallback: last weapon used by attacker (Option C)
    local trackedWeapon = lastWeaponByAttacker[attackerID]
    if trackedWeapon and WeaponDefs[trackedWeapon] then
        weaponName = WeaponDefs[trackedWeapon].description or weaponName
    end

    -- cleanup
    lastWeaponByAttacker[attackerID] = nil

    ------------------------------------------------------
    -- Record kill
    ------------------------------------------------------
    commanderKills[killerKey] = (commanderKills[killerKey] or 0) + 1

    commanderKillReasons[killerKey] = commanderKillReasons[killerKey] or {}
    table.insert(commanderKillReasons[killerKey], {
        killerName        = killerName,
        killerTeamID      = killerTeamID,
        victimName        = victimName,
        victimTeamID      = unitTeam,
        attackerDefID     = attackerDefID,
        weaponName        = weaponName,
        timestamp         = Spring.GetGameFrame(),
        victimFlashFrame  = Spring.GetGameFrame(),
    })

    widgetFlashFrame = Spring.GetGameFrame()
end


------------------------------------------------------------
-- DRAW PANEL
------------------------------------------------------------

local function DrawPanel()
    local vsx, vsy = spGetViewGeometry()
    local x1 = vsx * cfg.x
    local y1 = vsy * cfg.y
    local w  = vsx * cfg.w
    local h  = vsy * cfg.h

    if widgetFlashFrame then
        local age = spGetGameFrame() - widgetFlashFrame
        if age < 45 then
            local t = age / 45
            local pulse = math.abs(math.sin(t * math.pi * 7))
            glColor(1,1,0.4,pulse*0.55)
            glRect(x1-4, y1-4, x1+w+4, y1+h+4)
            glColor(1,1,1,1)
        else
            widgetFlashFrame = nil
        end
    end

    widget.box = { x1=x1, y1=y1, x2=x1+w, y2=y1+h }
    widget.iconHitboxes = {}

    glColor(0,0,0,0.65)
    glRect(x1, y1, x1+w, y1+h)
	
	
	--------------------------------------------------------
-- WHITE BORDER (matches Eco Graph / Energy Conversion)
--------------------------------------------------------

-- Outer bright border -- set at 0.50
glColor(1, 1, 1, 0.50)
glRect(x1, y1, x1+w, y1+1)         -- bottom
glRect(x1, y1+h-1, x1+w, y1+h)     -- top
glRect(x1, y1, x1+1, y1+h)         -- left
glRect(x1+w-1, y1, x1+w, y1+h)     -- right

-- Inner subtle highlight
glColor(1, 1, 1, 0.05)
glRect(x1+1, y1+1, x1+w-1, y1+2)         -- bottom inner
glRect(x1+1, y1+h-2, x1+w-1, y1+h-1)     -- top inner
glRect(x1+1, y1+1, x1+2, y1+h-1)         -- left inner
glRect(x1+w-2, y1+1, x1+w-1, y1+h-1)     -- right inner

glColor(1,1,1,1)
	

    glColor(1,1,1,1)
	-- Change title fontsize -- currently at 16
    glText(widget:GetInfo().name..":", x1+10, y1+h-24, 16, "o")

    --------------------------------------------------------
    -- APPLY SCROLL OFFSET (TOP-ALIGNED)
    --------------------------------------------------------
    local y = y1 + h - 48 - scrollOffset
    local startY = y

    --------------------------------------------------------
    -- CLIPPING (tight to widget)
    --------------------------------------------------------
    glScissor(x1, y1, w, h)

    --------------------------------------------------------
    -- SORT KILLERS
    --------------------------------------------------------
    local sortedKillers = {}
    for killerKey, total in pairs(commanderKills) do
        sortedKillers[#sortedKillers+1] = { key=killerKey, total=total }
    end
    table.sort(sortedKillers, function(a,b) return a.total > b.total end)

    --------------------------------------------------------
    -- DRAW LIST
    --------------------------------------------------------
    for _, data in ipairs(sortedKillers) do
        local killerKey = data.key
        local total     = data.total
        local entries   = commanderKillReasons[killerKey]

        if entries and #entries > 0 then
            local first = entries[1]
            local kr,kg,kb = spGetTeamColor(first.killerTeamID)
            glColor(kr or 1, kg or 1, kb or 1, 1)
            glText(string.format("%s: %d", first.killerName, total), x1+12, y, 16, "o")
            glColor(1,1,1,1)

            y = y - 30

            for _, entry in ipairs(entries) do
                local ix1 = x1 + 12
                local iy1 = y - ICON_SIZE + 4

                DrawUnitIcon(entry.attackerDefID, ix1, iy1, ICON_SIZE)

                local nameX = x1 + ICON_SIZE + 24
                local nameY = y - (ICON_SIZE * 0.5)
                local victimName = entry.victimName or "Unknown"
                local nameWidth = (glGetTextWidth(victimName) or 0) * 14

                local vr,vg,vb = spGetTeamColor(entry.victimTeamID)
                glColor(vr or 1, vg or 1, vb or 1, 1)
                glText(victimName, nameX, nameY, 14, "o")
                glColor(1,1,1,1)

                local ts = FormatTimestamp(entry.timestamp)

                glColor(0.8,0.8,0.8,1)
                glText(ts, nameX + nameWidth + 12, nameY, 12, "o")
                glColor(1,1,1,1)

                widget.iconHitboxes[#widget.iconHitboxes+1] = {
                    x1 = ix1, y1 = iy1, x2 = ix1+ICON_SIZE, y2 = iy1+ICON_SIZE,
                    unitDefID = entry.attackerDefID,
                    weaponName = entry.weaponName,
                    nameRightX = nameX + nameWidth,
                    nameMidY   = nameY,
                }

                y = y - (ICON_SIZE + 12)
            end

            y = y - 10
        end
    end

    --------------------------------------------------------
    -- END CLIPPING
    --------------------------------------------------------
    glScissor(false)

    --------------------------------------------------------
    -- UPDATE CONTENT HEIGHT + GLOBAL MAXSCROLL
    --------------------------------------------------------
    contentHeight = startY - y
    maxScroll = math.max(0, contentHeight - h)

    if maxScroll == 0 then
        scrollOffset = 0
    end

    --------------------------------------------------------
    -- SCROLLBAR
    --------------------------------------------------------
    if maxScroll > 0 then
        local scrollbarX1 = x1 + w - scrollbarWidth
        local scrollbarX2 = x1 + w

        glColor(1,1,1,0.15)
        glRect(scrollbarX1, y1, scrollbarX2, y1 + h)

        local thumbH = math.max(20, h * (h / (contentHeight + h)))
        local scrollRatio = scrollOffset / -maxScroll
        local thumbY = y1 + (h - thumbH) * scrollRatio
        thumbY = math.max(y1, math.min(thumbY, y1 + h - thumbH))

        glColor(1,1,1,0.4)
        glRect(scrollbarX1, thumbY, scrollbarX2, thumbY + thumbH)
        glColor(1,1,1,1)

        widget.scrollbar = {
            x1 = scrollbarX1,
            x2 = scrollbarX2,
            y1 = y1,
            y2 = y1 + h,
            thumbY = thumbY,
            thumbH = thumbH,
            maxScroll = maxScroll,
        }
    else
        widget.scrollbar = nil
    end

    --------------------------------------------------------
    -- RESIZE HANDLE
    --------------------------------------------------------
    local effectiveScrollbar = (maxScroll > 0) and scrollbarWidth or 0

    local rhX1 = x1 + w - RESIZE_HANDLE - effectiveScrollbar - 4
    local rhX2 = x1 + w - effectiveScrollbar - 4
    local rhY1 = y1
    local rhY2 = y1 + RESIZE_HANDLE

    glColor(1,1,1,0.7)   -- Change border color currently whitet and 0.7
    glRect(rhX1, rhY1, rhX2, rhY2)
    glColor(1,1,1,1)

    widget.resizeBox = {x1=rhX1, y1=rhY1, x2=rhX2, y2=rhY2}
end

------------------------------------------------------------
-- MOUSE WHEEL (STANDARD SCROLL)
------------------------------------------------------------

function widget:MouseWheel(up, value)
    local mx, my = spGetMouseState()
    local b = widget.box
    if not b.x1 then return false end

    if mx >= b.x1 and mx <= b.x2 and my >= b.y1 and my <= b.y2 then

        -- Slight acceleration
        local step = scrollStep + math.floor(math.abs(scrollOffset) * 0.02)

        -- Standard behavior:
        -- scroll down → list moves up → scrollOffset becomes more negative
        if up then
            scrollOffset = scrollOffset + step
        else
            scrollOffset = scrollOffset - step
        end

        -- Clamp using GLOBAL maxScroll
        scrollOffset = math.max(-maxScroll, math.min(scrollOffset, 0))
        return true
    end

    return false
end

------------------------------------------------------------
-- DRAW SCREEN (TOOLTIPS)
------------------------------------------------------------

function widget:DrawScreen()
    DrawPanel()

    tooltipText = nil
    tooltipMouseX = nil
    tooltipMouseY = nil

    local mx,my = spGetMouseState()
    if not mx then return end

    for _, box in ipairs(widget.iconHitboxes) do
        if mx>=box.x1 and mx<=box.x2 and my>=box.y1 and my<=box.y2 then
            local unitName = "Unknown Unit"
            if box.unitDefID and UnitDefs[box.unitDefID] then
                local ud = UnitDefs[box.unitDefID]
                unitName = ud.translatedHumanName or ud.humanName or ud.name or unitName
            end

            local weapon = box.weaponName or "Unknown Weapon"

            tooltipText = string.format("Unit: %s\nWeapon: %s", unitName, weapon)
            tooltipMouseX = box.nameRightX + 12
            tooltipMouseY = box.nameMidY
            break
        end
    end

    if tooltipText then
        local padding = 6
        local fontSize = 14
        local width = (glGetTextWidth(tooltipText) or 0) * fontSize
        local height = fontSize * 2

        local x1 = tooltipMouseX
        local y1 = tooltipMouseY - (height * 0.5)

        glColor(0,0,0,0.75)
        glRect(x1, y1, x1+width+padding*2, y1+height+padding*2)

        glColor(1,1,1,1)
        glText(tooltipText, x1+padding, y1+padding, fontSize, "o")
    end
end

------------------------------------------------------------
-- DRAG + RESIZE + SCROLLBAR DRAGGING
------------------------------------------------------------

local function IsInBox(mx,my)
    local b = widget.box
    return b.x1 and mx>=b.x1 and mx<=b.x2 and my>=b.y1 and my<=b.y2
end

local function IsInResize(mx,my)
    local b = widget.box
    local effectiveScrollbar = (contentHeight > (b.y2 - b.y1)) and scrollbarWidth or 0

    return b.x1
       and mx >= b.x2 - RESIZE_HANDLE - effectiveScrollbar - 4
       and mx <= b.x2 - effectiveScrollbar - 4
       and my >= b.y1
       and my <= b.y1 + RESIZE_HANDLE
end

local function IsInScrollbarThumb(mx,my)
    if not widget.scrollbar then return false end
    local sb = widget.scrollbar
    return mx >= sb.x1 and mx <= sb.x2 and my >= sb.thumbY and my <= sb.thumbY + sb.thumbH
end

local function IsInScrollbarTrack(mx,my)
    if not widget.scrollbar then return false end
    local sb = widget.scrollbar
    return mx >= sb.x1 and mx <= sb.x2 and my >= sb.y1 and my <= sb.y2
end

function widget:MousePress(mx,my,button)
    if button ~= 1 then return false end

    if IsInScrollbarThumb(mx,my) then
        draggingScrollbar = true
        scrollbarDragOffset = my - widget.scrollbar.thumbY
        return true
    end

    if IsInScrollbarTrack(mx,my) then
        local sb = widget.scrollbar
        local clickRatio = (my - sb.y1) / (sb.y2 - sb.y1)
        scrollOffset = -sb.maxScroll * clickRatio
        return true
    end

    if IsInResize(mx,my) then
        resizing = true
        return true
    end

    if IsInBox(mx,my) then
        dragging = true
        dragOffsetX = mx - widget.box.x1
        dragOffsetY = my - widget.box.y1
        return true
    end

    return false
end

function widget:MouseMove(mx,my)
    local vsx,vsy = spGetViewGeometry()

    if draggingScrollbar and widget.scrollbar then
        local sb = widget.scrollbar
        local newThumbY = my - scrollbarDragOffset

        newThumbY = math.max(sb.y1, math.min(newThumbY, sb.y2 - sb.thumbH))

        local ratio = (newThumbY - sb.y1) / (sb.y2 - sb.y1 - sb.thumbH)
        scrollOffset = -sb.maxScroll * ratio
        return
    end

    if dragging then
        cfg.x = math.max(0, math.min((mx - dragOffsetX) / vsx, 1 - cfg.w))
        cfg.y = math.max(0, math.min((my - dragOffsetY) / vsy, 1 - cfg.h))
    end

    if resizing then
        local newW = (mx - widget.box.x1) / vsx
        local topY = widget.box.y1 + (cfg.h * vsy)
        local newH = (topY - my) / vsy

        -- newH = math.max(0.10, math.min(newH, 0.80))
        -- cfg.h = newH
        -- cfg.y = (topY - (newH * vsy)) / vsy
        -- cfg.w = math.max(0.10, math.min(newW, 0.80))
		newH = math.max(0.05, math.min(newH, 0.80))
        cfg.h = newH
        cfg.y = (topY - (newH * vsy)) / vsy
        cfg.w = math.max(0.07, math.min(newW, 0.80))
    end
end

function widget:MouseRelease()
    dragging = false
    resizing = false
    draggingScrollbar = false
end

------------------------------------------------------------
-- SAVE / LOAD
------------------------------------------------------------

function widget:GetConfigData()
    return cfg
end

function widget:SetConfigData(data)
    if type(data) == "table" then
        cfg.x = data.x or cfg.x
        cfg.y = data.y or cfg.y
        cfg.w = data.w or cfg.w
        cfg.h = data.h or cfg.h
    end
end