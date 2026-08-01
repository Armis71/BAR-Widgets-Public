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

local recentCommanderSpawn = {}
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
local spGetUnitPosition    = Spring.GetUnitPosition
local spGetFeatureDefID    = Spring.GetFeatureDefID
local spGetFeaturePosition = Spring.GetFeaturePosition
local spGetCameraState     = Spring.GetCameraState
local spSetCameraState     = Spring.SetCameraState
local spGetMyAllyTeamID    = Spring.GetMyAllyTeamID
local spGetTeamAllyTeamID  = Spring.GetTeamAllyTeamID

local glColor        = gl.Color
local glText         = gl.Text
local glRect         = gl.Rect
local glTexture      = gl.Texture
local glTexRect      = gl.TexRect
local glGetTextWidth = gl.GetTextWidth
local glScissor      = gl.Scissor

local recentEffigyExplosion = {}

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

widget.box              = {}
widget.iconHitboxes     = {}
widget.tombstoneHitboxes = {}

-- Kill entries awaiting correlation with the wreck feature spawned by
-- their death, so we can later tell whether that wreck got reclaimed.
local pendingWreckEntries = {}
local WRECK_MATCH_RADIUS = 80
local WRECK_MATCH_TIMEOUT_FRAMES = 10

-- Tombstone camera jump + world-space "found it" flash (same numbers
-- as Base Unit Tracker's commander zoom/flash).
local TOMBSTONE_ZOOM_HEIGHT = 1000
local TOMBSTONE_ZOOM_TIME   = 1.2
local flashMarker        = nil
local FLASH_DURATION     = 2.0
local FLASH_RADIUS       = 90
local FLASH_SEGMENTS     = 32
local FLASH_BASE_OPACITY = 0.30

local aiTeamNameMap = {}
local widgetFlashFrame = nil

-- Scroll state
local scrollOffset = 0
local scrollStep   = 40
local contentHeight = 0
local maxScroll = 0   -- GLOBAL maxScroll (fixes early clamp)

--------------------------------------------------------------
-- To Capture Weapon Hits
--------------------------------------------------------------
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, attackerID, attackerDefID, attackerTeam)
    if not attackerID then
        return
    end

    -- Track effigy explosions for resurrection detection
    if unitDefID and UnitDefs[unitDefID] then
        local name = UnitDefs[unitDefID].name or ""
        if name:find("effigy") then
            recentEffigyExplosion[unitID] = Spring.GetGameFrame()
        end
    end


    -- BAR uses -1 for beam/continuous weapons; ignore those
    if weaponDefID and weaponDefID >= 0 then
        lastWeaponByAttacker[attackerID] = weaponDefID
    end
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

local function GetTeamUnitsKilled(teamID)
    if not teamID then return 0 end
    local historyMax = Spring.GetTeamStatsHistory(teamID)
    if not historyMax or historyMax < 1 then return 0 end
    local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
    if statsHistory and statsHistory[1] then
        return statsHistory[1].unitsKilled or 0
    end
    return 0
end

local function FormatTimestamp(frame)
    if not frame then return "" end
    local seconds = math.floor(frame / 30)
    return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
end

local function AssignCustomAINames()
    local teams = spGetTeamList()
    if not teams then return end
    for _, teamID in ipairs(teams) do
        if not aiTeamNameMap[teamID] then
            local _, _, _, isAI = spGetTeamInfo(teamID)
            if isAI then
                -- BAR stores the AI's assigned nickname (e.g. "PsychoPewPew")
                -- as a game rules param, keyed by teamID.
                local niceName = Spring.GetGameRulesParam("ainame_" .. teamID)
                if niceName and niceName ~= "" then
                    aiTeamNameMap[teamID] = niceName .. " (AI)"
                end
            end
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
    pendingWreckEntries  = {}
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

-- Procedural explosion/burst icon (no unit def available, e.g. commander
-- self-destruct or an untraceable chain-explosion kill). Drawn as a
-- spiky orange/yellow starburst so these kills aren't left blank.
local function DrawExplosionIcon(x, y, size)
    local cx = x + size * 0.5
    local cy = y + size * 0.5
    local rOuter = size * 0.5
    local rInner = size * 0.22
    local points = 16

    glTexture(false)

    glColor(1.0, 0.45, 0.05, 1)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(cx, cy)
        for i = 0, points do
            local idx = i % points
            local angle = (idx / points) * math.pi * 2
            local r = (idx % 2 == 0) and rOuter or rInner
            gl.Vertex(cx + math.cos(angle) * r, cy + math.sin(angle) * r)
        end
    end)

    local coreR = rOuter * 0.45
    glColor(1.0, 0.85, 0.35, 1)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(cx, cy)
        for i = 0, 12 do
            local angle = (i / 12) * math.pi * 2
            gl.Vertex(cx + math.cos(angle) * coreR, cy + math.sin(angle) * coreR)
        end
    end)

    glColor(1,1,1,1)
