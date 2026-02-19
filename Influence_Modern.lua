------------------------------------------------------------
-- Influence_Modern v1.2
-- Text-button edition (Top Bar / Eco Graph style, draggable, saved position)
-- Influence logic unchanged
------------------------------------------------------------

function widget:GetInfo()
return {
    name      = "Influence_Modern v1.2",
    desc      = "Real-time influence heatmap with text-button UI",
    author    = "Kerwin + Copilot",
    date      = "2026",
    license   = "GPLv2",
    layer     = 0,
    enabled   = false
}
end

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local GRID_RESOLUTION = 64
local CHUNK_SIZE = 8
local MOVE_THRESHOLD = GRID_RESOLUTION

local INTENSITY = {
    weak   = 0.25,
    medium = 0.45,
    strong = 0.65,
    max    = 0.85,
}

------------------------------------------------------------
-- SPRING SHORTCUTS
------------------------------------------------------------

local spGetUnitPosition   = Spring.GetUnitPosition
local spGetUnitTeam       = Spring.GetUnitTeam
local spGetUnitAllyTeam   = Spring.GetUnitAllyTeam
local spGetUnitDefID      = Spring.GetUnitDefID
local spGetTeamColor      = Spring.GetTeamColor
local spGetGroundHeight   = Spring.GetGroundHeight
local spGetMouseState     = Spring.GetMouseState

local glColor      = gl.Color
local glVertex     = gl.Vertex
local glBeginEnd   = gl.BeginEnd
local glCallList   = gl.CallList
local glCreateList = gl.CreateList
local glDeleteList = gl.DeleteList
local glText       = gl.Text

local GL_QUADS = GL.QUADS

------------------------------------------------------------
-- INTERNAL STATE
------------------------------------------------------------

local grid = {}
local gridVerts = {}
local drawChunks = {}
local chunkNeedsUpdate = {}
local unitData = {}
local quickDefs = {}
local captainColor = {}

local mapX = Game.mapSizeX
local mapZ = Game.mapSizeZ

local numCellsX = math.floor(mapX / GRID_RESOLUTION)
local numCellsZ = math.floor(mapZ / GRID_RESOLUTION)

local numChunksX = math.ceil(numCellsX / CHUNK_SIZE)
local numChunksZ = math.ceil(numCellsZ / CHUNK_SIZE)

local defaultDamageType = Game.armorTypes["default"]

local updateCounter = 0
local chunkCounter = 1
local drawer = false   -- OFF by default (no overlay shown)

------------------------------------------------------------
-- ICON BUTTON CONFIG (POSITION)
------------------------------------------------------------

-- We keep normalized coordinates so old configs still make sense.
-- buttonX / buttonY represent the top-left corner in [0..1] of the screen.
local buttonX = 1.0 - 0.04 - 0.02
local buttonY = 1.0 - 0.04 - 0.02

-- Match size with gui_vertical_toggle_menu
local buttonW = 0.04
local buttonH = 0.04


local dragging   = false
local dragMoved  = false
local dragStartX = 0
local dragStartY = 0
local dragOffsetX = 0
local dragOffsetY = 0

------------------------------------------------------------
-- UTILITY
------------------------------------------------------------

local function CellToChunk(cx, cz)
return (math.floor(cz / CHUNK_SIZE) * numChunksX) + math.floor(cx / CHUNK_SIZE) + 1
end

local function ChunkBounds(chunkID)
chunkID = chunkID - 1
local cx = chunkID % numChunksX
local cz = math.floor(chunkID / numChunksX)

local minX = cx * CHUNK_SIZE
local maxX = minX + CHUNK_SIZE - 1
local minZ = cz * CHUNK_SIZE
local maxZ = minZ + CHUNK_SIZE - 1

return minX, maxX, minZ, maxZ
end

local function MakeCellVerts(cx, cz)
local x1 = cx * GRID_RESOLUTION
local z1 = cz * GRID_RESOLUTION
local x2 = x1 + GRID_RESOLUTION
local z2 = z1 + GRID_RESOLUTION

return {
    {x1, spGetGroundHeight(x1, z1), z1},
    {x2, spGetGroundHeight(x2, z1), z1},
    {x2, spGetGroundHeight(x2, z2), z2},
    {x1, spGetGroundHeight(x1, z2), z2},
}
end

local function DrawCell(coord)
local v = gridVerts[coord]
glVertex(v[1])
glVertex(v[2])
glVertex(v[3])
glVertex(v[4])
end

