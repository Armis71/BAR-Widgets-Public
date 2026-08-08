function widget:GetInfo()
    return {
        name      = "Clone Builder (Drag‑Copy)",
        desc      = "Shift‑drag to copy selected units with ghost preview + terrain collision con units everywhere",
        author    = "Armis71 + Copilot",
        version   = "0.9",
        date      = "2026",
        license   = "GPLv2",
        layer     = 0,
        enabled   = true
    }
end

local swapped = false

--------------------------------------------------------------------------------
-- NEW SECTION: Widget options (3 patterns)
--------------------------------------------------------------------------------
options = {
    patternMode = {
        name  = "Build Order Pattern",
        type  = "list",
        value = "rowmajor",
        items = {
            {key="rowmajor", name="Row‑major"},
            {key="colmajor", name="Column‑major"},
        },
        desc = "Controls the order builders follow when placing copied buildings."
    },
}


--------------------------------------------------------------------------------
-- NEW SECTION: Sorting helpers
--------------------------------------------------------------------------------
-- Correct Row-major: left/right first
local function SortRowMajor(list)
    table.sort(list, function(a, b)
        if math.abs(a.gx - b.gx) < 1e-3 then
            return a.gz < b.gz
        else
            return a.gx < b.gx
        end
    end)
end

-- Correct Column-major: up/down first
local function SortColumnMajor(list)
    table.sort(list, function(a, b)
        if math.abs(a.gz - b.gz) < 1e-3 then
            return a.gx < b.gx
        else
            return a.gz < b.gz
        end
    end)
end


--------------------------------------------------------------------------------
-- NEW SECTION: Apply selected pattern
--------------------------------------------------------------------------------
local function ApplyPattern(list)
    -- Detect layout orientation
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge

    for _, g in ipairs(list) do
        if g.gx < minX then minX = g.gx end
        if g.gx > maxX then maxX = g.gx end
        if g.gz < minZ then minZ = g.gz end
        if g.gz > maxZ then maxZ = g.gz end
    end

    local width  = maxX - minX
    local height = maxZ - minZ

    local isHorizontal = width > height

    ------------------------------------------------------------------------
    -- FINAL LOGIC:
    -- Default: horizontal=row, vertical=column
    -- Swapped: horizontal=column, vertical=row
    ------------------------------------------------------------------------

    if not swapped then
        -- normal behavior
        if isHorizontal then
            SortRowMajor(list)
        else
            SortColumnMajor(list)
        end
    else
        -- swapped behavior
        if isHorizontal then
            SortColumnMajor(list)
        else
            SortRowMajor(list)
        end
    end
end


--------------------------------------------------------------------------------
-- Original code continues unchanged below
--------------------------------------------------------------------------------

local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitDefID     = Spring.GetUnitDefID
local spGetUnitPosition  = Spring.GetUnitPosition
local spTestBuildOrder   = Spring.TestBuildOrder
local spGetMouseState    = Spring.GetMouseState
local spTraceScreenRay   = Spring.TraceScreenRay
local spGiveOrderToUnit  = Spring.GiveOrderToUnit
local spPlaySoundFile    = Spring.PlaySoundFile
local spGetTimer         = Spring.GetTimer
local spDiffTimers       = Spring.DiffTimers

local ghostData   = {}
local dragging    = false
local rotation    = 0
local dragBuilders = {}

-- A unit is only eligible for shift-drag-clone if IT ITSELF was added to
-- the selection while shift was held (click or box-select). This has to be
-- tracked per-unit, not as one flag for "the selection" - otherwise a
-- single shift-drag that legitimately adds one new unit would flip the
-- WHOLE current selection clonable, dragging along whatever was plain-
-- selected earlier too. A unit stays non-clonable until it's deselected
-- and shift-selected fresh, no matter what other shift actions touch the
-- selection around it. Tracked via widget:SelectionChanged below, the one
-- reliable place that sees every kind of selection change.
local clonableUnits = {}

-- Destination centroid of the current ghost formation, kept up to date every
-- frame during a drag so we can draw the helper-recruit radius ring around it.
local ghostCenterX, ghostCenterZ = nil, nil

local lastSoundTime = nil
local soundInterval = 0.30

-- On-screen warning banner (e.g. "no idle con unit within the radius").
-- Spring.Echo alone goes to a chat log players can easily miss - a plop can
-- start well after the drag has ended (once an earlier queued plop
-- finishes), so this needs to render independent of the dragging state and
-- stick around long enough to actually be seen.
local screenWarningText  = nil
local screenWarningTimer = nil
local SCREEN_WARNING_DURATION = 4.5 -- seconds

--------------------------------------------------------------------------------
-- Convert our 0/90/180/270 degree rotation into Spring's 0-3 build facing
--------------------------------------------------------------------------------
local function ToBuildFacing(deg)
    return math.floor((deg / 90) + 0.5) % 4
end

--------------------------------------------------------------------------------
-- Plop queue + cross-tier assist
--
-- Each shift-drag release is a "plop". Only one plop is ever actively being
-- built at a time - if the player releases another drag while the previous
-- one is still going, it's queued up and doesn't start (doesn't even
-- recruit helpers yet) until the current plop is fully finished. This is
-- what makes "drag 3 clones in a row" behave like a normal build queue
-- instead of everyone getting yanked onto whatever was dropped last.
--
-- Within a single active plop: a builder that finishes its own share (e.g.
-- the single T1 con with only one T1 structure to place) should pitch in on
-- whatever's left in THIS plop instead of going idle - even if it can't
-- build that type itself. Guarding another builder makes a con assist its
-- construction regardless of buildOptions, so this is periodically
-- re-checked (not just once at release) so it reacts as builders finish at
-- different times. Once the whole plop is done, the next queued plop (if
-- any) starts - recruiting helpers fresh, based on who's idle *then*.
--------------------------------------------------------------------------------
local activeBuild = nil
local helperAssistTimer = nil
local HELPER_ASSIST_INTERVAL = 1.0 -- seconds between idle-helper reassignment checks
local CMD_GUARD = CMD and CMD.GUARD or 25
local CMD_STOP  = CMD and CMD.STOP or 0