end

-- Small clickable tombstone marker shown next to the timestamp for an
-- allied commander death, while you're actively playing (not a
-- spectator/replay). Clicking it jumps the camera to the death spot.
local function DrawTombstoneIcon(x, y, size)
    -- Same headstone design as Base/Unit Tracker's drawCommanderTombstoneIcon:
    -- ground shadow, base plinth (light-left/dark-right depth edge), rounded-
    -- arch headstone slab (dark-outline-then-fill technique), "RIP" text.
    -- Centered horizontally, flush to the bottom of the slot.
    local scale = 0.92
    local dsize = size * scale
    local offX = (size - dsize) * 0.5
    x = x + offX
    size = dsize

    glTexture(false)

    local cx = x + size * 0.5

    -- Soft ground shadow (flattened ellipse under the base).
    glColor(0, 0, 0, 0.32)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        local shY  = y - size * 0.03
        local shRX = size * 0.44
        local shRY = size * 0.08
        gl.Vertex(cx, shY)
        for i = 0, 16 do
            local angle = (i / 16) * 2 * math.pi
            gl.Vertex(cx + math.cos(angle) * shRX, shY + math.sin(angle) * shRY)
        end
    end)

    -- BASE PLINTH: full width, short -- the slab the headstone stands on.
    local baseH = size * 0.16
    local depth = size * 0.06
    local bx1, by1 = x, y
    local bx2, by2 = x + size, y + baseH

    glColor(0.12, 0.11, 0.10, 1)
    glRect(bx1 - 1, by1 - 1, bx2 + 1, by2 + 1)

    glColor(0.80, 0.78, 0.72, 1)
    glRect(bx1, by1, bx2 - depth, by2)
    glColor(0.52, 0.50, 0.45, 1)
    glRect(bx2 - depth, by1, bx2, by2)

    -- HEADSTONE: narrower slab, straight sides, rounded arch top.
    local slabW = size * 0.62
    local sx1 = x + (size - slabW) * 0.5
    local sx2 = sx1 + slabW
    local sy1 = by2
    local archTopY = y + size * 0.69
    local archR = slabW * 0.5
    local archCx = (sx1 + sx2) * 0.5

    -- Dark silhouette pass for the slab + arch (outline stroke look).
    glColor(0.12, 0.11, 0.10, 1)
    glRect(sx1 - 1, sy1 - 1, sx2 + 1, archTopY)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(archCx, archTopY)
        for i = 0, 16 do
            local angle = math.pi * (i / 16)
            local r = archR + 1
            gl.Vertex(archCx + math.cos(angle) * r, archTopY + math.sin(angle) * r)
        end
    end)

    -- Front face: spans the full slab width to exactly match the outline.
    glColor(0.83, 0.81, 0.75, 1)
    glRect(sx1, sy1, sx2, archTopY)

    -- Rounded arch cap: true circle, Gouraud-shaded, same center as the
    -- outline fan so it fully covers it with a clean 1px outline ring.
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Color(0.92, 0.90, 0.85, 1)
        gl.Vertex(archCx, archTopY)
        for i = 0, 16 do
            local angle = math.pi * (i / 16)
            local t = i / 16
            gl.Color(0.87 - 0.10 * t, 0.85 - 0.10 * t, 0.79 - 0.09 * t, 1)
            gl.Vertex(archCx + math.cos(angle) * archR, archTopY + math.sin(angle) * archR)
        end
    end)

    -- "RIP" engraved on the face, centered.
    local ripFontSize = slabW * 0.34
    glColor(0.42, 0.40, 0.35, 1)
    glText("RIP", archCx, sy1 + (archTopY - sy1) * 0.82, ripFontSize, "oc")

    glColor(1, 1, 1, 1)
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

    -- Give up correlating a death with its wreck feature if it's been
    -- pending too long (e.g. the unit left no wreck at all).
    if #pendingWreckEntries > 0 then
        for i = #pendingWreckEntries, 1, -1 do
            local pending = pendingWreckEntries[i]
            if frame - pending.spawnFrame > WRECK_MATCH_TIMEOUT_FRAMES then
                table.remove(pendingWreckEntries, i)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- WRECK TRACKING (for the tombstone "reclaimed" check)
--------------------------------------------------------------------------------

function widget:FeatureCreated(featureID)
    if #pendingWreckEntries == 0 then return end

    local featureDefID = spGetFeatureDefID(featureID)
    if not featureDefID then return end
    local fdef = FeatureDefs[featureDefID]
    if not fdef then return end

    local fx, fy, fz = spGetFeaturePosition(featureID)
    if not fx then return end

    for i = #pendingWreckEntries, 1, -1 do
        local pending = pendingWreckEntries[i]
        if fdef.name == pending.expectedWreckDefName then
            local entry = pending.entry
            local dx = (entry.deathX or fx) - fx
            local dz = (entry.deathZ or fz) - fz
            if (dx*dx + dz*dz) <= (WRECK_MATCH_RADIUS * WRECK_MATCH_RADIUS) then
                entry.wreckFeatureID = featureID
                table.remove(pendingWreckEntries, i)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- CHUNK 1 — TOP BAR COMMANDER DETECTION