------------------------------------------------------------
-- GRID INITIALIZATION
------------------------------------------------------------

local function PopulateGrid()
for cx = 0, numCellsX do
    for cz = 0, numCellsZ do
        local coord = cx .. "," .. cz

        grid[coord] = { allyTeam = nil, strength = 0 }
        gridVerts[coord] = MakeCellVerts(cx, cz)
        end
        end

        for i = 1, numChunksX * numChunksZ do
            chunkNeedsUpdate[i] = true
            end

            captainColor = {}
            local allyTeams = Spring.GetAllyTeamList()
            for _, at in ipairs(allyTeams) do
                local teams = Spring.GetTeamList(at)
                if teams and #teams > 0 then
                    local lowest = teams[1]
                    for i = 2, #teams do
                        if teams[i] < lowest then lowest = teams[i] end
                            end
                            local r, g, b = spGetTeamColor(lowest)
                            captainColor[at] = {r = r or 0.5, g = g or 0.5, b = b or 0.5}
                            else
                                captainColor[at] = {r = 0.5, g = 0.5, b = 0.5}
                                end
                                end
                                end

                                ------------------------------------------------------------
                                -- INFLUENCE ACCUMULATION
                                ------------------------------------------------------------

                                local function AddInfluence(cx, cz, allyTeam, amount)
                                local coord = cx .. "," .. cz
                                local cell = grid[coord]

                                if not cell then
                                    grid[coord] = { allyTeam = allyTeam, strength = amount }
                                    chunkNeedsUpdate[CellToChunk(cx, cz)] = true
                                    return
                                    end

                                    if amount > cell.strength then
                                        cell.strength = amount
                                        cell.allyTeam = allyTeam
                                        chunkNeedsUpdate[CellToChunk(cx, cz)] = true
                                        end
                                        end

                                        ------------------------------------------------------------
                                        -- UNIT PROFILES
                                        ------------------------------------------------------------

                                        local function BuildUnitProfile(udid)
                                        local ud = UnitDefs[udid]
                                        if not ud then return nil end

                                            if ud.speed == 0 and #ud.weapons == 0 then
                                                return { dps = 20, range = 200 }
                                                end

                                                local maxDPS = 0
                                                local maxRange = 150

                                                for _, w in ipairs(ud.weapons) do
                                                    local wd = WeaponDefs[w.weaponDef]
                                                    if wd and wd.canAttackGround and wd.type ~= "Shield" then
                                                        local dmg = wd.damages[defaultDamageType] or 0
                                                        local reload = wd.reload or 1
                                                        local dps = dmg / reload

                                                        if wd.type == "BeamLaser" then dps = dps * 0.5 end

                                                            if dps > maxDPS then maxDPS = math.min(dps, 2000) end
                                                                if wd.range > maxRange then maxRange = math.min(wd.range, 2000) end
                                                                    end
                                                                    end

                                                                    if maxDPS == 0 then
                                                                        local metal = ud.metalCost + (ud.energyCost / 70)
                                                                        maxDPS = math.max(5, metal / 10)
                                                                        maxRange = math.max(256, metal / 10)
                                                                        end

                                                                        return { dps = maxDPS, range = maxRange }
                                                                        end

                                                                        ------------------------------------------------------------
                                                                        -- APPLY UNIT INFLUENCE
                                                                        ------------------------------------------------------------

                                                                        local function ApplyUnitInfluence(unitID, udid, teamID)
                                                                        local allyTeam = spGetUnitAllyTeam(unitID)
                                                                        if not allyTeam then return end

                                                                            local x, _, z = spGetUnitPosition(unitID)
                                                                            if not x then return end

                                                                                local cx = math.floor(x / GRID_RESOLUTION)
                                                                                local cz = math.floor(z / GRID_RESOLUTION)

                                                                                local profile = quickDefs[udid]
                                                                                if not profile then
                                                                                    profile = BuildUnitProfile(udid)
                                                                                    quickDefs[udid] = profile
                                                                                    end

                                                                                    if not profile then return end

                                                                                        local range = profile.range
                                                                                        local dps   = profile.dps

                                                                                        local gridRadius = math.ceil(range / GRID_RESOLUTION)

                                                                                        for dx = -gridRadius, gridRadius do
                                                                                            for dz = -gridRadius, gridRadius do
                                                                                                local gx = cx + dx
                                                                                                local gz = cz + dz

                                                                                                if gx >= 0 and gz >= 0 and gx <= numCellsX and gz <= numCellsZ then
                                                                                                    local dist = (dx * GRID_RESOLUTION)^2 + (dz * GRID_RESOLUTION)^2
                                                                                                    if dist <= range * range then
                                                                                                        AddInfluence(gx, gz, allyTeam, dps)
                                                                                                        end
                                                                                                        end
                                                                                                        end
                                                                                                        end
                                                                                                        end

                                                                                                        ------------------------------------------------------------
                                                                                                        -- UNIT TRACKING
                                                                                                        ------------------------------------------------------------

                                                                                                        local function TrackUnit(unitID)
                                                                                                        local udid = spGetUnitDefID(unitID)
                                                                                                        if not udid then return end

                                                                                                            local teamID = spGetUnitTeam(unitID)
                                                                                                            if not teamID then return end

                                                                                                                local x, _, z = spGetUnitPosition(unitID)
                                                                                                                if not x then return end

                                                                                                                    local cx = math.floor(x / GRID_RESOLUTION)
                                                                                                                    local cz = math.floor(z / GRID_RESOLUTION)

                                                                                                                    unitData[unitID] = { cx = cx, cz = cz, udid = udid, team = teamID }
                                                                                                                    ApplyUnitInfluence(unitID, udid, teamID)
                                                                                                                    end

                                                                                                                    local function UpdateUnitMovement(unitID)
                                                                                                                    local data = unitData[unitID]
                                                                                                                    if not data then return end

                                                                                                                        local x, _, z = spGetUnitPosition(unitID)
                                                                                                                        if not x then
                                                                                                                            unitData[unitID] = nil
                                                                                                                            return
                                                                                                                            end

                                                                                                                            local cx = math.floor(x / GRID_RESOLUTION)
                                                                                                                            local cz = math.floor(z / GRID_RESOLUTION)

                                                                                                                            local dx = math.abs(cx - data.cx) * GRID_RESOLUTION
                                                                                                                            local dz = math.abs(cz - data.cz) * GRID_RESOLUTION

                                                                                                                            if dx >= MOVE_THRESHOLD or dz >= MOVE_THRESHOLD then
                                                                                                                                data.cx = cx
                                                                                                                                data.cz = cz
                                                                                                                                ApplyUnitInfluence(unitID, data.udid, data.team)
                                                                                                                                end
                                                                                                                                end

                                                                                                                                ------------------------------------------------------------
                                                                                                                                -- UNITTRACKERAPI
                                                                                                                                ------------------------------------------------------------

                                                                                                                                local function ProcessVisibleUnits()
                                                                                                                                local api = WG.unittrackerapi
                                                                                                                                if not api or not api.visibleUnits then return end

                                                                                                                                    for unitID, udid in pairs(api.visibleUnits) do
                                                                                                                                        TrackUnit(unitID)
                                                                                                                                        end
                                                                                                                                        end

                                                                                                                                        ------------------------------------------------------------
                                                                                                                                        -- COLOR SELECTION
                                                                                                                                        ------------------------------------------------------------

                                                                                                                                        local function GetCellColor(allyTeam, strength)
                                                                                                                                        if not allyTeam or strength <= 0 then
                                                                                                                                            return 0, 0, 0, 0
                                                                                                                                            end

                                                                                                                                            local c = captainColor[allyTeam]
                                                                                                                                            if not c then return 0, 0, 0, 0 end

                                                                                                                                                local alpha
                                                                                                                                                if strength < 300 then
                                                                                                                                                    alpha = INTENSITY.weak
                                                                                                                                                    elseif strength < 800 then
                                                                                                                                                        alpha = INTENSITY.medium
                                                                                                                                                        elseif strength < 1500 then
                                                                                                                                                            alpha = INTENSITY.strong
                                                                                                                                                            else
                                                                                                                                                                alpha = INTENSITY.max
                                                                                                                                                                end

                                                                                                                                                                return c.r, c.g, c.b, alpha
                                                                                                                                                                end

                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                -- CHUNK DRAWING
                                                                                                                                                                ------------------------------------------------------------

                                                                                                                                                                local function RedrawChunk(chunkID)
                                                                                                                                                                if drawChunks[chunkID] then
                                                                                                                                                                    glDeleteList(drawChunks[chunkID])
                                                                                                                                                                    end

                                                                                                                                                                    drawChunks[chunkID] = glCreateList(function()
                                                                                                                                                                    local minX, maxX, minZ, maxZ = ChunkBounds(chunkID)

                                                                                                                                                                    for cx = minX, maxX do
                                                                                                                                                                        for cz = minZ, maxZ do
                                                                                                                                                                            if cx >= 0 and cz >= 0 and cx <= numCellsX and cz <= numCellsZ then
                                                                                                                                                                                local coord = cx .. "," .. cz
                                                                                                                                                                                local cell = grid[coord]

                                                                                                                                                                                if cell and cell.strength > 0 then
                                                                                                                                                                                    local r, g, b, a = GetCellColor(cell.allyTeam, cell.strength)
                                                                                                                                                                                    if a > 0 then
                                                                                                                                                                                        glColor(r, g, b, a)
                                                                                                                                                                                        glBeginEnd(GL_QUADS, DrawCell, coord)
                                                                                                                                                                                        end
                                                                                                                                                                                        end
                                                                                                                                                                                        end
                                                                                                                                                                                        end
                                                                                                                                                                                        end
                                                                                                                                                                                        end)
                                                                                                                                                                    end

                                                                                                                                                                    local function DrawAllChunks()
                                                                                                                                                                    for _, list in pairs(drawChunks) do
                                                                                                                                                                        glCallList(list)
                                                                                                                                                                        end
                                                                                                                                                                        end

                                                                                                                                                                        ------------------------------------------------------------
                                                                                                                                                                        -- WORLD DRAW
                                                                                                                                                                        ------------------------------------------------------------

                                                                                                                                                                        function widget:DrawWorldPreUnit()
                                                                                                                                                                        if drawer then
                                                                                                                                                                            DrawAllChunks()
                                                                                                                                                                            end
                                                                                                                                                                            end

                                                                                                                                                                            ------------------------------------------------------------
                                                                                                                                                                            -- CHUNK UPDATE LOOP
                                                                                                                                                                            ------------------------------------------------------------

                                                                                                                                                                            local function UpdateChunks()
                                                                                                                                                                            local CHUNKS_PER_FRAME = 4

                                                                                                                                                                            for i = chunkCounter, chunkCounter + CHUNKS_PER_FRAME do
                                                                                                                                                                                if i > numChunksX * numChunksZ then break end
                                                                                                                                                                                    if chunkNeedsUpdate[i] then
                                                                                                                                                                                        RedrawChunk(i)
                                                                                                                                                                                        chunkNeedsUpdate[i] = false
                                                                                                                                                                                        end
                                                                                                                                                                                        end

                                                                                                                                                                                        chunkCounter = chunkCounter + CHUNKS_PER_FRAME
                                                                                                                                                                                        if chunkCounter > numChunksX * numChunksZ then
                                                                                                                                                                                            chunkCounter = 1
                                                                                                                                                                                            end
                                                                                                                                                                                            end

                                                                                                                                                                                            ------------------------------------------------------------
                                                                                                                                                                                            -- INIT
                                                                                                                                                                                            ------------------------------------------------------------

                                                                                                                                                                                            function widget:Initialize()
                                                                                                                                                                                            PopulateGrid()

                                                                                                                                                                                            if WG.unittrackerapi and WG.unittrackerapi.visibleUnits then
                                                                                                                                                                                                ProcessVisibleUnits()
                                                                                                                                                                                                end

                                                                                                                                                                                                Spring.Echo("[Influence_Modern v1.2] Initialized")
                                                                                                                                                                                                end

                                                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                                                -- UNIT VISIBILITY EVENTS
                                                                                                                                                                                                ------------------------------------------------------------

                                                                                                                                                                                                function widget:VisibleUnitAdded(unitID, unitDefID, teamID)
                                                                                                                                                                                                if select(5, Spring.GetUnitHealth(unitID)) == 1 then
                                                                                                                                                                                                    TrackUnit(unitID)
                                                                                                                                                                                                    end
                                                                                                                                                                                                    end

                                                                                                                                                                                                    function widget:VisibleUnitRemoved(unitID)
                                                                                                                                                                                                    unitData[unitID] = nil
                                                                                                                                                                                                    end

                                                                                                                                                                                                    function widget:VisibleUnitsChanged(visibleUnits)
                                                                                                                                                                                                    grid = {}
                                                                                                                                                                                                    gridVerts = {}
                                                                                                                                                                                                    unitData = {}
                                                                                                                                                                                                    quickDefs = {}
                                                                                                                                                                                                    drawChunks = {}
                                                                                                                                                                                                    chunkNeedsUpdate = {}

                                                                                                                                                                                                    PopulateGrid()

                                                                                                                                                                                                    if visibleUnits then
                                                                                                                                                                                                        for unitID, udid in pairs(visibleUnits) do
                                                                                                                                                                                                            TrackUnit(unitID)
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end
                                                                                                                                                                                                            end

                                                                                                                                                                                                            ------------------------------------------------------------
                                                                                                                                                                                                            -- GAMEFRAME
                                                                                                                                                                                                            ------------------------------------------------------------

                                                                                                                                                                                                            function widget:GameFrame(frame)
                                                                                                                                                                                                            updateCounter = updateCounter + 1

                                                                                                                                                                                                            for unitID in pairs(unitData) do
                                                                                                                                                                                                                UpdateUnitMovement(unitID)
                                                                                                                                                                                                                end

                                                                                                                                                                                                                if updateCounter % 4 == 0 then
                                                                                                                                                                                                                    UpdateChunks()
                                                                                                                                                                                                                    end
                                                                                                                                                                                                                    end

                                                                                                                                                                                                                    ------------------------------------------------------------
                                                                                                                                                                                                                    -- TEXT COMMANDS
                                                                                                                                                                                                                    ------------------------------------------------------------

                                                                                                                                                                                                                    function widget:TextCommand(cmd)
                                                                                                                                                                                                                    if cmd == "inf toggle" then
                                                                                                                                                                                                                        drawer = not drawer
                                                                                                                                                                                                                        Spring.Echo("[Influence] " .. (drawer and "shown" or "hidden"))
                                                                                                                                                                                                                        end
                                                                                                                                                                                                                        end

                                                                                                                                                                                                                        ------------------------------------------------------------
                                                                                                                                                                                                                        -- PLAYER STATE
                                                                                                                                                                                                                        ------------------------------------------------------------

                                                                                                                                                                                                                        function widget:PlayerChanged()
                                                                                                                                                                                                                        local spec, fullview = Spring.GetSpectatingState()
                                                                                                                                                                                                                        if fullview and WG.unittrackerapi then
                                                                                                                                                                                                                            widget:VisibleUnitsChanged(WG.unittrackerapi.visibleUnits)
                                                                                                                                                                                                                            end
                                                                                                                                                                                                                            end

                                                                                                                                                                                                                            ------------------------------------------------------------
                                                                                                                                                                                                                            -- SHUTDOWN
                                                                                                                                                                                                                            ------------------------------------------------------------

                                                                                                                                                                                                                            function widget:Shutdown()
                                                                                                                                                                                                                            for _, list in pairs(drawChunks) do
                                                                                                                                                                                                                                glDeleteList(list)
                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                                                                                -- ICON BUTTON UI (TOP BAR / ECO GRAPH STYLE)
                                                                                                                                                                                                                                ------------------------------------------------------------

                                                                                                                                                                                                                                local size = 136  -- square icon size (matches your other toggles)

                                                                                                                                                                                                                                local function GetButtonRect()
                                                                                                                                                                                                                                local vsx, vsy = Spring.GetViewGeometry()

                                                                                                                                                                                                                                local x1 = vsx * buttonX
                                                                                                                                                                                                                                local y1 = vsy * buttonY
                                                                                                                                                                                                                                local x2 = x1 + size
                                                                                                                                                                                                                                local y2 = y1 + size

                                                                                                                                                                                                                                return x1, y1, x2, y2, vsx, vsy
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                local function IsInsideButton(x, y)
                                                                                                                                                                                                                                local x1, y1, x2, y2 = GetButtonRect()
                                                                                                                                                                                                                                return x >= x1 and x <= x2 and y >= y1 and y <= y2
                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                                                                                -- DRAW (TEXT-ONLY, NO PNG)
                                                                                                                                                                                                                                ------------------------------------------------------------

                                                                                                                                                                                                                                function widget:DrawScreen()
                                                                                                                                                                                                                                local x1, y1, x2, y2 = GetButtonRect()

                                                                                                                                                                                                                                -- Background (black translucent square)
                                                                                                                                                                                                                                glColor(0, 0, 0, 0.55)
                                                                                                                                                                                                                                gl.Rect(x1, y1, x2, y2)

                                                                                                                                                                                                                                -- Centered text
                                                                                                                                                                                                                                local cx = (x1 + x2) * 0.5
                                                                                                                                                                                                                                local cy = (y1 + y2) * 0.5

                                                                                                                                                                                                                                glColor(1, 1, 1, 1)
                                                                                                                                                                                                                                glText("Influence", cx, cy + 20, 26, "oc")

                                                                                                                                                                                                                                if drawer then
                                                                                                                                                                                                                                    glColor(0, 1, 0, 1)
                                                                                                                                                                                                                                    glText("ON", cx, cy - 20, 32, "oc")
                                                                                                                                                                                                                                    else
                                                                                                                                                                                                                                        glColor(1, 0, 0, 1)
                                                                                                                                                                                                                                        glText("OFF", cx, cy - 20, 32, "oc")
                                                                                                                                                                                                                                        end
                                                                                                                                                                                                                                        end

                                                                                                                                                                                                                                        ------------------------------------------------------------
                                                                                                                                                                                                                                        -- DRAGGING + CLICK TO TOGGLE (drag-safe)
                                                                                                                                                                                                                                        ------------------------------------------------------------

                                                                                                                                                                                                                                        function widget:MousePress(x, y, button)
                                                                                                                                                                                                                                        if button ~= 1 then return false end

                                                                                                                                                                                                                                            if IsInsideButton(x, y) then
                                                                                                                                                                                                                                                dragging   = true
                                                                                                                                                                                                                                                dragMoved  = false
                                                                                                                                                                                                                                                dragStartX = x
                                                                                                                                                                                                                                                dragStartY = y

                                                                                                                                                                                                                                                local x1, y1, x2, y2, vsx, vsy = GetButtonRect()
                                                                                                                                                                                                                                                dragOffsetX = x - x1
                                                                                                                                                                                                                                                dragOffsetY = y - y1
                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                function widget:MouseMove(x, y, dx, dy, button)
                                                                                                                                                                                                                                                if dragging then
                                                                                                                                                                                                                                                    -- Detect real movement (not a click)
                                                                                                                                                                                                                                                    if math.abs(x - dragStartX) > 3 or math.abs(y - dragStartY) > 3 then
                                                                                                                                                                                                                                                        dragMoved = true
                                                                                                                                                                                                                                                        end

                                                                                                                                                                                                                                                        local x1, y1, x2, y2, vsx, vsy = GetButtonRect()

                                                                                                                                                                                                                                                        local newX = (x - dragOffsetX) / vsx
                                                                                                                                                                                                                                                        local newY = (y - dragOffsetY) / vsy

                                                                                                                                                                                                                                                        -- Clamp to screen
                                                                                                                                                                                                                                                        if newX < 0 then newX = 0 end
                                                                                                                                                                                                                                                            if newY < 0 then newY = 0 end
                                                                                                                                                                                                                                                                if newX > 1 then newX = 1 end
                                                                                                                                                                                                                                                                if newY > 1 then newY = 1 end

                                                                                                                                                                                                                                                                buttonX = newX
                                                                                                                                                                                                                                                                buttonY = newY

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function widget:MouseRelease(x, y, button)
                                                                                                                                                                                                                                                                if dragging then
                                                                                                                                                                                                                                                                dragging = false

                                                                                                                                                                                                                                                                -- Only toggle if it was a click, not a drag
                                                                                                                                                                                                                                                                if not dragMoved and IsInsideButton(x, y) then
                                                                                                                                                                                                                                                                drawer = not drawer
                                                                                                                                                                                                                                                                Spring.Echo("[Influence] " .. (drawer and "shown" or "hidden"))
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return true
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                return false
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                                                                                                                -- SAVE / LOAD BUTTON POSITION
                                                                                                                                                                                                                                                                ------------------------------------------------------------

                                                                                                                                                                                                                                                                function widget:GetConfigData()
                                                                                                                                                                                                                                                                return {
                                                                                                                                                                                                                                                                buttonX = buttonX,
                                                                                                                                                                                                                                                                buttonY = buttonY,
                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                function widget:SetConfigData(data)
                                                                                                                                                                                                                                                                if type(data) == "table" then
                                                                                                                                                                                                                                                                buttonX = data.buttonX or buttonX
                                                                                                                                                                                                                                                                buttonY = data.buttonY or buttonY
                                                                                                                                                                                                                                                                end
                                                                                                                                                                                                                                                                end

                                                                                                                                                                                                                                                                ------------------------------------------------------------
                                                                                                                                                                                                                                                                -- END OF WIDGET
                                                                                                                                                                                                                                                                ------------------------------------------------------------