local plopQueue = {}
local MaybeStartNextPlop -- forward-declared; assigned further down once
                          -- RecruitHelpers/BuilderCanBuildType etc. exist

local function TickHelperAssist()
    if not activeBuild then return end

    local builders = activeBuild.builders
    local busy, idle = {}, {}

    for _, b in ipairs(builders) do
        local queue = Spring.GetCommandQueue(b, 1)
        local cmdID = queue and queue[1] and queue[1].id
        if cmdID and cmdID < 0 then
            -- Actively has a BUILD command queued/in progress.
            table.insert(busy, b)
        elseif not cmdID then
            -- Truly empty queue - finished its own share, or never had any.
            table.insert(idle, b)
        end
        -- Anything else (e.g. already CMD_GUARD) is left alone.
    end

    if #busy == 0 then
        -- Nothing left that needs help - release anyone still guarding.
        for _, b in ipairs(builders) do
            local queue = Spring.GetCommandQueue(b, 1)
            if queue and queue[1] and queue[1].id == CMD_GUARD then
                spGiveOrderToUnit(b, CMD_STOP, {}, {})
            end
        end
        activeBuild = nil
        if MaybeStartNextPlop then MaybeStartNextPlop() end
        return
    end

    if #idle > 0 then
        local helper = busy[1]
        for _, b in ipairs(idle) do
            spGiveOrderToUnit(b, CMD_GUARD, { helper }, {})
        end
        Spring.Echo("DCB: assist - " .. #idle .. " finished helper(s) now guarding #" .. helper)
    end
end

local spGetMyTeamID = Spring.GetMyTeamID

--------------------------------------------------------------------------------
-- Box-select footprint fix
--
-- The engine's own box-select only grabs a unit if its CENTER point falls
-- inside the drag box, which makes small buildings (like Dragon's Teeth)
-- much harder to box-select than bigger ones (like turbines/turrets), since
-- you have to land the box exactly on their tiny center point.
--
-- We never intercept the drag itself, so the engine's default box-select
-- still runs exactly as before. After it's done, we add any of our own
-- units whose footprint overlaps the box on top of whatever the engine
-- already picked.
--------------------------------------------------------------------------------
local spGetTeamUnits    = Spring.GetTeamUnits
local spSelectUnitArray = Spring.SelectUnitArray

local BOX_DRAG_THRESHOLD = 6 -- pixels; below this it's a click, not a box-drag

-- Widgets only get MouseMove/MouseRelease callins for a drag if their
-- MousePress returned true (i.e. "claimed" the click). We deliberately
-- don't claim plain drags (so the engine's own box-select still runs),
-- which means we never get a MouseRelease for them either. So instead we
-- just poll the left mouse button state every frame to detect the drag
-- start/end ourselves.
local pollDragStartX, pollDragStartY = nil, nil
local pollDragTracking = false
local wasLmbDown = false

local function GetUnitScreenBounds(unitID)
    local udid = spGetUnitDefID(unitID)
    local ud = UnitDefs[udid]
    if not ud then return nil end

    local x, y, z = spGetUnitPosition(unitID)
    if not x then return nil end

    -- xsize/zsize are footprint squares (8 elmos each); use half-extents
    local hx = (ud.xsize or 2) * 4
    local hz = (ud.zsize or 2) * 4

    local corners = {
        { x - hx, y, z - hz },
        { x + hx, y, z - hz },
        { x - hx, y, z + hz },
        { x + hx, y, z + hz },
    }

    local minSx, maxSx = math.huge, -math.huge
    local minSy, maxSy = math.huge, -math.huge

    for _, c in ipairs(corners) do
        local sx, sy = Spring.WorldToScreenCoords(c[1], c[2], c[3])
        if sx and sy then
            if sx < minSx then minSx = sx end
            if sx > maxSx then maxSx = sx end
            if sy < minSy then minSy = sy end
            if sy > maxSy then maxSy = sy end
        end
    end

    if minSx == math.huge then return nil end
    return minSx, maxSx, minSy, maxSy
end

local function TryFootprintBoxSelect(x0, y0, x1, y1)
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)

    -- Too small to be a box-drag; it was a click, leave the engine's pick alone.
    if dx < BOX_DRAG_THRESHOLD and dy < BOX_DRAG_THRESHOLD then return end

    local ctrl = Spring.GetModKeyState()
    -- Ctrl-drag removes units from selection; don't fight that by re-adding them.
    if ctrl then return end

    local rectMinX, rectMaxX = math.min(x0, x1), math.max(x0, x1)
    local rectMinY, rectMaxY = math.min(y0, y1), math.max(y0, y1)

    local teamUnits = spGetTeamUnits(spGetMyTeamID())
    if not teamUnits then return end

    local alreadySelected = {}
    for _, id in ipairs(spGetSelectedUnits()) do
        alreadySelected[id] = true
    end

    local toAdd = {}
    for _, unitID in ipairs(teamUnits) do
        if not alreadySelected[unitID] then
            local minSx, maxSx, minSy, maxSy = GetUnitScreenBounds(unitID)
            if minSx then
                local overlaps = not (maxSx < rectMinX or minSx > rectMaxX or maxSy < rectMinY or minSy > rectMaxY)
                if overlaps then
                    table.insert(toAdd, unitID)
                end
            end
        end
    end

    if #toAdd > 0 then
        -- Build the union explicitly and do a plain (non-append) select,
        -- rather than relying on SelectUnitArray's append flag.
        local combined = {}
        for _, id in ipairs(spGetSelectedUnits()) do
            table.insert(combined, id)
        end
        for _, id in ipairs(toAdd) do
            table.insert(combined, id)
        end
        spSelectUnitArray(combined)
    end