--------------------------------------------------------------------------------

local function IsCommanderDef(unitDefID)

    -- Spring.Echo("CHECK", unitDefID, UnitDefs[unitDefID].name, UnitDefs[unitDefID].deathExplosion)

    if not unitDefID then return false end
    local ud = UnitDefs[unitDefID]
    if not ud then return false end
    local cp = ud.customParams or {}
    local udName = ud.name or ""

    -- Hard blacklist: respawn pads and effigies
    if udName == "armrespawn" or udName == "correspawn" then
        return false
    end
    if udName:find("effigy") then
        return false
    end

    -- True commander identifiers
    if cp.iscommander then return true end
    if cp.commtype then return true end
    if cp.iscommanderunit then return true end
    if cp.iscommanderclass then return true end

    -- Explosion-based detection (real commanders only)
    if ud.deathExplosion == "commanderexplosion" then
        return true
    end

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

local function ResolveAttacker(unitID, unitTeam, attackerID_raw, attackerTeam_raw, attackerDefID_raw)
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

    -- 3. Final fallback: the raw attacker info the engine already handed
    -- us as arguments to UnitDestroyed. This matters most with 3+ teams,
    -- since kills between two other teams (not involving the local
    -- player) can have rules-param visibility restricted by LOS, causing
    -- paths 1 and 2 above to come back empty even though the engine
    -- itself already told us who did it.
    if attackerID_raw and attackerTeam_raw then
        return attackerID_raw, attackerTeam_raw, attackerDefID_raw
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


function widget:UnitCreated(unitID, unitDefID, teamID)
    if IsCommanderDef(unitDefID) then
        recentCommanderSpawn[teamID] = Spring.GetGameFrame()
    end
end

--------------------------------------------------------------------------------
-- CHUNK 5 — FINAL KILL-RECORDING INTEGRATION
--------------------------------------------------------------------------------

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID_raw, attackerDefID_raw, attackerTeam_raw, weaponDefID_raw)


    -- Ignore fake commander deaths caused by effigy explosions
    local isEffigy = UnitDefs[unitDefID] and UnitDefs[unitDefID].name:find("effigy")
    if isEffigy then
        return
    end

    -- Capture raw engine weaponDefID BEFORE Top Bar overrides it
    local rawWeaponDefID = weaponDefID_raw

    -- Commander detection (with effigy + respawn filtering)
    if not IsCommanderDef(unitDefID) then
        return
    end

    -- MORPH FILTER: ignore fake commander deaths caused by morph transitions
    local gf = Spring.GetGameFrame()
    local spawnFrame = recentCommanderSpawn[unitTeam]

    -- If a new commander spawned for this team within 3 frames of this "death",
    -- then this is a morph, not a real kill.
    if spawnFrame and (gf - spawnFrame) <= 3 then
        return
    end

    -- If the commander "dies" within 2 frames of an effigy explosion,
    -- it's a fake death (effigy resurrection)
    local frame = Spring.GetGameFrame()
    if recentEffigyExplosion[unitID] and frame - recentEffigyExplosion[unitID] <= 2 then
        return
    end

    -- Ignore fake commander deaths caused by effigy explosions
    local udName = UnitDefs[unitDefID].name or ""
    if udName:find("effigy") then
        return
    end


    -- Ignore self-destruct (Ctrl+B)
    if IsSelfDestruct(unitID, unitTeam) then
        return
    end

	------------------------------------------------------
	-- Resolve attacker using Top Bar logic
	------------------------------------------------------
	local attackerID, attackerTeam, attackerDefID = ResolveAttacker(unitID, unitTeam, attackerID_raw, attackerTeam_raw, attackerDefID_raw)
	local attackerResolved = attackerID and attackerTeam

	if attackerResolved then
		------------------------------------------------------
		-- Chain-explosion root tracing MUST happen BEFORE
		-- any team filtering, because engine often reports
		-- commander explosions as self-damage.
		------------------------------------------------------
		attackerID, attackerTeam, attackerDefID =
			ResolveChainExplosionRoot(unitID, attackerID, attackerTeam, attackerDefID)

		-- Same-team death (friendly fire / suicide) is not a kill by an
		-- opponent, so skip it entirely -- this is a deliberate
		-- exclusion, unlike the "couldn't identify the attacker" case
		-- below, which we still want to log.
		if attackerTeam == unitTeam then
			return
		end
	end

    ------------------------------------------------------
    -- Killer label + victim name
    ------------------------------------------------------
    local killerKey, killerName, killerTeamID
    if attackerResolved then
        killerKey, killerName, killerTeamID = GetKillerLabel(attackerID)
    end

    if not killerKey then
        -- We know a real commander died (all filters above already
        -- passed), but couldn't identify who did it -- most likely a
        -- vision/LOS gap for a kill that didn't involve the local
        -- player's ally-team (common in 3+ team games). Log it as
        -- Unknown instead of silently dropping a confirmed death.
        killerKey = "UNKNOWN"
        killerName = "Unknown"
        killerTeamID = nil
        attackerDefID = nil
    end

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
    if attackerID then
        lastWeaponByAttacker[attackerID] = nil
    end

    ------------------------------------------------------
    -- Record kill
    ------------------------------------------------------
    commanderKills[killerKey] = (commanderKills[killerKey] or 0) + 1

    -- Capture the death spot (for the tombstone camera jump) and the
    -- wreck feature def we'd expect it to leave, so we can later tell
    -- whether that wreck has been reclaimed.
    local deathX, deathY, deathZ = spGetUnitPosition(unitID)
    local expectedWreckDefName = nil
    local ud = UnitDefs[unitDefID]
    if ud and ud.wreckName and ud.wreckName ~= "" then
        expectedWreckDefName = ud.wreckName
    end

    commanderKillReasons[killerKey] = commanderKillReasons[killerKey] or {}
    local newEntry = {
        killerName        = killerName,
        killerTeamID      = killerTeamID,
        victimName        = victimName,
        victimTeamID      = unitTeam,
        attackerDefID     = attackerDefID,
        weaponName        = weaponName,
        timestamp         = Spring.GetGameFrame(),
        victimFlashFrame  = Spring.GetGameFrame(),
        deathX            = deathX,
        deathY            = deathY,
        deathZ            = deathZ,
        wreckFeatureID    = nil,
        wreckGone         = false,
    }
    table.insert(commanderKillReasons[killerKey], newEntry)

    if deathX and expectedWreckDefName then
        pendingWreckEntries[#pendingWreckEntries+1] = {
            entry               = newEntry,
            expectedWreckDefName = expectedWreckDefName,
            spawnFrame          = Spring.GetGameFrame(),
        }
    end

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
    widget.tombstoneHitboxes = {}

    -- Tombstones: while actively playing a live match, only show/allow
    -- jumping to an allied (teammate or your own) death -- jumping the
    -- camera to an unscouted enemy death would leak map info you
    -- shouldn't have. Spectators/replay viewers already see the whole
    -- map with no LOS restriction, so there's nothing to leak -- show
    -- tombstones for every commander death, any team, in that case.
    local spectating = spGetSpectatingState()
    local myAllyTeam = (not spectating) and spGetMyAllyTeamID() or nil

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

    --------------------------------------------------------
    -- FIXED HEADER ROW (own row: background band + divider,
    -- centered title + disclaimer). Kept visually separate from
    -- the scrollable list below so scrolling can never merge
    -- into it.
    --------------------------------------------------------
    local title = widget:GetInfo().name .. ":"
    local disclaimer = "Effigy fake deaths are not counted"

    local HEADER_ROW_HEIGHT = 72
    local headerRowTopY = y1 + h
    local headerBottomY = headerRowTopY - HEADER_ROW_HEIGHT

    -- Header row background band
    glColor(1,1,1,0.06)
    glRect(x1, headerBottomY, x1+w, headerRowTopY)
    -- Divider line separating the header row from the list
    glColor(1,1,1,0.35)
    glRect(x1, headerBottomY, x1+w, headerBottomY+1)
    glColor(1,1,1,1)

    -- Title
    local titleSize = 16
    local titleWidth = glGetTextWidth(title) * titleSize
    local titleX = x1 + (w * 0.5) - (titleWidth * 0.5)
    local titleY = headerRowTopY - 26
    glColor(1,1,1,1)
    glText(title, titleX, titleY, titleSize, "o")

    -- Disclaimer
    local discSize = 14
    local discWidth = glGetTextWidth(disclaimer) * discSize
    local discX = x1 + (w * 0.5) - (discWidth * 0.5)
    local discY = titleY - 18
    glColor(1,1,1,0.55)
    glText(disclaimer, discX, discY, discSize, "o")
    glColor(1,1,1,1)

    --------------------------------------------------------
    -- HELP ICON (top-right of header row). Hover it for an
    -- explanation of Unknown/Explosion entries, sort order,
    -- and other panel behavior.
    --------------------------------------------------------
    local HELP_SIZE = 18
    local helpX2 = x1 + w - 8
    local helpX1 = helpX2 - HELP_SIZE
    local helpY2 = headerRowTopY - 8
    local helpY1 = helpY2 - HELP_SIZE

    glColor(1,1,1,0.12)
    glRect(helpX1, helpY1, helpX2, helpY2)
    glColor(1,1,1,0.5)
    glRect(helpX1, helpY1, helpX2, helpY1+1)
    glRect(helpX1, helpY2-1, helpX2, helpY2)
    glRect(helpX1, helpY1, helpX1+1, helpY2)
    glRect(helpX2-1, helpY1, helpX2, helpY2)

    local helpMark = "?"
    local helpSize = 13
    local helpMarkWidth = glGetTextWidth(helpMark) * helpSize
    local helpMarkX = helpX1 + (HELP_SIZE * 0.5) - (helpMarkWidth * 0.5)
    local helpMarkY = helpY1 + (HELP_SIZE * 0.5) - (helpSize * 0.35)
    glColor(1,1,1,0.85)
    glText(helpMark, helpMarkX, helpMarkY, helpSize, "o")
    glColor(1,1,1,1)

    widget.helpBox = { x1=helpX1, y1=helpY1, x2=helpX2, y2=helpY2 }

    --------------------------------------------------------
    -- FIXED FOOTER ROW BOUNDS (computed now so the list
    -- viewport below can be clipped away from it too)
    --------------------------------------------------------
    local FOOTER_ROW_HEIGHT = 26
    local footerRowBottomY = y1
    local footerRowTopY    = footerRowBottomY + FOOTER_ROW_HEIGHT

    --------------------------------------------------------
    -- APPLY SCROLL OFFSET (TOP-ALIGNED)
    --------------------------------------------------------
    -- Small top padding so the first row's text doesn't render
    -- flush against the header divider (was getting clipped/
    -- hidden right at the boundary line).
    local LIST_TOP_PADDING = 22
    local y = headerBottomY - LIST_TOP_PADDING - scrollOffset
    local startY = y

    --------------------------------------------------------
    -- CLIPPING -- restricted to the viewport strictly between
    -- the header row and footer row, so scrolled content is cut
    -- off instead of drawing over either fixed row.
    --------------------------------------------------------
    local viewportHeight = math.max(0, headerBottomY - footerRowTopY)
    glScissor(x1, footerRowTopY, w, viewportHeight)

    --------------------------------------------------------
    -- SORT KILLERS
    --------------------------------------------------------
    local sortedKillers = {}
    for killerKey, total in pairs(commanderKills) do
        local entries = commanderKillReasons[killerKey]
        local killerTeamID = entries and entries[1] and entries[1].killerTeamID
        local unitsKilled = GetTeamUnitsKilled(killerTeamID)
        sortedKillers[#sortedKillers+1] = { key=killerKey, total=total, unitsKilled=unitsKilled }
    end
    table.sort(sortedKillers, function(a,b)
        -- A commander death still happened (and got voice-announced) even
        -- when we can't resolve a killer, so keep "Unknown" in the list
        -- rather than dropping it silently -- just sink it to the bottom.
        local aUnknown = a.key == "UNKNOWN"
        local bUnknown = b.key == "UNKNOWN"
        if aUnknown ~= bUnknown then
            return not aUnknown
        end
        if a.total ~= b.total then
            return a.total > b.total
        end
        return a.unitsKilled > b.unitsKilled
    end)

    --------------------------------------------------------
    -- DRAW LIST
    --------------------------------------------------------
    for _, data in ipairs(sortedKillers) do
        local killerKey = data.key
        local total     = data.total
        local entries   = commanderKillReasons[killerKey]

        if entries and #entries > 0 then
            local first = entries[1]
            local kr,kg,kb
            if first.killerTeamID then
                kr,kg,kb = spGetTeamColor(first.killerTeamID)
            else
                kr,kg,kb = 0.7,0.7,0.7
            end
            glColor(kr or 1, kg or 1, kb or 1, 1)
            glText(string.format("%s: %d", first.killerName, total), x1+12, y, 16, "o")
            glColor(1,1,1,1)

            y = y - 30

            for _, entry in ipairs(entries) do
                local ix1 = x1 + 12
                local iy1 = y - ICON_SIZE + 4

                if entry.attackerDefID and UnitDefs[entry.attackerDefID] then
                    DrawUnitIcon(entry.attackerDefID, ix1, iy1, ICON_SIZE)
                else
                    DrawExplosionIcon(ix1, iy1, ICON_SIZE)
                end

                local nameX = x1 + ICON_SIZE + 24
                local nameY = y - (ICON_SIZE * 0.5)
                local victimName = entry.victimName or "Unknown"
                local nameWidth = (glGetTextWidth(victimName) or 0) * 14

                local vr,vg,vb = spGetTeamColor(entry.victimTeamID)
                glColor(vr or 1, vg or 1, vb or 1, 1)
                glText(victimName, nameX, nameY, 14, "o")
                glColor(1,1,1,1)

                local ts = FormatTimestamp(entry.timestamp)
                local tsWidth = (glGetTextWidth(ts) or 0) * 12

                glColor(0.8,0.8,0.8,1)
                glText(ts, nameX + nameWidth + 12, nameY, 12, "o")
                glColor(1,1,1,1)

                -- Re-check wreck validity every draw -- cheap, and picks
                -- up a reclaim as soon as it happens.
                if entry.wreckFeatureID and not entry.wreckGone then
                    if not spGetFeatureDefID(entry.wreckFeatureID) then
                        entry.wreckGone = true
                    end
                end

                local tombstoneAllowed = entry.deathX and not entry.wreckGone and (
                    spectating
                    or (myAllyTeam and spGetTeamAllyTeamID(entry.victimTeamID) == myAllyTeam)
                )

                if tombstoneAllowed then
                    local tombX1 = nameX + nameWidth + 12 + tsWidth + 10
                    local tombY1 = nameY - 7
                    local tombSize = 36
                    DrawTombstoneIcon(tombX1, tombY1, tombSize)

                    widget.tombstoneHitboxes[#widget.tombstoneHitboxes+1] = {
                        x1 = tombX1, y1 = tombY1, x2 = tombX1+tombSize, y2 = tombY1+tombSize,
                        deathX = entry.deathX, deathY = entry.deathY, deathZ = entry.deathZ,
                    }
                end

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
    -- FIXED FOOTER ROW (own row: background band + divider,
    -- tie-breaker remark). Drawn after the clipped list so it
    -- always sits on top of anything scrolled underneath.
    --------------------------------------------------------
    glColor(1,1,1,0.06)
    glRect(x1, footerRowBottomY, x1+w, footerRowTopY)
    glColor(1,1,1,0.35)
    glRect(x1, footerRowTopY-1, x1+w, footerRowTopY)
    glColor(1,1,1,1)

    local footerText = "Tie-breaker is total units killed"
    local footerSize = 12
    local footerWidth = glGetTextWidth(footerText) * footerSize
    local footerX = x1 + (w * 0.5) - (footerWidth * 0.5)
    local footerY = footerRowBottomY + 8
    glColor(1,1,1,0.5)
    glText(footerText, footerX, footerY, footerSize, "o")
    glColor(1,1,1,1)

    --------------------------------------------------------
    -- UPDATE CONTENT HEIGHT + GLOBAL MAXSCROLL (matches the
    -- actual clipped viewport, not the whole panel)
    --------------------------------------------------------
    contentHeight = startY - y
    maxScroll = math.max(0, contentHeight - viewportHeight)

    if maxScroll == 0 then
        scrollOffset = 0
    end

    --------------------------------------------------------
    -- RESIZE HANDLE
    --------------------------------------------------------
    local rhX1 = x1 + w - RESIZE_HANDLE
    local rhX2 = x1 + w
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

        -- Standard/browser behavior:
        -- scroll wheel toward you (down) → list moves up → scrollOffset becomes more negative
        -- scroll wheel away from you (up) → list moves down → scrollOffset moves back toward 0
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

-- Rows for the help tooltip: "kv" rows render as an aligned two-column
-- key/value table (like the built-in Eco Graph tooltip), "divider" rows
-- draw a thin separator line, "text" rows span the full width.
local HELP_TOOLTIP_ROWS = {
    { type="kv", key="Unknown:",       value="No resolvable killer" },
    { type="kv", key="Explosion:",     value="No unit could be identified" },
    { type="kv", key="Sort order:",    value="Most kills, ties by units killed" },
    { type="kv", key="Effigy deaths:", value="Never counted" },
    { type="kv", key="Tombstone:",     value="Click to jump there; gone once reclaimed" },
    { type="divider" },
    { type="text", text="Drag to move, corner to resize, wheel to scroll." },
}

-- Same look as the built-in Eco Graph tooltip: cream/off-white panel,
-- warm tan border, near-black text.
local TOOLTIP_BG     = {0.96, 0.94, 0.85, 0.97}
local TOOLTIP_BORDER = {0.55, 0.50, 0.35, 0.9}
local TOOLTIP_TEXT   = {0.05, 0.05, 0.05, 1}

------------------------------------------------------------
-- WORLD-SPACE "FOUND IT" FLASH (green pulsing circle at a
-- tombstone jump target, same as Base Unit Tracker)
------------------------------------------------------------

function widget:DrawWorld()
    if not flashMarker then return end

    local elapsed = os.clock() - flashMarker.startTime
    if elapsed > FLASH_DURATION then
        flashMarker = nil
        return
    end

    local fx, fy, fz = flashMarker.x, flashMarker.y, flashMarker.z

    -- 7 pulses spread evenly across the flash duration
    local alpha = FLASH_BASE_OPACITY * math.abs(math.sin((7 * math.pi / FLASH_DURATION) * elapsed))
    if alpha < 0.01 then return end

    gl.DepthTest(true)
    gl.DepthMask(false)
    gl.Culling(false)
    gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

    gl.Color(0, 1, 0, alpha)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(fx, fy + 20, fz)
        for i = 0, FLASH_SEGMENTS do
            local theta = (i / FLASH_SEGMENTS) * 2 * math.pi
            gl.Vertex(fx + FLASH_RADIUS * math.cos(theta), fy + 20, fz + FLASH_RADIUS * math.sin(theta))
        end
    end)

    gl.Color(1,1,1,1)
    gl.DepthMask(true)