end

--------------------------------------------------------------------------------
-- Split selection into builders and buildings
-- Some unitDefs have an empty-string humanName ("") rather than nil, which
-- is truthy in Lua - `ud.humanName or ud.name` would silently pick the
-- empty string and produce a blank name in messages. This checks for a
-- genuinely non-empty string at each fallback step.
local function GetUnitDefDisplayName(udid)
    local ud = UnitDefs[udid]
    if ud then
        if ud.humanName and ud.humanName ~= "" then
            return ud.humanName
        elseif ud.name and ud.name ~= "" then
            return ud.name
        end
    end
    return "unknown structure"
end

-- BAR unitDefs carry their tech tier in customParams.techlevel ("1", "2",
-- "3", ...). Used to tell the player which specific tier con they're
-- missing (e.g. "You also need a T1 con unit.") instead of a vague
-- "something's missing".
local function GetUnitTechLevel(udid)
    local ud = UnitDefs[udid]
    local level = ud and ud.customParams and ud.customParams.techlevel
    return level and tonumber(level) or nil
end

--------------------------------------------------------------------------------
local function SplitSelection()
    local builders = {}
    local buildings = {}

    local selected = spGetSelectedUnits()
    for _, id in ipairs(selected) do
        local udid = spGetUnitDefID(id)
        local ud = UnitDefs[udid]

        -- TRUE builders have buildOptions
        if ud and ud.buildOptions and #ud.buildOptions > 0 then
            table.insert(builders, id)
        else
            -- Everything else (including Dragon's Teeth) is a building
            table.insert(buildings, id)
        end
    end

    return builders, buildings
end


--------------------------------------------------------------------------------
-- Auto-pick constructors when none (or not enough) are selected
--
-- A mixed selection (e.g. T1 Dragon's Teeth + a T2 structure) can need more
-- than one constructor tier, since a T1 con can't build T2 buildings. For
-- each distinct structure type being copied, if none of the currently
-- selected builders can actually build it, find the closest capable
-- constructor (preferring idle, falling back to busy) and add it. If no
-- constructor anywhere on the team can build a given type, that type is
-- reported back as unavailable instead of silently vanishing.
--------------------------------------------------------------------------------
local function BuilderCanBuildType(builderUnitID, targetUnitDefID)
    local budid = spGetUnitDefID(builderUnitID)
    local bud = UnitDefs[budid]
    if not bud or not bud.buildOptions then return false end
    for _, optID in ipairs(bud.buildOptions) do
        if optID == targetUnitDefID then
            return true
        end
    end
    return false
end

local function FindBuilderForType(cx, cz, targetUnitDefID, requireIdle)
    local teamUnits = spGetTeamUnits(spGetMyTeamID())
    if not teamUnits then return nil end

    local best, bestDistSq = nil, math.huge
    for _, unitID in ipairs(teamUnits) do
        if BuilderCanBuildType(unitID, targetUnitDefID) then
            local idle = (Spring.GetUnitCommandCount(unitID) or 0) == 0
            if (not requireIdle) or idle then
                local x, y, z = spGetUnitPosition(unitID)
                if x then
                    local dx, dz = x - cx, z - cz
                    local distSq = dx * dx + dz * dz
                    if distSq < bestDistSq then
                        bestDistSq = distSq
                        best = unitID
                    end
                end
            end
        end
    end
    return best
end

local HELPER_RECRUIT_RADIUS = 1125 -- elmos; how far to look for idle helpers to rope in

-- Recruits every nearby idle constructor into `builders` (modified in
-- place) - ANY constructor, not just ones that can directly build one of
-- `neededTypes`. A unit that can't build any of this plop's specific
-- types (e.g. a T1-only commander when the plop is all T2) can still
-- Guard-assist a busy builder once recruited - Guard doesn't care about
-- buildOptions at all. Gating recruitment on direct-build capability was
-- excluding exactly the units the cross-tier assist system exists for,
-- so being a construction-capable unit at all is enough to get swept in.
-- Searches near (cx, cz), which the caller passes in as the DROP
-- location, not the source, so helpers come from wherever the clone is
-- actually landing.
--
-- Returns a set of unitDefIDs (keyed by udid, value = human-readable name)
-- for any type nobody on the team can build at all, even ignoring idleness.
local function RecruitHelpers(builders, neededTypes, cx, cz)
    local startCount = #builders

    local alreadyIn = {}
    for _, b in ipairs(builders) do
        alreadyIn[b] = true
    end

    local teamUnits = spGetTeamUnits(spGetMyTeamID())
    if teamUnits then
        for _, unitID in ipairs(teamUnits) do
            if not alreadyIn[unitID] and (Spring.GetUnitCommandCount(unitID) or 0) == 0 then
                local budid = spGetUnitDefID(unitID)
                local bud = UnitDefs[budid]
                local isConstructor = bud and bud.buildOptions and #bud.buildOptions > 0

                if isConstructor then
                    local x, y, z = spGetUnitPosition(unitID)
                    if x then
                        local dx, dz = x - cx, z - cz
                        if math.sqrt(dx * dx + dz * dz) <= HELPER_RECRUIT_RADIUS then
                            table.insert(builders, unitID)
                            alreadyIn[unitID] = true
                        end
                    end
                end
            end
        end
    end

    if #builders > startCount then
        local names = {}
        for i = startCount + 1, #builders do
            table.insert(names, GetUnitDefDisplayName(spGetUnitDefID(builders[i])) .. "#" .. builders[i])
        end
        Spring.Echo("DCB: recruited " .. #names .. " helper(s) near drop site: " .. table.concat(names, ", "))
    end

    -- No automatic fallback to a busy/far-away builder anymore - if
    -- nothing idle is inside the recruit radius for a given type, that's
    -- reported back instead of silently pulling someone off another job
    -- or grabbing a distant unit the player didn't intend to use. Two
    -- different messages depending on WHY: "nobody idle nearby" (player
    -- should wait or select a builder themselves) vs. "nobody on the team
    -- can build this at all" (a tech/tier problem, not a location one).
    local unavailable = {}
    for udid in pairs(neededTypes) do
        local covered = false
        for _, b in ipairs(builders) do
            if BuilderCanBuildType(b, udid) then
                covered = true
                break
            end
        end
        if not covered then
            local name = GetUnitDefDisplayName(udid)
            local existsAnywhere = FindBuilderForType(cx, cz, udid, false) ~= nil
            unavailable[udid] = {
                name = name,
                noIdleInRadius = existsAnywhere,
                techLevel = GetUnitTechLevel(udid),
            }
        end
    end

    return unavailable
end


--------------------------------------------------------------------------------
-- Create ghost objects (each building keeps its own unit type)
--------------------------------------------------------------------------------
local function CreateGhosts(buildings)
    ghostData = {}

    for _, unitID in ipairs(buildings) do
        local udid = spGetUnitDefID(unitID)
        local x, y, z = spGetUnitPosition(unitID)

        table.insert(ghostData, {
            udid = udid,           -- KEEP ORIGINAL UNIT TYPE
            ox = x, oy = y, oz = z,
            gx = x, gy = y, gz = z,
            valid = true,
        })
    end
end


--------------------------------------------------------------------------------
-- Update ghost positions + sound loop
--------------------------------------------------------------------------------
local function UpdateGhostPositions()
    local mx, my = spGetMouseState()
    local _, pos = spTraceScreenRay(mx, my, true)
    if not pos then return end

    local tx, ty, tz = pos[1], pos[2], pos[3]

    local cx, cy, cz = 0, 0, 0
    for _, g in ipairs(ghostData) do
        cx = cx + g.ox
        cy = cy + g.oy
        cz = cz + g.oz
    end
    cx = cx / #ghostData
    cy = cy / #ghostData
    cz = cz / #ghostData

    for _, g in ipairs(ghostData) do
        local dx = g.ox - cx
        local dz = g.oz - cz

        local rx = dx * math.cos(math.rad(rotation)) - dz * math.sin(math.rad(rotation))
        local rz = dx * math.sin(math.rad(rotation)) + dz * math.cos(math.rad(rotation))

        -- Ask the engine itself for the exact valid build position nearest
        -- our target, instead of guessing our own grid alignment. Crucially
        -- minDistance=0: that parameter is meant to space out same-type
        -- buildings (e.g. wind turbines), which would push a tight wall of
        -- Dragon's Teeth apart if left non-zero. searchRadius is kept small
        -- so it only corrects sub-grid rounding, not drift to a different spot.
        local facing = ToBuildFacing(rotation)
        local bx, by, bz = Spring.ClosestBuildPos(
            spGetMyTeamID(), g.udid, tx + rx, ty, tz + rz, 16, 0, facing
        )

        g.gx = bx or (tx + rx)
        g.gy = by or ty
        g.gz = bz or (tz + rz)

        local canBuild = spTestBuildOrder(g.udid, g.gx, g.gy, g.gz, facing)
        g.valid = (canBuild == 2)
    end

    -- Track the destination centroid (where the clone is actually landing)
    -- so DrawWorld can show the helper-recruit radius ring around it.
    local sumX, sumZ = 0, 0
    for _, g in ipairs(ghostData) do
        sumX = sumX + g.gx
        sumZ = sumZ + g.gz
    end
    ghostCenterX = sumX / #ghostData
    ghostCenterZ = sumZ / #ghostData

    if lastSoundTime then
        local now = spGetTimer()
        local dt = spDiffTimers(now, lastSoundTime)
        if dt > soundInterval then
            spPlaySoundFile("LuaUI/Sounds/land.wav", 1.0)
            lastSoundTime = now
        end
    end
end

--------------------------------------------------------------------------------
-- MousePress: start drag-copy (Shift)
--------------------------------------------------------------------------------
function widget:MousePress(x, y, button)
    local ctrl, alt, meta, shift = Spring.GetModKeyState()
    if button == 1 and shift then
        local builders, buildings = SplitSelection()

        -- Every single building in the selection has to be individually
        -- clonable (i.e. added while shift was held - see clonableUnits /
        -- widget:SelectionChanged below). If even one of them was picked
        -- up by a plain click/drag, the whole drag falls through instead
        -- of dragging the mix.
        local allClonable = #buildings > 0
        for _, b in ipairs(buildings) do
            if not clonableUnits[b] then
                allClonable = false
                break
            end
        end

        if allClonable then
            -- Whatever constructors (if any) are manually selected right
            -- now. We don't recruit helpers here - we don't know where
            -- this is landing yet, and helpers should be picked near the
            -- drop site, not the source. That happens in MouseRelease.
            dragging = true
            rotation = 0
            dragBuilders = builders
            CreateGhosts(buildings)

            lastSoundTime = spGetTimer()

            return true
        end
        -- Not a clonable selection - fall through and let this be a
        -- normal (shift-)box-select drag instead.
    end
end

--------------------------------------------------------------------------------
-- SelectionChanged: the one reliable place to know how the current
-- selection came to be. Fires for clicks, box-selects (native or via our
-- footprint supplement), hotkey group recalls - anything that changes
-- selection.
--
-- The engine fires this even for a shift-drag that doesn't actually add
-- anything new (e.g. re-boxing empty ground, or re-boxing the exact same
-- group that's already selected) - so just "shift held right now" isn't
-- enough, or a leftover plain-selected group would get silently promoted
-- to clonable by an unrelated later shift-drag that happened to touch
-- nothing new. Only react when the selected SET actually changed - that's
-- what "click away to deselect, then shift-select again" (the intended
-- way to make a plain selection clonable) reliably produces: an empty-set
-- -> real-set transition.
--------------------------------------------------------------------------------
local lastSelectionSet = {}

local function SelectionSetsEqual(a, b)
    for id in pairs(a) do
        if not b[id] then return false end
    end
    for id in pairs(b) do
        if not a[id] then return false end
    end
    return true
end

function widget:SelectionChanged(sel)
    local newSet = {}
    for _, id in ipairs(sel) do
        newSet[id] = true
    end

    if SelectionSetsEqual(newSet, lastSelectionSet) then
        return -- nothing actually changed, don't touch clonable state
    end

    local ctrl, alt, meta, shift = Spring.GetModKeyState()

    if shift then
        -- A unit counts as clonable if it was ALREADY clonable (carried
        -- over from an earlier all-shift selection) or is being added
        -- fresh by THIS shift action. Units that were already selected
        -- from an earlier PLAIN action stay non-clonable - a shift-drag
        -- touching the selection at all doesn't retroactively clean them.
        local newClonable = {}
        for id in pairs(newSet) do
            if clonableUnits[id] or not lastSelectionSet[id] then
                newClonable[id] = true
            end
        end
        clonableUnits = newClonable
    else
        -- Plain selection (click or drag) - wipes clonable status entirely.
        clonableUnits = {}
    end

    lastSelectionSet = newSet
end

--------------------------------------------------------------------------------
-- MouseMove
--------------------------------------------------------------------------------
function widget:MouseMove()
    if dragging then
        UpdateGhostPositions()
        return true
    end
end


function widget:KeyPress(key)
    if not dragging then return end

    -- SPACE = rotate
    if key == 32 then
        rotation = (rotation + 90) % 360
        UpdateGhostPositions()
        return true
    end

    -- SHIFT + LMB + R = toggle swap
    local ctrl, alt, meta, shift = Spring.GetModKeyState()
    local mx, my, lmb = Spring.GetMouseState()

    if shift and lmb and key == string.byte('r') then
        swapped = not swapped
        Spring.Echo("DCB: swap = " .. tostring(swapped))
        return true
    end
end


--------------------------------------------------------------------------------
-- StartPlop: recruit helpers + issue direct build orders for one plop.
-- Only ever called when no other plop is currently active (see
-- MaybeStartNextPlop below) - that's what makes plops finish in order.
--------------------------------------------------------------------------------
local function StartPlop(plop)
    local ghosts   = plop.ghostData
    local builders = plop.builders
    local facing   = plop.facing

    --------------------------------------------------------------------
    -- Figure out what's needed and where it's landing, then recruit
    -- idle helpers near the DROP site (not the source) to cover
    -- anything the manually selected builders can't. This happens now,
    -- at start time, not at drag-release time - so if this plop was
    -- queued behind another, recruitment sees who's ACTUALLY idle once
    -- it's this plop's turn (which may well include cons that just
    -- finished helping the previous plop).
    --------------------------------------------------------------------
    local neededTypes = {}
    local cx, cz, count = 0, 0, 0
    for _, g in ipairs(ghosts) do
        neededTypes[g.udid] = true
        cx = cx + g.gx
        cz = cz + g.gz
        count = count + 1
    end

    if count > 0 then
        cx, cz = cx / count, cz / count
        local unavailable = RecruitHelpers(builders, neededTypes, cx, cz)

        local noIdleNames, noBuilderNames = {}, {}
        local missingTiers = {}
        local missingUntiered = {}
        for _, info in pairs(unavailable) do
            if info.noIdleInRadius then
                table.insert(noIdleNames, info.name)
                if info.techLevel then
                    missingTiers[info.techLevel] = true
                else
                    table.insert(missingUntiered, info.name)
                end
            else
                table.insert(noBuilderNames, info.name)
            end
        end

        -- Console log keeps the full structure list for diagnostics. The
        -- on-screen banner branches on whether ANYTHING is going to work
        -- on this plop at all (#builders here already includes both
        -- manually-selected AND auto-recruited units):
        --   - #builders == 0: nothing selected, nothing idle nearby for
        --     anything - the whole plop is stuck. Tell the player to
        --     select a con before dragging.
        --   - #builders > 0: something's already going to build part of
        --     it (manual pick or auto-recruit) - call out exactly which
        --     additional tier(s) it can't cover, so the player knows
        --     what's missing rather than a vague "select a builder".
        local bannerLines = {}
        if #noIdleNames > 0 then
            Spring.Echo("DCB: WARNING no idle con unit within radius for "
                .. table.concat(noIdleNames, " "))

            if #builders == 0 then
                table.insert(bannerLines, "No idle con unit within the radius.")
                table.insert(bannerLines, "Please shift + select a con unit, then the structures.")
            else
                local tierList = {}
                for tier in pairs(missingTiers) do
                    table.insert(tierList, tier)
                end
                table.sort(tierList)
                for _, tier in ipairs(tierList) do
                    table.insert(bannerLines, "You also need a T" .. tier .. " con unit to clone.")
                end
                for _, name in ipairs(missingUntiered) do
                    table.insert(bannerLines, "You also need a con unit that can build " .. name .. " to clone.")
                end
            end
        end
        if #noBuilderNames > 0 then
            Spring.Echo("DCB: WARNING no constructor available anywhere for "
                .. table.concat(noBuilderNames, " "))
            table.insert(bannerLines, "No constructor available to build this. Those will be skipped.")
        end
        if #bannerLines > 0 then
            screenWarningText = table.concat(bannerLines, "\n")
            screenWarningTimer = spGetTimer()
        end
    end

    local validCount = 0
    for _, g in ipairs(ghosts) do
        if g.valid then validCount = validCount + 1 end
    end
    Spring.Echo(string.format(
        "DCB: plop start - %d builder(s), %d/%d ghosts valid",
        #builders, validCount, #ghosts
    ))

    --------------------------------------------------------------------
    -- Diagnostic: per needed type, how many ghosts need it and exactly
    -- which builder IDs are considered capable of it.
    --------------------------------------------------------------------
    do
        local typeCounts = {}
        for _, g in ipairs(ghosts) do
            typeCounts[g.udid] = (typeCounts[g.udid] or 0) + 1
        end
        for udid, cnt in pairs(typeCounts) do
            local name = GetUnitDefDisplayName(udid)
            local capableList = {}
            for _, b in ipairs(builders) do
                if BuilderCanBuildType(b, udid) then
                    table.insert(capableList, "#" .. b)
                end
            end
            Spring.Echo(string.format(
                "DCB: type %s x%d - capable builder(s): %s",
                name, cnt,
                (#capableList > 0) and table.concat(capableList, ",") or "NONE"
            ))
        end
    end

    --------------------------------------------------------------------
    -- Issue a BUILD order to every builder capable of that specific
    -- type. Since only one plop is ever active at a time, a builder's
    -- queue here is always either empty or has a leftover STALE GUARD
    -- from a previous cycle (never a legit in-progress build from
    -- another plop) - clear that specific case before queuing new work.
    --------------------------------------------------------------------
    local directOrders = 0
    local checkedForStaleGuard = {}
    for _, g in ipairs(ghosts) do
        if g.valid then
            for _, builder in ipairs(builders) do
                if BuilderCanBuildType(builder, g.udid) then
                    if not checkedForStaleGuard[builder] then
                        checkedForStaleGuard[builder] = true
                        local q = Spring.GetCommandQueue(builder, 1)
                        if q and q[1] and q[1].id == CMD_GUARD then
                            spGiveOrderToUnit(builder, CMD_STOP, {}, {})
                        end
                    end
                    spGiveOrderToUnit(
                        builder,
                        -g.udid,                         -- BUILD command
                        { g.gx, g.gy, g.gz, facing },    -- position + facing
                        { "shift" }
                    )
                    directOrders = directOrders + 1
                end
            end
        end
    end
    Spring.Echo("DCB: plop start - issued " .. directOrders .. " direct build order(s)")

    --------------------------------------------------------------------
    -- Diagnostic: ask the engine itself what's actually sitting in each
    -- builder's command queue right now, right after we gave the order(s).
    --------------------------------------------------------------------
    for _, builder in ipairs(builders) do
        local queue = Spring.GetCommandQueue(builder, -1)
        local qlen = queue and #queue or -1
        local firstDesc = "none"
        if queue and queue[1] then
            local c = queue[1]
            firstDesc = string.format("id=%s params=%s",
                tostring(c.id), table.concat(c.params or {}, ","))
        end
        local vx, vy, vz, speed = Spring.GetUnitVelocity(builder)
        local bx, by, bz = spGetUnitPosition(builder)
        Spring.Echo(string.format(
            "DCB: post-order check - builder #%s pos=(%.0f,%.0f,%.0f) queue_len=%s first_cmd=[%s] speed=%s",
            tostring(builder), bx or -1, by or -1, bz or -1,
            tostring(qlen), firstDesc, tostring(speed)
        ))
    end

    -- Hand off to the periodic assist checker: once any of these
    -- builders finishes its own share, it'll be sent to guard/help
    -- whichever builder(s) still have work left in THIS plop. Once the
    -- whole plop is done, this triggers the next queued plop to start.
    activeBuild = { builders = builders }
    helperAssistTimer = spGetTimer() -- delay first check so fresh orders have time to register
end

MaybeStartNextPlop = function()
    if not activeBuild and #plopQueue > 0 then
        local plop = table.remove(plopQueue, 1)
        Spring.Echo("DCB: starting next plop (" .. #plopQueue .. " still queued)")
        StartPlop(plop)
    end
end

--------------------------------------------------------------------------------
-- MouseRelease: snapshot this drag as a plop and queue it up. It only
-- actually starts (recruiting helpers, issuing orders) once no other plop
-- is in progress - see StartPlop/MaybeStartNextPlop above.
--------------------------------------------------------------------------------
function widget:MouseRelease()
    if dragging then
        dragging = false
        lastSoundTime = nil

        -- Use the builder(s) locked in when the drag started, not whatever
        -- happens to be selected right now - the selection can change
        -- mid-drag, which used to make the whole build silently do nothing.
        local builders = dragBuilders
        dragBuilders = {}

        ApplyPattern(ghostData)

        local plop = {
            ghostData = ghostData,
            builders  = builders,
            facing    = ToBuildFacing(rotation),
        }
        table.insert(plopQueue, plop)
        Spring.Echo("DCB: queued plop (" .. #plopQueue .. " pending)")

        ghostData = {}
        MaybeStartNextPlop()
        return true
    end
end

--------------------------------------------------------------------------------
-- Poll the left mouse button every frame to catch box-select drags
-- (see note above pollDragTracking for why we can't just use MouseRelease).
--
-- The footprint supplement (what lets you box-select Dragon's Teeth) only
-- runs on a SHIFT-held drag now. A plain drag is left completely alone so
-- it behaves exactly like vanilla Spring/BAR selection - which already
-- prioritizes mobile units over buildings in a mixed box (e.g. dragging
-- over some DTs, a radar, turbines, and 2 con bots selects just the 2 con
-- bots). Our supplement used to run on every plain drag and silently
-- overrode that, adding every building in the box regardless - confusing
-- since it didn't match how selection normally works. Shift+drag is now
-- the explicit "also grab structures/DTs" gesture.
--------------------------------------------------------------------------------
function widget:Update()
    local mx, my, lmb = Spring.GetMouseState()

    if lmb and not wasLmbDown then
        -- Button just went down this frame.
        local ctrl, alt, meta, shift = Spring.GetModKeyState()
        if not dragging and shift then
            pollDragStartX, pollDragStartY = mx, my
            pollDragTracking = true
        else
            -- Plain drag (vanilla selection only) or a clone-copy drag
            -- (or something else) owns this click instead.
            pollDragTracking = false
        end

    elseif not lmb and wasLmbDown then
        -- Button just went up this frame.
        if pollDragTracking and not dragging then
            TryFootprintBoxSelect(pollDragStartX, pollDragStartY, mx, my)
        end
        pollDragTracking = false
    end

    wasLmbDown = lmb

    if activeBuild then
        local now = spGetTimer()
        if not helperAssistTimer or spDiffTimers(now, helperAssistTimer) > HELPER_ASSIST_INTERVAL then
            helperAssistTimer = now
            TickHelperAssist()
        end
    elseif #plopQueue > 0 then
        -- Nothing active but something's waiting - safety net in case a
        -- plop ever ends up queued without a start being triggered.
        MaybeStartNextPlop()
    end
end

function widget:DrawScreen()
    -- On-screen warning banner (e.g. "no idle con unit within the
    -- radius") - independent of dragging state, since a queued plop (and
    -- any resulting warning) can start well after its drag has ended.
    if screenWarningText and screenWarningTimer then
        local now = spGetTimer()
        if spDiffTimers(now, screenWarningTimer) < SCREEN_WARNING_DURATION then
            local vsx, vsy = Spring.GetViewGeometry()
            local bx, by = vsx / 2, vsy * 0.75
            local lineHeight = 30

            gl.Color(0, 0, 0, 0.85)
            gl.Text("Clone Builder Widget", bx + 3, by + lineHeight - 3, 26, "oc")
            gl.Color(1, 1, 1, 1)
            gl.Text("Clone Builder Widget", bx, by + lineHeight, 26, "oc")

            local lineIndex = 0
            for line in screenWarningText:gmatch("[^\n]+") do
                local ly = by - (lineIndex * lineHeight)
                gl.Color(0, 0, 0, 0.85)
                gl.Text(line, bx + 3, ly - 3, 24, "oc")
                gl.Color(1, 0.25, 0.15, 1)
                gl.Text(line, bx, ly, 24, "oc")
                lineIndex = lineIndex + 1
            end
        else
            screenWarningText = nil
            screenWarningTimer = nil
        end
    end

    if not dragging then return end

    -- Get mouse world position
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    if not pos then return end

    local px, py, pz = pos[1], pos[2], pos[3]

    -- Convert world → screen
    local sx, sy = Spring.WorldToScreenCoords(px, py, pz)
    if not sx or not sy then return end

    ---------------------------------------------------------
    -- Determine layout orientation
    ---------------------------------------------------------
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    for _, g in ipairs(ghostData) do
        if g.gx < minX then minX = g.gx end
        if g.gx > maxX then maxX = g.gx end
        if g.gz < minZ then minZ = g.gz end
        if g.gz > maxZ then maxZ = g.gz end
    end
    local width  = maxX - minX
    local height = maxZ - minZ
    local isHorizontal = width > height

    local label
    if not swapped then
        label = isHorizontal and "Column" or "Row"
    else
        label = isHorizontal and "Row" or "Column"
    end

---------------------------------------------------------
-- SCREEN-SPACE TEXT WITH SHADOW
---------------------------------------------------------

local shadowOffset = 3
local labelSize    = 36
local hintSize     = 18

---------------------------------------------------------
-- Row/Column label (TOP)
---------------------------------------------------------
gl.Color(0, 0, 0, 0.8)
gl.Text(label, sx + shadowOffset, sy + 60 - shadowOffset, labelSize, "oc")

gl.Color(1, 1, 1, 1)
gl.Text(label, sx, sy + 60, labelSize, "oc")

---------------------------------------------------------
-- Spacebar hint (MIDDLE)
---------------------------------------------------------
gl.Color(0, 0, 0, 0.8)
gl.Text("Spacebar to rotate", sx + shadowOffset, sy + 30 - shadowOffset, hintSize, "oc")

gl.Color(1, 1, 1, 1)
gl.Text("Spacebar to rotate", sx, sy + 30, hintSize, "oc")

---------------------------------------------------------
-- R to change pattern (BOTTOM)
---------------------------------------------------------
gl.Color(0, 0, 0, 0.8)
gl.Text("R to change pattern", sx + shadowOffset, sy + 0 - shadowOffset, hintSize, "oc")

gl.Color(1, 1, 1, 1)
gl.Text("R to change pattern", sx, sy + 0, hintSize, "oc")


    end

--------------------------------------------------------------------------------
-- Draw a thin ring on the ground, same idea as the commander's D-Gun range
-- ring, to show how far the helper-recruit search reaches from the drop site.
--------------------------------------------------------------------------------
local spGetGroundHeight = Spring.GetGroundHeight

local function DrawGroundRing(cx, cz, radius, segments, r, g, b, a)
    segments = segments or 72
    gl.Color(r, g, b, a)
    gl.LineWidth(3.5)
    gl.BeginEnd(GL.LINE_LOOP, function()
        for i = 0, segments - 1 do
            local theta = (i / segments) * 2 * math.pi
            local px = cx + radius * math.cos(theta)
            local pz = cz + radius * math.sin(theta)
            local py = (spGetGroundHeight(px, pz) or 0) + 3
            gl.Vertex(px, py, pz)
        end
    end)
    gl.LineWidth(1.0)
end

-- Filled version of the same circle, for a soft tint across the whole
-- recruit area rather than just an outline.
local function DrawGroundDisc(cx, cz, radius, segments, r, g, b, a)
    segments = segments or 72
    gl.Color(r, g, b, a)
    gl.BeginEnd(GL.TRIANGLE_FAN, function()
        gl.Vertex(cx, (spGetGroundHeight(cx, cz) or 0) + 2, cz)
        for i = 0, segments do
            local theta = (i / segments) * 2 * math.pi
            local px = cx + radius * math.cos(theta)
            local pz = cz + radius * math.sin(theta)
            local py = (spGetGroundHeight(px, pz) or 0) + 2
            gl.Vertex(px, py, pz)
        end
    end)
end

--------------------------------------------------------------------------------
-- Draw ghosts
--------------------------------------------------------------------------------
function widget:DrawWorld()
    if not dragging and #plopQueue == 0 then return end

    if dragging then
        ---------------------------------------------------------
        -- Get mouse world position
        ---------------------------------------------------------
        local mx, my = Spring.GetMouseState()
        local _, pos = Spring.TraceScreenRay(mx, my, true)

        if pos then
            local px, py, pz = pos[1], pos[2], pos[3]

            ---------------------------------------------------------
            -- Determine layout orientation
            ---------------------------------------------------------
            local minX, maxX = math.huge, -math.huge
            local minZ, maxZ = math.huge, -math.huge
            for _, g in ipairs(ghostData) do
                if g.gx < minX then minX = g.gx end
                if g.gx > maxX then maxX = g.gx end
                if g.gz < minZ then minZ = g.gz end
                if g.gz > maxZ then maxZ = g.gz end
            end
            local width  = maxX - minX
            local height = maxZ - minZ
            local isHorizontal = width > height

            ---------------------------------------------------------
            -- Corrected label
            ---------------------------------------------------------
            local label
            if not swapped then
                label = isHorizontal and "Column" or "Row"
            else
                label = isHorizontal and "Row" or "Column"
            end

            ---------------------------------------------------------
            -- Draw ghosts (original behavior)
            ---------------------------------------------------------
            gl.DepthTest(true)

            for _, g in ipairs(ghostData) do
                if g.valid then gl.Color(0, 1, 0, 0.4)
                else gl.Color(1, 0, 0, 0.4) end

                gl.PushMatrix()
                gl.Translate(g.gx, g.gy, g.gz)
                gl.Rotate(rotation, 0, 1, 0)
                gl.UnitShape(g.udid, 0)
                gl.PopMatrix()
            end

            -- Helper-recruit radius: any idle constructor inside this
            -- circle (centered on the drop site) gets pulled in to help
            -- on release. Filled with a slight yellow tint across the
            -- whole area, plus a solid ring for a crisp edge.
            if ghostCenterX then
                DrawGroundDisc(ghostCenterX, ghostCenterZ, HELPER_RECRUIT_RADIUS, 72, 1, 0.85, 0, 0.05)
                DrawGroundRing(ghostCenterX, ghostCenterZ, HELPER_RECRUIT_RADIUS, 72, 1, 0.85, 0, 1.0)
            end

            gl.DepthTest(false)

            ---------------------------------------------------------
            -- SCREEN-SPACE TEXT (ALWAYS UPRIGHT, ALWAYS VISIBLE)
            ---------------------------------------------------------
            local sx, sy = Spring.WorldToScreenCoords(px, py, pz)
            if sx and sy then
                gl.Color(1, 1, 1, 1)
                gl.Text(label, sx, sy + 40, 30, "oc")
                gl.Text("Spacebar to rotate", sx, sy + 20, 10, "oc")
                gl.Color(1, 1, 1, 1)
            end
        end
    end

    ---------------------------------------------------------
    -- Static preview for plops still waiting in the queue. Their build
    -- orders haven't been issued yet (that only happens once it's their
    -- turn), so the engine has no blueprint outline for them yet - draw
    -- our own so they're not just invisible in the meantime. Blue marks
    -- "queued, not started" as distinct from the green/red of the plop
    -- you're actively dragging.
    ---------------------------------------------------------
    if #plopQueue > 0 then
        gl.DepthTest(true)
        for _, plop in ipairs(plopQueue) do
            gl.Color(0.3, 0.6, 1, 0.35)
            for _, g in ipairs(plop.ghostData) do
                gl.PushMatrix()
                gl.Translate(g.gx, g.gy, g.gz)
                gl.Rotate((plop.facing or 0) * 90, 0, 1, 0)
                gl.UnitShape(g.udid, 0)
                gl.PopMatrix()
            end
        end
        gl.DepthTest(false)
    end
end


-- end of drag_copy_builder.lua