end

function widget:DrawScreen()
    DrawPanel()

    local tooltipRows = nil

    local mx,my = spGetMouseState()
    if not mx then return end

    local hb = widget.helpBox
    local tomb = nil
    for _, box in ipairs(widget.tombstoneHitboxes) do
        if mx>=box.x1 and mx<=box.x2 and my>=box.y1 and my<=box.y2 then
            tomb = box
            break
        end
    end

    if hb and hb.x1 and mx>=hb.x1 and mx<=hb.x2 and my>=hb.y1 and my<=hb.y2 then
        tooltipRows = HELP_TOOLTIP_ROWS
    elseif tomb then
        tooltipRows = {
            { type="text", text="Click to jump the camera to the death spot" },
        }
    else
        for _, box in ipairs(widget.iconHitboxes) do
            if mx>=box.x1 and mx<=box.x2 and my>=box.y1 and my<=box.y2 then
                local unitName = "Explosion"
                if box.unitDefID and UnitDefs[box.unitDefID] then
                    local ud = UnitDefs[box.unitDefID]
                    unitName = ud.translatedHumanName or ud.humanName or ud.name or unitName
                end

                local weapon = box.weaponName or "Unknown Weapon"

                tooltipRows = {
                    { type="kv", key="Unit:",   value=unitName },
                    { type="kv", key="Weapon:", value=weapon },
                }
                break
            end
        end
    end

    if tooltipRows then
        local padding      = 8
        local fontSize      = 14
        local colGap         = 14
        local normalRowH    = fontSize + 6
        local dividerRowH   = 9

        local keyColW, valColW, textW = 0, 0, 0
        for _, row in ipairs(tooltipRows) do
            if row.type == "kv" then
                local kw = (glGetTextWidth(row.key) or 0) * fontSize
                local vw = (glGetTextWidth(row.value) or 0) * fontSize
                if kw > keyColW then keyColW = kw end
                if vw > valColW then valColW = vw end
            elseif row.type == "text" then
                local tw = (glGetTextWidth(row.text) or 0) * fontSize
                if tw > textW then textW = tw end
            end
        end

        local kvWidth = (keyColW > 0 and valColW > 0) and (keyColW + colGap + valColW) or 0
        local contentW = math.max(kvWidth, textW)

        local contentH = 0
        for _, row in ipairs(tooltipRows) do
            contentH = contentH + ((row.type == "divider") and dividerRowH or normalRowH)
        end

        local boxW = contentW + padding*2
        local boxH = contentH + padding*2

        local vsx, vsy = spGetViewGeometry()

        -- Default: 20px right of the cursor, top edge level with it
        local boxX1 = mx + 20
        local boxY1 = my - boxH

        -- Flip to the left of the cursor if it would run off the right edge
        if boxX1 + boxW > vsx then
            boxX1 = mx - 20 - boxW
        end
        -- Flip above the cursor if it would run off the bottom edge
        if boxY1 < 0 then
            boxY1 = my
        end
        -- Final clamps so it never runs off-screen on tiny/odd viewports
        if boxY1 + boxH > vsy then boxY1 = vsy - boxH end
        if boxX1 < 0 then boxX1 = 0 end
        if boxY1 < 0 then boxY1 = 0 end

        glColor(TOOLTIP_BG[1], TOOLTIP_BG[2], TOOLTIP_BG[3], TOOLTIP_BG[4])
        glRect(boxX1, boxY1, boxX1+boxW, boxY1+boxH)

        glColor(TOOLTIP_BORDER[1], TOOLTIP_BORDER[2], TOOLTIP_BORDER[3], TOOLTIP_BORDER[4])
        glRect(boxX1, boxY1, boxX1+boxW, boxY1+1)
        glRect(boxX1, boxY1+boxH-1, boxX1+boxW, boxY1+boxH)
        glRect(boxX1, boxY1, boxX1+1, boxY1+boxH)
        glRect(boxX1+boxW-1, boxY1, boxX1+boxW, boxY1+boxH)

        local valueColX = boxX1 + padding + keyColW + colGap
        local cursorY = boxY1 + boxH - padding

        for _, row in ipairs(tooltipRows) do
            if row.type == "divider" then
                local ly = cursorY - (dividerRowH * 0.5)
                glColor(TOOLTIP_BORDER[1], TOOLTIP_BORDER[2], TOOLTIP_BORDER[3], 0.6)
                glRect(boxX1+padding, ly, boxX1+boxW-padding, ly+1)
                cursorY = cursorY - dividerRowH
            elseif row.type == "kv" then
                local ly = cursorY - normalRowH
                glColor(TOOLTIP_TEXT[1], TOOLTIP_TEXT[2], TOOLTIP_TEXT[3], TOOLTIP_TEXT[4])
                glText(row.key, boxX1+padding, ly, fontSize, "o")
                glText(row.value, valueColX, ly, fontSize, "o")
                cursorY = cursorY - normalRowH
            else
                local ly = cursorY - normalRowH
                glColor(TOOLTIP_TEXT[1], TOOLTIP_TEXT[2], TOOLTIP_TEXT[3], TOOLTIP_TEXT[4])
                glText(row.text, boxX1+padding, ly, fontSize, "o")
                cursorY = cursorY - normalRowH
            end
        end

        glColor(1,1,1,1)
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
    return b.x1
       and mx >= b.x2 - RESIZE_HANDLE
       and mx <= b.x2
       and my >= b.y1
       and my <= b.y1 + RESIZE_HANDLE
end

-- Gradual camera zoom to a world position at a given height, same
-- approach Base Unit Tracker uses for its commander zoom (2000 height).
local function JumpCameraTo(x, y, z, height, transitionTime)
    local camState = spGetCameraState()
    camState.px = x
    camState.py = y
    camState.pz = z
    if camState.height ~= nil then
        camState.height = height
    end
    if camState.dist ~= nil then
        camState.dist = height
    end
    spSetCameraState(camState, transitionTime or TOMBSTONE_ZOOM_TIME)
end

function widget:MousePress(mx,my,button)
    if button ~= 1 then return false end

    for _, box in ipairs(widget.tombstoneHitboxes) do
        if mx>=box.x1 and mx<=box.x2 and my>=box.y1 and my<=box.y2 then
            JumpCameraTo(box.deathX, box.deathY, box.deathZ, TOMBSTONE_ZOOM_HEIGHT)
            flashMarker = { x = box.deathX, y = box.deathY, z = box.deathZ, startTime = os.clock() }
            return true
        end
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

    if dragging then
        cfg.x = math.max(0, math.min((mx - dragOffsetX) / vsx, 1 - cfg.w))
        cfg.y = math.max(0, math.min((my - dragOffsetY) / vsy, 1 - cfg.h))
    end

if resizing then
    local vsx, vsy = spGetViewGeometry()

    -- Fixed top edge
    local topY = widget.box.y2

    -- Height grows when mouse moves DOWN (my decreases)
    local newH = (topY - my) / vsy

    -- Clamp
    newH = math.max(0.05, math.min(newH, 0.80))

    -- Apply new height
    cfg.h = newH

    -- Recompute cfg.y so TOP stays locked
    cfg.y = (topY - newH * vsy) / vsy

    -- Width (unchanged logic)
    local newW = (mx - widget.box.x1) / vsx
    cfg.w = math.max(0.07, math.min(newW, 0.80))
end


end

function widget:MouseRelease()
    dragging = false
    resizing = false
end

------------------------------------------------------------
-- SAVE / LOAD
------------------------------------------------------------

-- Same fallback BAR's own widgets (e.g. gui_chat.lua) use: Game.gameID is
-- frequently nil client-side, so fall back to the GameID rules param.
local function CurrentGameID()
    return (Game and Game.gameID) or Spring.GetGameRulesParam("GameID")
end

function widget:GetConfigData()
    return {
        x = cfg.x,
        y = cfg.y,
        w = cfg.w,
        h = cfg.h,
        -- Tag the saved kill data with the current match's gameID so it
        -- only gets restored on a same-game /luaui reload, never carried
        -- over into a different game/spectate session.
        gameID                = CurrentGameID(),
        commanderKills        = commanderKills,
        commanderKillReasons  = commanderKillReasons,
    }
end

function widget:SetConfigData(data)
    if type(data) == "table" then
        cfg.x = data.x or cfg.x
        cfg.y = data.y or cfg.y
        cfg.w = data.w or cfg.w
        cfg.h = data.h or cfg.h

        -- If the game frame is already ticking, this is unambiguously a
        -- reload of the same running match. Otherwise fall back to
        -- comparing gameIDs (covers the reload-at-frame-0 edge case).
        local sameGame = spGetGameFrame() > 0
            or (data.gameID and data.gameID == CurrentGameID())

        if sameGame then
            if type(data.commanderKills) == "table" then
                commanderKills = data.commanderKills
            end
            if type(data.commanderKillReasons) == "table" then
                commanderKillReasons = data.commanderKillReasons
            end
        else
            -- Different match (or gameID unavailable) -- start fresh
            -- instead of showing another game's kills.
            commanderKills = {}
            commanderKillReasons = {}
        end
    end
end