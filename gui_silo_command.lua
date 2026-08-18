function widget:GetInfo()
  return {
    name    = "Silo Command",
    desc    = "One panel for every nuke silo: total ready, total loading, "
           .. "and a two-click arm-and-target flow that fires exactly the "
           .. "number of missiles you asked for.",
    author  = "Armis71",
    date    = "2026",
    license = "GNU GPL v2 or later",
    layer   = 0,
    enabled = true,
  }
end

--------------------------------------------------------------------
-- WHY THIS EXISTS
--------------------------------------------------------------------
-- Stockpile counts live on individual silos. With ten of them you have
-- to click each one to learn it holds 2, 1, 0, 4, 3... and then add up.
-- The information exists; it's just scattered across ten unit panels.
--
-- HOW THE FIRING WORKS
--
-- Nothing here reimplements targeting. BAR already does the right
-- thing: select N silos, press attack, right-drag, and you get N target
-- markers spread along the drag. So "arm 3" simply means "select 3
-- loaded silos and turn on the attack cursor" -- after that the game's
-- own behaviour takes over, and it behaves exactly as if you'd picked
-- the silos by hand.
--
-- The consequence, which is worth knowing: each silo contributes ONE
-- missile per volley, so the number of simultaneous targets is capped
-- by how many silos are LOADED, not by how many missiles you own. Ten
-- missiles sitting in one silo is still one target.
--------------------------------------------------------------------

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------
local UI = {
  x = nil, y = nil,          -- nil until first draw, then bottom-centre
  W = 330,                   -- MINIMUM width; the silo grid can widen it
  -- One cylinder per silo, in two fixed rows. The cylinder size never
  -- changes -- the PANEL grows sideways instead -- so a silo always
  -- looks the same whether you own two or thirty.
  CYL_W = 20,
  CYL_H = 45,
  --  CYL_W = 9,
  --  CYL_H = 12,--
  CYL_GAP = 3,
  ROW_GAP = 3,
  ROW = 31,   -- ARM/TARGET button height -- was 26, bumped ~1/5 taller
  -- Taller than ROW on purpose: this is the SALVO/STOCK/SILOS readout
  -- row, and the big number needs clear space above its label so the
  -- two don't run into each other.
  STAT_ROW = 42,   -- SALVO/STOCK/SILOS row -- tall enough for the bigger
                    -- count fonts plus a real gap above their labels
  PAD = 7,
  FONT = 14,
  SMALL = 14, -- fontsize for number of nukes shown in panel (the red numbers)
  drag = false, dragDX = 0, dragDY = 0,
}

-- Silos are rescanned on this interval rather than every frame. They
-- are built and destroyed rarely, and GetTeamUnits on a large army is
-- not something to do 60 times a second.
local SCAN_INTERVAL = 30       -- frames

-- Cooldown hand-off (rotateCooldownSilos) is checked much more often
-- than a full rescan -- a stalled single-file stream should notice its
-- silo went on cooldown and hand off within a fraction of a second, not
-- wait up to a full SCAN_INTERVAL.
local ROTATE_INTERVAL = 5      -- frames
local lastRotateCheck  = -999

-- Flip to true (e.g. via /luaui reload after editing this line, or from
-- the in-game Lua console: NUKE_MANAGER_DEBUG = true) to print why a
-- repeat rotation stalled instead of switching to another loaded silo.
NUKE_MANAGER_DEBUG = false

--------------------------------------------------------------------
local spGetTeamUnits     = Spring.GetTeamUnits
local spGetUnitDefID     = Spring.GetUnitDefID
local spGetUnitStockpile = Spring.GetUnitStockpile
local spGetMyTeamID      = Spring.GetMyTeamID
local spGetMouseState    = Spring.GetMouseState
local spGetViewGeometry  = Spring.GetViewGeometry
local spGetTimer         = Spring.GetTimer
local spDiffTimers       = Spring.DiffTimers
local spGetGameFrame     = Spring.GetGameFrame
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spGetCommandQueue  = Spring.GetCommandQueue
local glColor            = gl.Color
local glText             = gl.Text
local glRect             = gl.Rect
local glGetTextWidth     = gl.GetTextWidth
local glLineWidth        = gl.LineWidth
local glBeginEnd         = gl.BeginEnd
local glVertex           = gl.Vertex

local myTeamID  = spGetMyTeamID()
local isSiloDef = {}           -- [unitDefID] = true for offensive silos
local silos     = {}           -- { {id=, ready=, queued=, pct=}, ... }
local totalReady, totalQueued, loadedSilos = 0, 0, 0
local nextPct   = 0            -- progress of the nearest-complete missile

local armed     = 0            -- how many the player has asked for
local armedIDList = {}         -- specific unit IDs currently armed --
                                -- persists across rescans; only changed
                                -- by explicit arm/disarm/abort, never by
                                -- a passive fullness recompute (see
                                -- rescan() for why that mattered)
local repeatOn  = false        -- mirrors the silos' own repeat state
local lastRepeatTarget = nil   -- last player-issued nuke attack target; used for repeat hand-offs
local lastScan  = -999

-- Set true whenever the armed count actually changes (ARM click or wheel,
-- either direction) or repeat is toggled on/off, as long as something is
-- armed. Any of those means whatever target was last given no longer
-- matches the current setup, so TARGET flashes until the player
-- re-acquires one. Cleared the moment a fresh ATTACK order is actually
-- given (see CommandNotify), TARGET is clicked, the salvo is aborted, or
-- nothing is armed any more.
local needsRetarget = false
local RETARGET_FLASH_HZ = 2.2   -- pulses per second while it's flashing

-- Set the instant the wheel is actually scrolled; DrawScreen fades a
-- little lightning-spark burst out of this over WHEEL_FLASH_TIME. Kept
-- separate from wheelHot (cursor-in-hit-area) so the spark still plays
-- even if the mouse has already left the icon by the next frame.
local wheelSpinTimer = nil
local WHEEL_FLASH_TIME = 0.35   -- seconds

-- Fixed reference point for the selected-silo glow's pulse. A
-- continuous sine off a fixed start (rather than a per-arm timer) gives
-- a steady, even pulse instead of one that resets and looks different
-- depending on when a silo was armed.
local armGlowClock = spGetTimer()
local ARM_GLOW_HZ  = 2          -- pulses per second

--------------------------------------------------------------------
-- Which defs are OFFENSIVE silos
--------------------------------------------------------------------
-- Anti-nukes stockpile too, and they'd otherwise inflate the count and,
-- worse, get selected and told to attack ground. The stockpiled weapon
-- knows which it is: interceptors carry a non-zero `interceptor` field.
--
-- The pattern, once enough impostors turned up to see it: a genuine
-- strategic silo (nuke, EMP) is built to hit ANYWHERE on the map, so its
-- weapon range is enormous -- the real Apocalypse/Armageddon nuke silo
-- sits around 72,000. Every impostor found so far is an ordinary
-- point-defense or direct-fire weapon with a normal combat range in the
-- hundreds-to-low-thousands: Catalyst-class tactical missiles (~2,250),
-- Screamer-class AA towers (~2,400), Thor's secondary EMP rounds. That
-- range gap is the real, faction-independent tell for most impostors --
-- it covers Armada/Cortex/Legion equivalents alike without hardcoding
-- unit names one at a time as new ones get discovered.
--
-- The interceptor/mobility/ground-attack checks below are kept as
-- belt-and-suspenders (interceptors in particular could theoretically
-- also have long range, since they must reach a nuke anywhere overhead).
-- Juno is the one confirmed exception to the range tell (see below) and
-- is caught by an explicit name check instead.
local SILO_MIN_RANGE = 20000   -- comfortably above every known impostor,
                                -- comfortably below a real silo's ~72,000

-- Juno (armjuno/corjuno/legjuno) is a jammer/radar-disable utility silo,
-- not a strategic weapon. It stockpiles like a real silo, and its
-- ability description touts a "massive radius" -- likely why its
-- WeaponDef `range` reports large enough to clear SILO_MIN_RANGE even
-- though the unit panel never shows Juno a normal combat range stat.
-- It also isn't an interceptor, isn't mobile, and can attack ground, so
-- none of the other checks catch it either. The signal that never lies
-- is damage: Juno's stockpiled shot deals 0, same reason an anti-nuke
-- correctly reads DPS 0 -- neither is a real attack. Rather than keep
-- chasing inferred engine fields, Juno is excluded by name directly,
-- across every faction's equivalent.
local JUNO_NAMES = { armjuno = true, corjuno = true, legjuno = true }

local siloWeaponNum = {}       -- [unitDefID] = weapon slot index (1-based)
                                -- of the stockpile weapon, for cooldown checks
for unitDefID, ud in pairs(UnitDefs) do
  local wdID = ud.stockpileWeaponDef
  if ud.canStockpile and wdID then
    local wd = WeaponDefs[wdID]
    local isInterceptor = wd and wd.interceptor and wd.interceptor > 0
    local isMobile = (ud.speed and ud.speed > 0) or ud.canfly or ud.canMove
    local aaOnly = wd and wd.canAttackGround == false
    local longRangeEnough = wd and wd.range and wd.range >= SILO_MIN_RANGE
    local isJuno = JUNO_NAMES[ud.name]
    if longRangeEnough and not isInterceptor and not isMobile and not aaOnly and not isJuno then
      isSiloDef[unitDefID] = true
      if ud.weapons then
        for i = 1, #ud.weapons do
          if ud.weapons[i].weaponDef == wdID then
            siloWeaponNum[unitDefID] = i
            break
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function inRect(mx, my, x1, y1, x2, y2)
  return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

-- Two rows always, so the grid is columns of two: silo 1 top, silo 2
-- bottom, silo 3 the next column up, and so on.
local function gridDims()
  local n = #silos
  if n == 0 then return 0, 0, 0 end
  local cols = math.ceil(n / 2)
  local w = cols * UI.CYL_W + (cols - 1) * UI.CYL_GAP
  local h = UI.CYL_H * 2 + UI.ROW_GAP
  return cols, w, h
end

-- Minimum width that keeps the "SILO"/"COMMAND" fire-title (drawn at
-- the two column dividers, see fireTitle() in DrawScreen) clear of the
-- SALVO/STOCK/SILOS numbers on either side of it. Computed from actual
-- font metrics rather than a fixed constant, so it's still correct if
-- the title text, font sizes, or stat-number width ever change.
local function titleMinWidth()
  local numFont   = UI.FONT + 4     -- widest of the three number styles
  -- Stat numbers are effectively always 1-2 digits; sizing off "88"
  -- covers that with a little room to spare.
  local numHalfW  = glGetTextWidth("88") * numFont * 0.5

  -- Matches fireTitle()'s own sizing: text half-width plus its glow
  -- padding, using the outermost (widest) glow layer.
  local function titleHalfW(txt)
    return glGetTextWidth(txt) * UI.SMALL * 0.5 + 6 + 12
  end

  local gap = 4  -- small buffer so the glow and number never quite touch
  local needSilo    = 2 * (titleHalfW("SILO")    + numHalfW + gap)
  local needCommand = 2 * (titleHalfW("COMMAND") + numHalfW + gap)
  local q = math.max(needSilo, needCommand)
  return q * 3
end

local function panelWidth()
  local _, gw = gridDims()
  return math.max(UI.W, gw + UI.PAD * 2, titleMinWidth())
end

local function panelRect()
  local vsx, vsy = spGetViewGeometry()
  vsx, vsy = vsx or 1920, vsy or 1080
  local _, _, gh = gridDims()
  local h = UI.ROW + UI.STAT_ROW + UI.PAD * 3 + (gh > 0 and (gh + UI.PAD) or 0)
  local w = panelWidth()
  local x = UI.x or math.floor(vsx * 0.5 - w * 0.5)
  local y = UI.y or math.floor(vsy * 0.18)
  return x, y, x + w, y + h
end

local function buttonRects()
  local x1, y1, x2, y2 = panelRect()
  local rowY1 = y1 + UI.PAD
  local rowY2 = rowY1 + UI.ROW
  local mid   = x1 + (x2 - x1) * 0.52
  return x1 + UI.PAD, rowY1, mid - 2, rowY2,     -- ARM
         mid + 2, rowY1, x2 - UI.PAD, rowY2      -- TARGET
end

-- The two mini buttons live INSIDE the big ones, tucked into the
-- top-right corner. They're modifiers on their host action -- repeat
-- belongs with arming, abort with targeting -- so nesting them says
-- that better than a separate row would, and costs no height.
--
-- Because they overlap their host, the click handler MUST test these
-- first or the big button swallows them.
local MINI_H, MINI_INSET = 13, 3
-- The three readout fields, as hit boxes. They're just text, but a
-- number with no explanation is exactly the thing people want to hover.
local function statRects()
  local x1, y1, x2, y2 = panelRect()
  local W = x2 - x1
  local q = W / 3
  local ty2 = y2 - UI.PAD * 0.5
  local ty1 = ty2 - UI.STAT_ROW
  return x1, ty1, x1 + q, ty2,
         x1 + q, ty1, x1 + q * 2, ty2,
         x1 + q * 2, ty1, x2, ty2
end

local function miniRects()
  local ax1, ay1, ax2, ay2, tx1, ty1, tx2, ty2 = buttonRects()
  local rw, aw = 34, 46
  return ax2 - MINI_INSET - rw, ay2 - MINI_INSET - MINI_H,
         ax2 - MINI_INSET,      ay2 - MINI_INSET,
         tx2 - MINI_INSET - aw, ty2 - MINI_INSET - MINI_H,
         tx2 - MINI_INSET,      ty2 - MINI_INSET
end

-- Small mouse-wheel control inside ARM. Only this hit area responds to
-- MouseWheel; scrolling anywhere else in the widget is left untouched.
local WHEEL_SIZE = 22
local WHEEL_INSET = 5
local function wheelRect()
  local ax1, ay1, ax2, ay2 = buttonRects()
  local x1 = ax1 + WHEEL_INSET
  local y1 = ay1 + math.floor((ay2 - ay1 - WHEEL_SIZE) * 0.5)
  return x1, y1, x1 + WHEEL_SIZE, y1 + WHEEL_SIZE
end

-- Larger invisible hit area around the wheel. The icon stays the same size,
-- but the player does not have to pinpoint the mouse exactly on the graphic.
local WHEEL_HIT_W = 40
local function wheelHitRect()
  -- Entire widget panel accepts mousewheel
  return panelRect()
end

local function wheelGlowRect()
    -- Glow whenever mouse is anywhere over the widget window
    return panelRect()
end

local function wheelTooltipRect()
    return wheelRect()   -- small icon only
end


--------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------
-- Forward-declared: rescan() needs to call this (see below) but
-- selectArmed's real definition, which just re-applies armedIDList,
-- comes later.
local selectArmed
local readActualRepeatState
-- Also forward-declared: armMore() needs to call this when the wheel
-- drops the arm count to 0 (see below); real definition comes later.
local abortAll

local function rescan()
  silos = {}
  totalReady, totalQueued, loadedSilos, nextPct = 0, 0, 0, 0

  local units = spGetTeamUnits(myTeamID)
  if not units then return end

  for i = 1, #units do
    local uid = units[i]
    local defID = spGetUnitDefID(uid)
    if defID and isSiloDef[defID] then
      local ready, queued, pct = spGetUnitStockpile(uid)
      ready  = ready or 0
      queued = queued or 0
      pct    = pct or 0
      silos[#silos + 1] = { id = uid, defID = defID, ready = ready, queued = queued, pct = pct }
      totalReady  = totalReady + ready
      totalQueued = totalQueued + queued
      if ready > 0 then loadedSilos = loadedSilos + 1 end
      -- The most advanced missile anywhere is the one you're waiting on.
      if queued > 0 and pct > nextPct then nextPct = pct end
    end
  end

  -- Grid order is stable and has nothing to do with priority: each
  -- silo keeps the same cylinder slot for as long as it exists, sorted
  -- only by unit ID. Sorting this by ready count (as an earlier version
  -- did) made cylinders swap positions the moment stockpiles changed --
  -- so right after firing, the whole grid would reshuffle at the same
  -- moment the glow moved to different silos, which read as the glow
  -- "jumping to the wrong ones" when really two things were changing at
  -- once. With a fixed layout, only the glow moves, and it's obvious
  -- why: a silo dropped out because it just fired, another qualified.
  table.sort(silos, function(a, b) return a.id < b.id end)

  -- You cannot aim more missiles than you have loaded silos.
  if armed > loadedSilos then armed = loadedSilos end

  -- Drop any armed silo that no longer EXISTS (destroyed/reclaimed) --
  -- but deliberately nothing else. We used to also drop (and silently
  -- replace) an armed silo the instant its ready count hit 0, which
  -- sounds harmless but isn't: a silo mid-reload between repeat shots
  -- reads as ready=0 too, so that logic was swapping the highlighted
  -- silo out for whichever OTHER one happened to be fullest that
  -- instant -- every ~30 frames -- even though the real attack order
  -- (with repeat) was still permanently locked onto the original silo.
  -- The display drifted to a different "fullest" set every second
  -- while the actual launches kept coming from whoever really got the
  -- order. Now the armed list only ever changes when the player arms
  -- or disarms, so what's highlighted always matches what's live.
  do
    local currentIDs = {}
    for i = 1, #silos do currentIDs[silos[i].id] = true end
    local kept = {}
    for i = 1, #armedIDList do
      if currentIDs[armedIDList[i]] then kept[#kept + 1] = armedIDList[i] end
    end
    armedIDList = kept
    armed = #armedIDList
    if armed == 0 then needsRetarget = false end
  end

  -- Re-pin the real game selection to the (now-pruned) armed list.
  -- Without this, a silo lost from the list above (destroyed) would
  -- leave a stale unit ID in the real game selection.
  -- This keeps reselecting the silos cause the game to be unplayable can't control anything
--[[   if armed > 0 then
    selectArmed()
  end ]]

  -- Read the actual repeat state from the armed silos when possible.
  -- This keeps the RPT indicator correct even after /luaui reload or when
  -- the game changed the unit state outside this widget. If nothing is armed
  -- yet, leave the cached toggle alone until an armed silo exists.
  if #armedIDList > 0 then
    readActualRepeatState()
  end
end

--------------------------------------------------------------------
-- Arm and fire
--------------------------------------------------------------------
-- Add up to `want` NEW silos to armedIDList, fullest-ready-first,
-- skipping anything already armed. Only called when the player actually
-- increases the arm count (click/scroll) -- never from a passive
-- rescan -- so an already-armed silo keeps its slot instead of being
-- bumped the moment a fuller one appears.
local function growArmedList(want)
  local inList = {}
  for i = 1, #armedIDList do inList[armedIDList[i]] = true end

  local candidates = {}
  for i = 1, #silos do
    if silos[i].ready > 0 and not inList[silos[i].id] then
      candidates[#candidates + 1] = silos[i]
    end
  end
  table.sort(candidates, function(a, b) return a.ready > b.ready end)

  local i = 1
  while #armedIDList < want and i <= #candidates do
    armedIDList[#armedIDList + 1] = candidates[i].id
    i = i + 1
  end
end

-- Selection happens on EVERY arm click, not when you finally press
-- TARGET. One click selects one silo, two selects two -- so the game
-- highlights them as you go and the arm count is something you can see
-- on the map rather than only in this panel.
selectArmed = function()
  if #armedIDList > 0 then
    Spring.SelectUnitArray(armedIDList)
  else
    Spring.SelectUnitArray({})
  end
end

local function armMore(n)
  local beforeCount = armed
  local before = {}
  for i = 1, #armedIDList do before[armedIDList[i]] = true end

  local want = clamp(armed + n, 0, loadedSilos)

  -- Dropping to 0 (e.g. wheel-up all the way, or right-click while
  -- armed=1) has to behave exactly like the ABORT button: just trimming
  -- armedIDList down to empty leaves any already-issued attack/repeat
  -- orders running on those silos, so missiles keep launching even
  -- though the panel shows nothing armed. abortAll() sends the real
  -- Stop order.
  if want == 0 and beforeCount > 0 then
    abortAll()
    return
  end

  if want < #armedIDList then
    for i = #armedIDList, want + 1, -1 do armedIDList[i] = nil end
  elseif want > #armedIDList then
    growArmedList(want)
  end
  armed = #armedIDList
  selectArmed()

  -- ANY change to the armed count -- click or wheel, up or down --
  -- means whatever target was last given no longer matches what's
  -- armed now. Flash TARGET until the player re-acquires one, even if
  -- nothing was ever fired yet this round.
  if armed ~= beforeCount and armed > 0 then
    needsRetarget = true
  end

  -- If we just grew the list while a live repeat target already exists,
  -- the newly added silos need the same ATTACK order as the silos already
  -- firing -- otherwise they sit selected-but-idle (armed, highlighted,
  -- but never given a command) until TARGET is clicked again. This is the
  -- same hand-off rotateCooldownSilos() already does for a dry-silo swap;
  -- growing the list via ARM/wheel just never triggered it before.
  if readActualRepeatState() and lastRepeatTarget then
    local newIDs = {}
    for i = 1, #armedIDList do
      local uid = armedIDList[i]
      if not before[uid] then newIDs[#newIDs + 1] = uid end
    end
    if #newIDs > 0 then
      Spring.GiveOrderToUnitArray(newIDs, CMD.ATTACK, lastRepeatTarget, 0)
    end
  end
end

--------------------------------------------------------------------
-- Rotate off cooling-down silos (repeat mode)
--------------------------------------------------------------------
-- `ready > 0` only tells us a silo HAS a missile in stock -- not that
-- its launcher can fire RIGHT NOW. After a shot, the launcher itself
-- has its own reload/animation before its next command can go off,
-- separate from stockpile buildup. Checked via the weapon's own
-- reload frame, not the stockpile fields.
local function isOnCooldown(uid, defID)
  local wNum = siloWeaponNum[defID]
  if not wNum or not spGetUnitWeaponState then return false end
  local ok, reloadFrame = pcall(spGetUnitWeaponState, uid, wNum, "reloadFrame")
  if not ok or type(reloadFrame) ~= "number" then return false end
  return reloadFrame > spGetGameFrame()
end

-- While repeat is on, an armed silo that's gone on cooldown (or run dry)
-- hands its live target off to a fresh, ready, off-cooldown silo instead
-- of the salvo just stalling until that one launcher cycles back around.
-- This is what turns "arm 1, repeat on" into a continuous single-file
-- stream sourced from whichever of the 20 silos is actually available,
-- rather than being capped by one launcher's private reload rate.
readActualRepeatState = function()
  -- Do not trust the widget's cached repeatOn flag. BAR's repeat state can
  -- already be active on the silos after a /luaui reload, or can be changed
  -- through the game's normal unit-state controls. Read the actual state of
  -- the armed silos whenever rotation is considered.
  local sawState = false
  local sawRepeat = false
  if Spring.GetUnitStates then
    for i = 1, #armedIDList do
      local ok, st = pcall(Spring.GetUnitStates, armedIDList[i])
      if ok and type(st) == "table" and st["repeat"] ~= nil then
        sawState = true
        if st["repeat"] == true or st["repeat"] == 1 then
          sawRepeat = true
          break
        end
      end
    end
  end
  if sawState then
    repeatOn = sawRepeat
    return sawRepeat
  end
  return repeatOn
end

local function rotateCooldownSilos()
  -- The real game state is authoritative. This is especially important after
  -- /luaui reload: the silos can still be repeating even though repeatOn was
  -- reset to false when this Lua file was reloaded.
  if #armedIDList == 0 or not readActualRepeatState() then return end

  -- Refresh stockpile values directly here. The normal silo scan runs every
  -- 30 frames, but repeat rotation needs the current ready count so a newly
  -- empty armed silo can be replaced immediately by a 10/10 silo elsewhere.
  local siloByID = {}
  local candidates = {}
  local armedSet = {}

  for i = 1, #armedIDList do
    armedSet[armedIDList[i]] = true
  end

  for i = 1, #silos do
    local s = silos[i]
    local ready = 0
    local queued = 0
    local pct = 0
    local ok, r, q, pc = pcall(spGetUnitStockpile, s.id)
    if ok then
      ready = r or 0
      queued = q or 0
      pct = pc or 0
    else
      ready = s.ready or 0
      queued = s.queued or 0
      pct = s.pct or 0
    end
    siloByID[s.id] = { id = s.id, defID = s.defID, ready = ready, queued = queued, pct = pct }
  end

  -- A replacement is needed ONLY when an armed silo has run out of missiles.
  -- Do not rotate merely because a launcher is on its normal firing cooldown:
  -- if it still has stock, let that same silo cycle normally. The purpose of
  -- this rotation is to prevent stockpile exhaustion from throttling Repeat.
  local needsSlots = 0
  for i = 1, #armedIDList do
    local s = siloByID[armedIDList[i]]
    if not s or s.ready <= 0 then
      needsSlots = needsSlots + 1
    end
  end
  if needsSlots == 0 then return end

  -- Find every unarmed silo that currently has at least one missile ready.
  --
  -- NOTE: this used to also reject a candidate if isOnCooldown() said its
  -- weapon's reloadFrame was in the future. In practice that field tracks
  -- the engine's reload cycle for BUILDING the next stockpiled missile, not
  -- whether the launcher can fire an already-ready one -- so it was true
  -- for almost every partially-stocked silo almost all the time, and ended
  -- up disqualifying every real candidate. `ready > 0` from
  -- Spring.GetUnitStockpile is already the correct, sufficient signal that
  -- a silo can fire right now; isOnCooldown() is kept below (unused) in
  -- case a future debug session finds it useful for something narrower.
  for i = 1, #silos do
    local s = siloByID[silos[i].id]
    if s and s.ready > 0 and not armedSet[s.id] then
      candidates[#candidates + 1] = s
    end
  end

  table.sort(candidates, function(a, b)
    if a.ready ~= b.ready then return a.ready > b.ready end
    return a.id < b.id
  end)

  if #candidates == 0 then
    if NUKE_MANAGER_DEBUG then
      Spring.Echo(string.format(
        "[NukeManager] rotation stalled: %d slot(s) need a replacement, "
     .. "but no other silo currently has a missile in stock.",
        needsSlots))
    end
    return
  end

  -- Prefer the target recorded when the player last issued ATTACK. As a
  -- fallback, inspect the armed silos in case the command was issued before
  -- this widget version started tracking it.
  local liveTarget = lastRepeatTarget
  if not liveTarget and spGetCommandQueue then
    for i = 1, #armedIDList do
      local uid = armedIDList[i]
      local ok, queue = pcall(spGetCommandQueue, uid, 1)
      if ok and queue and queue[1] and queue[1].id == CMD.ATTACK then
        liveTarget = queue[1].params
        break
      end
    end
  end

  local candidateIndex = 1
  local changed = false

  -- Replace dry slots while preserving the requested ARM count.
  for i = #armedIDList, 1, -1 do
    local uid = armedIDList[i]
    local s = siloByID[uid]
    if not s or s.ready <= 0 then
      local candidate = candidates[candidateIndex]
      if not candidate then break end
      candidateIndex = candidateIndex + 1

      if s then
        Spring.GiveOrderToUnitArray({ uid }, CMD.STOP, {}, 0)
      end

      -- The replacement inherits the same target, so Repeat continues from
      -- the new silo instead of waiting for the old empty silo to reload.
      if liveTarget then
        Spring.GiveOrderToUnitArray({ candidate.id }, CMD.ATTACK, liveTarget, 0)
      end

      armedIDList[i] = candidate.id
      armedSet[uid] = nil
      armedSet[candidate.id] = true
      changed = true
    end
  end

  if changed then
      armed = #armedIDList
      -- selectArmed()   -- DO NOT auto-select during rotation
  end

end

-- Exactly the attack cursor, as though you'd pressed A. The silos are
-- already selected; this only turns on the command.
--
-- It re-selects first as a safeguard: you may have clicked elsewhere
-- between arming and firing, and issuing an attack command to whatever
-- happens to be selected is not a mistake worth risking with nukes.
-- Turning on the attack cursor is fiddlier than it looks.
--
-- Spring.SetActiveCommand takes EITHER an action name ("attack") or an
-- INDEX into the unit's current command list -- and the numeric form is
-- an index, not a command ID. Passing CMD.ATTACK (20) therefore picked
-- whatever happened to sit at slot 20, which for a silo is nothing.
--
-- The string form is the right one, with an index lookup as a fallback
-- for builds where the action isn't bound.
local function setAttackCursor()
  if not Spring.SetActiveCommand then return false end

  local ok, res = pcall(Spring.SetActiveCommand, "attack")
  if ok and res ~= false then return true end

  -- Fallback: find where CMD.ATTACK actually sits in the command list
  -- for the current selection, and activate it by index.
  local ok2, descs = pcall(Spring.GetActiveCmdDescs)
  if ok2 and type(descs) == "table" then
    for i = 1, #descs do
      local d = descs[i]
      if d and d.id == CMD.ATTACK then
        local ok3 = pcall(Spring.SetActiveCommand, i)
        if ok3 then return true end
      end
    end
  end
  return false
end

local function allSiloIDs()
  local ids = {}
  for i = 1, #silos do ids[#ids + 1] = silos[i].id end
  return ids
end

-- Repeat is a standing unit state, so it applies to EVERY silo rather
-- than just the armed ones -- otherwise it would silently mean
-- something different depending on what you'd armed when you pressed it.
local function toggleRepeat()
  local ids = allSiloIDs()
  if #ids == 0 then return end

  -- Synchronize with the real BAR state first. This matters after /luaui
  -- reload: the widget's local flag may say OFF while the silos themselves
  -- are still repeating.
  if #armedIDList > 0 then
    repeatOn = readActualRepeatState()
  else
    -- If nothing is armed yet, inspect the actual silo state directly.
    local sawState = false
    if Spring.GetUnitStates then
      for i = 1, #ids do
        local ok, st = pcall(Spring.GetUnitStates, ids[i])
        if ok and type(st) == "table" and st["repeat"] ~= nil then
          repeatOn = (st["repeat"] == true) or (st["repeat"] == 1)
          sawState = true
          break
        end
      end
    end
    if not sawState then repeatOn = false end
  end

  local wasOn = repeatOn
  repeatOn = not repeatOn

  -- Turning RPT OFF must not leave a repeating salvo quietly running:
  -- abort every silo's current queue (exactly what the ABORT button
  -- does) before the REPEAT order itself goes out. abortAll() also
  -- clears the arm count/armedIDList/lastRepeatTarget, which is correct
  -- here too -- a launch that just got aborted shouldn't stay "armed".
  if wasOn then
    abortAll()
  end

  Spring.GiveOrderToUnitArray(ids, CMD.REPEAT, { repeatOn and 1 or 0 }, 0)
  -- Flipping repeat either way changes how the current arm count will
  -- behave (one-shot vs. continuous hand-offs), so the player needs to
  -- reassert a target either way -- flash TARGET regardless of which
  -- direction the toggle went.
  if armed > 0 then
    needsRetarget = true
  end
end

-- Abort: exactly what Stop does in game -- clears every silo's queue,
-- so anything launched-but-unfired and everything still queued is
-- cancelled. The arm count goes with it; leaving it set after
-- cancelling the launch is the one bit of state worth not getting
-- wrong here.
abortAll = function()
  local ids = allSiloIDs()
  if #ids == 0 then return end
  Spring.GiveOrderToUnitArray(ids, CMD.STOP, {}, 0)
  armed = 0
  armedIDList = {}
  lastRepeatTarget = nil
  needsRetarget = false
  Spring.SelectUnitArray({})
end

local function engage()
  if armed <= 0 then return end

  -- If the armed count changed (or repeat was toggled) since the last
  -- target was given, silos that dropped OUT of armedIDList still have
  -- their old standing order live -- shrinking 10 -> 5 on repeat, for
  -- example, left the other 5 quietly repeating at the OLD target
  -- forever, since only the 5 still-armed silos ever got told about the
  -- new one. Stop every silo's current order before issuing the new
  -- one, so TARGET always starts the new count completely fresh instead
  -- of layering it on top of whatever the old count was doing. Also
  -- drop the remembered target so a repeat hand-off can't reuse the
  -- stale one in the gap before the player actually drags a new target.
  if needsRetarget then
    local ids = allSiloIDs()
    if #ids > 0 then
      Spring.GiveOrderToUnitArray(ids, CMD.STOP, {}, 0)
    end
    lastRepeatTarget = nil
  end

  selectArmed()
  if not setAttackCursor() then
    Spring.Echo("[NukeManager] couldn't activate the attack cursor -- "
             .. "press A instead. Silos are already selected.")
  end
  -- Clicking TARGET is the player acting on the flash -- clear it here
  -- rather than waiting on CommandNotify so the button stops flashing
  -- the instant they respond, even if they end up cancelling the drag.
  needsRetarget = false
end

--------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------
local function box(x1, y1, x2, y2, r, g, b, a)
  glColor(r, g, b, a)
  glRect(x1, y1, x2, y2)
end

-- A raised panel, built from flat rects since that's all we have here.
--
--   1. drop shadow, down and right, to lift it off the map
--   2. a light outer border
--   3. the fill
--   4. a bright top/left inner edge and a dark bottom/right one, which
--      is what actually reads as "raised" -- the border alone looks
--      printed on, the bevel makes it a physical thing
local function raisedPanel(x1, y1, x2, y2)
  -- Matched to the Eco Graph panel: a crisp 1px near-white border over
  -- a near-black fill. The first attempt used a grey border with a 3px
  -- bevel inside it, which side by side just looked soft -- the bevel
  -- blurs the very edge the border is trying to draw.
  --
  -- Depth comes from the drop shadow alone now, which is enough at this
  -- size and keeps the outline sharp.
  local s = 4
  box(x1 + s, y1 - s, x2 + s, y2 - s, 0, 0, 0, 0.50)

  box(x1, y1, x2, y2, 0.93, 0.95, 0.98, 0.97)          -- border
  box(x1 + 1, y1 + 1, x2 - 1, y2 - 1, 0.04, 0.05, 0.06, 0.95)
end

-- Buttons get the same treatment at a smaller scale, so they read as
-- sitting ON the panel rather than being holes cut into it.
-- Buttons keep a bevel -- they're small enough that a 1px highlight
-- reads as shape rather than blur, and it's what distinguishes a
-- pressed toggle from a raised one at a glance.
local function raisedButton(x1, y1, x2, y2, r, g, b, a, pressed)
  box(x1 + 1, y1 - 1, x2 + 1, y2 - 1, 0, 0, 0, 0.35)
  box(x1, y1, x2, y2, r, g, b, a)
  if pressed then
    box(x1, y2 - 1, x2, y2, 0, 0, 0, 0.35)
    box(x1, y1, x2, y1 + 1, 1, 1, 1, 0.12)
  else
    box(x1, y2 - 1, x2, y2, 1, 1, 1, 0.20)
    box(x1, y1, x2, y1 + 1, 0, 0, 0, 0.32)
  end
end

-- A small missile silhouette, built from stacked rects the same way the
-- ARM wheel icon is (no triangles/circles available here, only glRect).
-- Sized as a FRACTION of the tube (w, h) rather than fixed pixels, so it
-- still looks right if UI.CYL_W/UI.CYL_H are ever tuned.
local function drawMissileIcon(cx, cy, w, h, r, g, b, a)
  local midX = cx + w * 0.5

  -- Nose cone, tip at the top of the tube.
  box(midX - w * 0.06, cy + h * 0.82, midX + w * 0.06, cy + h * 0.95, r, g, b, a)
  box(midX - w * 0.14, cy + h * 0.68, midX + w * 0.14, cy + h * 0.82, r, g, b, a)

  -- Body.
  box(midX - w * 0.16, cy + h * 0.30, midX + w * 0.16, cy + h * 0.68, r, g, b, a)

  -- Fins, flared out at the base.
  box(midX - w * 0.32, cy + h * 0.12, midX - w * 0.14, cy + h * 0.30, r, g, b, a)
  box(midX + w * 0.14, cy + h * 0.12, midX + w * 0.32, cy + h * 0.30, r, g, b, a)

  -- Exhaust flicker at the tail -- same trick as the ARM wheel's spark
  -- flicker: chance-gated per frame so it reads as fire, not a static
  -- shape.
  if math.random() < 0.7 then
    box(midX - w * 0.08, cy + h * 0.02, midX + w * 0.08, cy + h * 0.12,
        1.0, 0.75, 0.25, a)
  end
end

function widget:DrawScreen()
  if Spring.IsGUIHidden and Spring.IsGUIHidden() then return end
  if #silos == 0 and totalQueued == 0 then return end

  local mx, my = spGetMouseState()
  local x1, y1, x2, y2 = panelRect()
  local ax1, ay1, ax2, ay2, tx1, ty1, tx2, ty2 = buttonRects()

  raisedPanel(x1, y1, x2, y2)

  ------------------------------------------------------------------
  -- Top row: the readout
  ------------------------------------------------------------------
  -- SALVO first and brightest, because it's the number you actually
  -- make decisions with. STOCK can be 10 while only 4 missiles can
  -- leave the ground this minute -- each silo fires one per volley, so
  -- a stockpile of 10 sitting in 4 loaded silos is a salvo of 4. Having
  -- to work that out from a single "READY 10" was the problem.
  local W = x2 - x1
  local q = W / 3
  -- numY is pinned a fixed distance below the panel's top border (clear
  -- of the border even at the biggest count font, SALVO's FONT+4).
  -- lblY is defined RELATIVE TO numY with a fixed gap, rather than
  -- independently off the divider, so the number and its label can
  -- never drift close enough to clash regardless of how STAT_ROW or the
  -- font sizes get tuned later.
  local numY = y2 - UI.PAD - 18
  local lblY = numY - 18

  if loadedSilos > 0 then
    glColor(0.55, 1.00, 0.60, 1)
  else
    glColor(0.42, 0.45, 0.50, 1)
  end
  glText(tostring(loadedSilos), x1 + q * 0.5, numY, UI.FONT + 4, "oc")
  glColor(0.55, 0.62, 0.70, 1)
  glText("SALVO", x1 + q * 0.5, lblY, UI.SMALL, "oc")

  glColor(0.72, 0.80, 0.90, 1)
  glText(tostring(totalReady), x1 + q * 1.5, numY, UI.FONT + 2, "oc")
  glColor(0.50, 0.55, 0.62, 1)
  glText("STOCK", x1 + q * 1.5, lblY, UI.SMALL, "oc")

  glColor(0.80, 0.85, 0.92, 1)
  glText(tostring(#silos), x1 + q * 2.5, numY, UI.FONT + 2, "oc")
  glColor(0.50, 0.55, 0.62, 1)
  glText(#silos == 1 and "SILO" or "SILOS", x1 + q * 2.5, lblY,
         UI.SMALL, "oc")

  ------------------------------------------------------------------
  -- "SILO COMMAND" -- the panel's own name, torched into the two gaps
  -- between the stat columns instead of sitting in a header row of its
  -- own. Sits on the NUMBER row (numY), not the label row, so it reads
  -- as a mark burned across the readout rather than a fourth label.
  ------------------------------------------------------------------
  local function fireTitle(txt, cx, cy, size)
    -- Blast glow first: the same widening/fading-layer trick as the ARM
    -- wheel's hover glow, just tinted hot red-orange instead of gold so
    -- it reads as a small detonation behind the letters.
    local halfW = glGetTextWidth(txt) * size * 0.5 + 6
    local glowHalf = { halfW + 12, halfW + 6, halfW + 1 }
    local glowA    = { 0.08, 0.16, 0.26 }
    for i = 1, #glowHalf do
      box(cx - glowHalf[i], cy - size * 0.35, cx + glowHalf[i], cy + size * 1.05,
          1.0, 0.30, 0.05, glowA[i])
    end
    -- Dark ember shadow offset down-right, then a hot core straight on
    -- top -- two flat text passes fake a charred-edge/white-hot-centre
    -- look without needing a custom glyph set.
    glColor(0.40, 0.04, 0.0, 0.95)
    glText(txt, cx + 1, cy - 1, size, "oc")
    glColor(1.0, 0.58, 0.15, 1)
    glText(txt, cx, cy, size, "oc")
  end

  fireTitle("SILO",    x1 + q * 1, numY, UI.SMALL)
  fireTitle("COMMAND", x1 + q * 2, numY, UI.SMALL)
  glColor(1, 1, 1, 1)

  ------------------------------------------------------------------
  -- Divider, then the silo grid
  ------------------------------------------------------------------
  -- The stats and the cylinders are different kinds of information --
  -- totals versus per-silo state -- and without a rule between them
  -- the numbers read as labels for the bars underneath.
  local cols0 = gridDims()
  if cols0 > 0 then
    local divY = y1 + UI.PAD * 2 + UI.ROW + UI.CYL_H * 2 + UI.ROW_GAP + 5
    box(x1 + UI.PAD, divY, x2 - UI.PAD, divY + 1, 0.93, 0.95, 0.98, 0.55)
  end

  ------------------------------------------------------------------
  -- Silo grid: one cylinder per silo, two rows
  ------------------------------------------------------------------
  -- Replaces a "LOADING 3" total, which said nothing about WHICH silos
  -- were close. A column of bars tells you at a glance whether the next
  -- missile lands in ten seconds or two minutes.
  local cols, gw, gh = gridDims()
  local siloHover = nil

  -- Which silos get the armed marker: built straight from armedIDList,
  -- the exact same persistent list selectArmed() uses for the real map
  -- selection -- so the highlight can never drift from what's truly
  -- selected/armed, no matter how ready counts shift between rescans.
  local armedIDs = nil
  if armed > 0 then
    armedIDs = {}
    for i = 1, #armedIDList do armedIDs[armedIDList[i]] = true end
  end

  if cols > 0 then
    local gx = x1 + (W - gw) * 0.5
    local gyTop = y1 + UI.PAD * 2 + UI.ROW + UI.CYL_H + UI.ROW_GAP
    for i = 1, #silos do
      local s = silos[i]
      local col = math.ceil(i / 2)
      local isTop = (i % 2 == 1)
      local cx = gx + (col - 1) * (UI.CYL_W + UI.CYL_GAP)
      local cy = isTop and gyTop or (gyTop - UI.CYL_H - UI.ROW_GAP)

      -- The tube is split into two stacked plates: a progress box on
      -- top (the meter itself, unchanged proportions-wise) and a count
      -- box along the bottom (~40% of the cylinder's height, big enough
      -- for the number to actually be readable), that just shows the number with a flat backing instead of
      -- competing with the fill colour.
      local countH = clamp(math.floor(UI.CYL_H * 0.4), 10, UI.CYL_H - 6)
      local progH  = UI.CYL_H - countH
      local progY  = cy + countH   -- bottom of the progress box

      -- Empty tube (progress box only)
      box(cx, progY, cx + UI.CYL_W, cy + UI.CYL_H, 0.09, 0.10, 0.13, 0.95)

      -- Count box: flat, matching the PANEL's own background rather
      -- than the tube colour, so it reads as a label plate under the
      -- meter rather than part of the meter itself.
      box(cx, cy, cx + UI.CYL_W, progY, 0.04, 0.05, 0.06, 0.95)

      -- Fill. A silo holding stock with nothing on the way shows full;
      -- otherwise the bar is the progress of the missile being loaded.
      local fill, r, g, b
      if s.queued > 0 then
        fill = s.pct
        -- Single green progression -- dim at the start, brightening as
        -- the missile nears completion, converging on the same green
        -- used for "ready" at 100%. No hue shift, just a value ramp, so
        -- the whole panel stays in one color family instead of cycling
        -- through red/orange on the way there.
        r = 0.10
        g = 0.30 + 0.62 * fill
        b = 0.14
      elseif s.ready > 0 then
        fill, r, g, b = 1, 0.30, 0.92, 0.35
      else
        fill = 0
      end
      if fill > 0 then
        box(cx + 1, progY + 1, cx + UI.CYL_W - 1,
            progY + 1 + (progH - 2) * fill, r, g, b, 1)
      end

      -- Selected-for-salvo silos get a small missile silhouette inside
      -- the progress box: a dark drop-shadow pass offset right and
      -- down, then the bright icon on top at true size. An offset
      -- shadow (rather than a symmetric outline) reads as the icon
      -- catching light from the upper-left, and still keeps it visible
      -- against the tube's own near-black empty background.
      if armedIDs and armedIDs[s.id] then
        local shadowDX, shadowDY = 2, 2  -- right, and down (GL y is up)
        drawMissileIcon(cx + shadowDX, progY - shadowDY, UI.CYL_W, progH,
                         0.0, 0.0, 0.0, 0.55)
        drawMissileIcon(cx, progY, UI.CYL_W, progH, 0.92, 0.95, 1.0, 1.0)
      end

      -- A loaded silo gets a bright cap, so "has a missile ready NOW"
      -- is readable even while the next one is only half built.
      if s.ready > 0 then
        box(cx, cy + UI.CYL_H - 2, cx + UI.CYL_W, cy + UI.CYL_H,
            0.65, 1.0, 0.70, 1)
      end

      -- Divider between the progress box and the count box below it.
      box(cx, progY, cx + UI.CYL_W, progY + 1, 0, 0, 0, 0.55)
      box(cx, cy, cx + UI.CYL_W, cy + 1, 0, 0, 0, 0.45)

      -- Silos actively progressing toward their next missile get a thin
      -- white lightning bolt zigzagging up the INSIDE of the progress
      -- box, drawn last so it sits on top of everything. Redrawn with
      -- fresh jitter and gated by chance every frame so it flickers like
      -- electricity rather than animating smoothly.
--[[       if s.queued > 0 and glBeginEnd and glVertex and math.random() < 0.85 then
        local topY, botY = progY + 1, cy + UI.CYL_H - 1
        local midY1 = botY - (botY - topY) * 0.33
        local midY2 = botY - (botY - topY) * 0.66
        local midXc = cx + UI.CYL_W * 0.5
        local half = (UI.CYL_W - 2) * 0.5
        local function jx() return midXc + (math.random() - 0.5) * half * 2 end
        glLineWidth(1.2)
        glColor(1, 1, 1, 0.55 + math.random() * 0.45)
        glBeginEnd(GL.LINE_STRIP, function()
          glVertex(jx(), botY)
          glVertex(jx(), midY1)
          glVertex(jx(), midY2)
          glVertex(jx(), topY)
        end)
        glLineWidth(1)
        glColor(1, 1, 1, 1)
      end ]]

      -- Count box readout: this silo's current ready stockpile, on its
      -- own flat plate rather than a badge over the meter, per the new
      -- layout above.
      do
        local readyTxt = tostring(s.ready)
        local fs = clamp(countH - 2, 8, 20)
        glColor(1.0, 0.82, 0.30, 1.0)
        glText(readyTxt, cx + UI.CYL_W * 0.5, cy + countH * 0.5 - fs * 0.35,
               fs, "oc")
        glColor(1, 1, 1, 1)
      end

      -- Hovering any cylinder explains what the meter graphic represents.
      if inRect(mx, my, cx, cy, cx + UI.CYL_W, cy + UI.CYL_H) then
        siloHover = true
      end
    end
  end

  ------------------------------------------------------------------
  -- Bottom row: arm and target
  ------------------------------------------------------------------
  local armHot = inRect(mx, my, ax1, ay1, ax2, ay2)
  local canArm = loadedSilos > 0
  if armed > 0 then
    raisedButton(ax1, ay1, ax2, ay2, 0.85, 0.45, 0.15, armHot and 1.0 or 0.90, true)
    glColor(0.06, 0.05, 0.03, 1)
  elseif canArm then
    raisedButton(ax1, ay1, ax2, ay2, 0.20, 0.23, 0.28, armHot and 1.0 or 0.85)
    glColor(0.85, 0.89, 0.94, 1)
  else
    raisedButton(ax1, ay1, ax2, ay2, 0.13, 0.14, 0.17, 0.7)
    glColor(0.40, 0.43, 0.48, 1)
  end
  -- Clearly visible mouse-wheel icon at the left side of ARM.
  -- Drawn from rectangles instead of a Unicode glyph so it renders
  -- consistently with BAR's available fonts.
  local wx1, wy1, wx2, wy2 = wheelRect()
  local gx1, gy1, gx2, gy2 = wheelGlowRect()
  local wheelHot = inRect(mx, my, gx1, gy1, gx2, gy2)
  local c = wheelHot and 1.0 or 0.88
  local cx, cy = (wx1 + wx2) * 0.5, (wy1 + wy2) * 0.5

  -- Fades from 1 (just spun) to 0 over WHEEL_FLASH_TIME, independent of
  -- whether the cursor is still over the icon.
  local spinFlash = 0
  if wheelSpinTimer then
    local dt = spDiffTimers(spGetTimer(), wheelSpinTimer)
    if dt < WHEEL_FLASH_TIME then
      spinFlash = 1 - (dt / WHEEL_FLASH_TIME)
    else
      wheelSpinTimer = nil
    end
  end

  -- Soft gold glow behind the icon -- present (dim) on hover, and
  -- punched up brighter for the moment right after a scroll. A few
  -- widening, fading layers read as a glow far better than a single
  -- translucent box, which just looks like a flat highlight square.
  if wheelHot or spinFlash > 0 then
    local boost = 1 + spinFlash * 0.8
    local glowHalf = { 13, 10, 7 }
    local glowA    = { 0.10, 0.18, 0.26 }
    for i = 1, #glowHalf do
      local hw = glowHalf[i] * (1 + spinFlash * 0.35)
      local a = clamp(glowA[i] * boost, 0, 0.85)
      box(cx - hw, cy - hw, cx + hw, cy + hw, 1.0, 0.80, 0.20, a)
    end
  end

  -- Small recessed icon tile.
  box(wx1, wy1, wx2, wy2, 0.06, 0.07, 0.09, 0.90)
  box(wx1 + 1, wy1 + 1, wx2 - 1, wy2 - 1, 0.18, 0.20, 0.23, c)

  -- Icon colour shifts toward bright gold when hot, and further toward
  -- white-hot gold during the post-spin flash, rather than just going
  -- more opaque -- so the glow reads as coming FROM the icon.
  local ir, ig, ib = 0.82, 0.85, 0.90
  if wheelHot then ir, ig, ib = 1.0, 0.82, 0.25 end
  if spinFlash > 0 then
    ir = ir + (1.0 - ir) * spinFlash
    ig = ig + (0.95 - ig) * spinFlash
    ib = ib + (0.55 - ib) * spinFlash
  end

  -- Eight-spoke wheel, deliberately large enough to be recognizable.
  -- Outer wheel / rim (octagonal approximation).
  box(wx1 + 7, wy1 + 2,  wx1 + 15, wy1 + 4,  ir, ig, ib, c)
  box(wx1 + 4, wy1 + 4,  wx1 + 18, wy1 + 6,  ir, ig, ib, c)
  box(wx1 + 2, wy1 + 7,  wx1 + 20, wy1 + 15, ir, ig, ib, c)
  box(wx1 + 4, wy1 + 16, wx1 + 18, wy1 + 18, ir, ig, ib, c)
  box(wx1 + 7, wy1 + 18, wx1 + 15, wy1 + 20, ir, ig, ib, c)

  -- Hollow the middle back out.
  box(wx1 + 7, wy1 + 7, wx1 + 15, wy1 + 15, 0.12, 0.13, 0.15, 1)

  -- Four clear spokes.
  box(wx1 + 10, wy1 + 5, wx1 + 12, wy1 + 17, ir, ig, ib, c)
  box(wx1 + 5, wy1 + 10, wx1 + 17, wy1 + 12, ir, ig, ib, c)

  -- Centre hub.
  box(wx1 + 9, wy1 + 9, wx1 + 13, wy1 + 13, 0.12, 0.13, 0.15, 1)
  box(wx1 + 10, wy1 + 10, wx1 + 12, wy1 + 12, 0.90, 0.92, 0.96, c)

  -- Lightning sparks: a handful of jagged gold bolts kicked outward
  -- from the hub the instant the wheel is scrolled, fading with
  -- spinFlash. Each bolt flickers on/off per frame (math.random gate)
  -- rather than animating smoothly, since real sparks read as sudden
  -- and electric, not as something easing in and out.
  if spinFlash > 0 and glBeginEnd and glVertex then
    glLineWidth(1.6)
    local baseAngles = { 20, 100, 160, 230, 290, 340 }
    for i = 1, #baseAngles do
      if math.random() < (0.35 + spinFlash * 0.55) then
        local ang    = math.rad(baseAngles[i] + (math.random() - 0.5) * 26)
        local perp   = ang + math.pi * 0.5
        local innerR = 9
        local outerR = 14 + math.random() * (7 + spinFlash * 6)
        local midR   = (innerR + outerR) * 0.5
        local jog    = (math.random() - 0.5) * 7
        local x1p, y1p = cx + math.cos(ang) * innerR, cy + math.sin(ang) * innerR
        local xm,  ym  = cx + math.cos(ang) * midR + math.cos(perp) * jog,
                          cy + math.sin(ang) * midR + math.sin(perp) * jog
        local x2p, y2p = cx + math.cos(ang) * outerR, cy + math.sin(ang) * outerR
        local flicker = 0.6 + math.random() * 0.4
        glColor(1.0, 0.92, 0.55, spinFlash * flicker)
        glBeginEnd(GL.LINE_STRIP, function()
          glVertex(x1p, y1p)
          glVertex(xm, ym)
          glVertex(x2p, y2p)
        end)
      end
    end
    glLineWidth(1)
    glColor(1, 1, 1, 1)
  end

  -- "ARMED" and its count are drawn as two separate pieces (rather than
  -- one string) so the count itself can run at a bigger font -- the
  -- number is the thing you actually glance at, the word "ARMED" is
  -- just context. Widths are measured so the pair still lands centered
  -- as a unit at the same spot the single combined label used to sit.
  local armCenterX = (ax1 + ax2) * 0.5 - 14
  local armLabelY  = ay1 + UI.ROW * 0.32
  if armed > 0 then
    local prefix  = "ARMED "
    local numTxt  = tostring(armed)
    local numFont = UI.FONT + 4
    local prefixW = glGetTextWidth(prefix) * UI.FONT
    local numW    = glGetTextWidth(numTxt) * numFont
    local startX  = armCenterX - (prefixW + numW) * 0.5
    glText(prefix, startX, armLabelY, UI.FONT, "o")
    glText(numTxt, startX + prefixW, armLabelY - 2, numFont, "o")
  else
    glText("ARM", armCenterX, armLabelY, UI.FONT, "oc")
  end

  local tgtHot = inRect(mx, my, tx1, ty1, tx2, ty2)

  -- 0..1 sine pulse, running continuously off the fixed armGlowClock
  -- epoch (rather than a timer restarted each trigger) so the flash is
  -- steady regardless of when it started.
  local retargetPulse = 0
  if needsRetarget and armed > 0 then
    local t = spDiffTimers(spGetTimer(), armGlowClock)
    retargetPulse = 0.5 + 0.5 * math.sin(t * RETARGET_FLASH_HZ * 2 * math.pi)
  end

  if retargetPulse > 0 then
    -- Soft amber halo behind the button, drawn before raisedButton so
    -- the button itself stays crisp on top of it.
    local gp = 2 + retargetPulse * 4
    box(tx1 - gp, ty1 - gp, tx2 + gp, ty2 + gp,
        1.0, 0.75, 0.15, 0.15 + 0.35 * retargetPulse)
  end

  if armed > 0 then
    if retargetPulse > 0 then
      -- Flash between the normal armed-red and a hot amber warning --
      -- the arm count just changed, so the standing target no longer
      -- covers exactly what's armed.
      local fr = 0.85 + (1.00 - 0.85) * retargetPulse
      local fg = 0.20 + (0.75 - 0.20) * retargetPulse
      local fb = 0.20 + (0.10 - 0.20) * retargetPulse
      raisedButton(tx1, ty1, tx2, ty2, fr, fg, fb, tgtHot and 1.0 or 0.92)
    else
      raisedButton(tx1, ty1, tx2, ty2, 0.85, 0.20, 0.20, tgtHot and 1.0 or 0.90)
    end
    glColor(1, 0.95, 0.92, 1)
  else
    raisedButton(tx1, ty1, tx2, ty2, 0.13, 0.14, 0.17, 0.7)
    glColor(0.40, 0.43, 0.48, 1)
  end
  -- Labels sit left of centre so the mini buttons don't crowd them.
  glText("TARGET", (tx1 + tx2) * 0.5 - 18, ty1 + UI.ROW * 0.32, UI.FONT, "oc")

  ------------------------------------------------------------------
  -- Mini buttons, nested in the corners of their hosts
  ------------------------------------------------------------------
  local rx1, ry1, rx2, ry2, bx1, by1, bx2, by2 = miniRects()
  local repHot  = inRect(mx, my, rx1, ry1, rx2, ry2)
  local abortHot = inRect(mx, my, bx1, by1, bx2, by2)

  -- Pressed-in when active, so the toggle state is legible from the
  -- shape as well as the colour.
  if repeatOn then
    raisedButton(rx1, ry1, rx2, ry2, 0.30, 0.66, 0.90, repHot and 1.0 or 0.95, true)
    glColor(0.02, 0.05, 0.08, 1)
  else
    raisedButton(rx1, ry1, rx2, ry2, 0.10, 0.11, 0.14, repHot and 0.95 or 0.75)
    glColor(0.60, 0.65, 0.73, 1)
  end
  glText("RPT", (rx1 + rx2) * 0.5, ry1 + 3, UI.SMALL - 1, "oc")

  if armed > 0 then
    raisedButton(bx1, by1, bx2, by2, 0.55, 0.12, 0.12, abortHot and 1.0 or 0.92)
    glColor(1, 0.90, 0.88, 1)
  else
    raisedButton(bx1, by1, bx2, by2, 0.10, 0.11, 0.14, abortHot and 0.95 or 0.75)
    glColor(0.60, 0.65, 0.73, 1)
  end
  glText("ABORT", (bx1 + bx2) * 0.5, by1 + 3, UI.SMALL - 1, "oc")

  ------------------------------------------------------------------
  -- Hover help
  ------------------------------------------------------------------
  local s1x1, s1y1, s1x2, s1y2,
        s2x1, s2y1, s2x2, s2y2,
        s3x1, s3y1, s3x2, s3y2 = statRects()
  local salvoHot = inRect(mx, my, s1x1, s1y1, s1x2, s1y2)
  local stockHot = inRect(mx, my, s2x1, s2y1, s2x2, s2y2)
  local siloHot  = inRect(mx, my, s3x1, s3y1, s3x2, s3y2)
  local tx1, ty1, tx2, ty2 = wheelRect()  -- small icon only
  local wheelHot = inRect(mx, my, tx1, ty1, tx2, ty2)

  if armHot or tgtHot or repHot or abortHot
     or salvoHot or stockHot or siloHot or siloHover or wheelHot then
    local tip
    if wheelHot then
      tip = "mouse wheel: scroll down to arm more  ·  scroll up to arm less"
    elseif siloHover then
      tip = "shows all silos, their loading progress, and missiles ready (bottom plate)"
    elseif salvoHot then
      tip = "missiles you can launch at once  ·  one per loaded silo"
    elseif stockHot then
      tip = "total missiles across every silo"
    elseif siloHot then
      tip = "silos built  ·  each bar below is one silo's next missile"
    elseif repHot then
      tip = "repeat: keep firing at the same targets as missiles finish"
    elseif abortHot then
      tip = "abort: cancel every queued launch and disarm"
    elseif armHot then
      tip = canArm
        and ("click to arm  ·  right-click to abort  ·  max " .. loadedSilos
             .. " this salvo (one per loaded silo)")
        or  "no silo has a missile ready"
    elseif needsRetarget and armed > 0 then
      tip = "arm count changed -- click TARGET to re-acquire for " .. armed
    else
      tip = (armed > 0)
        and "attack cursor  ·  right-drag to spread targets"
        or  "arm at least one missile first"
    end
    local w = glGetTextWidth(tip) * UI.SMALL + 10
    box(x1, y2 + 3, x1 + w, y2 + UI.SMALL + 9, 0.05, 0.06, 0.08, 0.92)
    glColor(0.75, 0.79, 0.86, 1)
    glText(tip, x1 + 5, y2 + 7, UI.SMALL, "o")
  end

  glColor(1, 1, 1, 1)
end

--------------------------------------------------------------------
-- Input
--------------------------------------------------------------------
function widget:MousePress(mx, my, button)
  if #silos == 0 and totalQueued == 0 then return false end
  local x1, y1, x2, y2 = panelRect()
  if not inRect(mx, my, x1, y1, x2, y2) then return false end

  local ax1, ay1, ax2, ay2, tx1, ty1, tx2, ty2 = buttonRects()

  -- Mini buttons FIRST: they sit inside the big ones, so testing the
  -- hosts first would swallow every click aimed at them.
  local rx1, ry1, rx2, ry2, bx1, by1, bx2, by2 = miniRects()
  if inRect(mx, my, rx1, ry1, rx2, ry2) then
    if button == 1 then toggleRepeat() end
    return true
  end
  if inRect(mx, my, bx1, by1, bx2, by2) then
    if button == 1 then abortAll() end
    return true
  end

  if inRect(mx, my, ax1, ay1, ax2, ay2) then
    if button == 1 then
      armMore(1)
    elseif button == 3 then
      -- Right-click clears rather than decrementing: overshooting by
      -- one click is common, and starting again is quicker than
      -- counting back down. Now exactly Abort (a real Stop order to
      -- every silo, same as pressing G) rather than just dropping the
      -- panel's own count -- otherwise a queued/half-fired volley kept
      -- running even after the panel looked cleared.
      abortAll()
    end
    return true
  end

  if inRect(mx, my, tx1, ty1, tx2, ty2) then
    if button == 1 then engage() end
    return true
  end



  -- Anywhere else on the panel drags it.
  if button == 1 then
    UI.drag = true
    UI.dragDX, UI.dragDY = mx - x1, my - y1
    UI.x, UI.y = x1, y1
    return true
  end
  return false
end

function widget:MouseWheel(up, value)
  if #silos == 0 and totalQueued == 0 then return false end

  -- MouseWheel gives us no coordinates, so check the current mouse position.
  -- This keeps wheel control exclusive to the small icon inside ARM.
  local mx, my = spGetMouseState()
  local hx1, hy1, hx2, hy2 = wheelHitRect()
  if not inRect(mx, my, hx1, hy1, hx2, hy2) then
    return false
  end

  local step = math.max(1, math.floor(tonumber(value) or 1))

  -- BAR reports wheel-up as true. Scrolling down/toward yourself arms more.
  -- (armMore() itself now flags needsRetarget on any actual change, so
  -- there's nothing else to do here.)
  if up then
    armMore(-step)
  else
    armMore(step)
  end
  wheelSpinTimer = spGetTimer()

  return true
end

function widget:MouseMove(mx, my)
  if not UI.drag then return false end
  local vsx, vsy = spGetViewGeometry()
  local _, _, x2, y2 = panelRect()
  local w, h = UI.W, y2 - (UI.y or 0)
  UI.x = clamp(mx - UI.dragDX, 0, (vsx or 1920) - w)
  UI.y = clamp(my - UI.dragDY, 0, (vsy or 1080) - h)
  return true
end

function widget:MouseRelease()
  UI.drag = false
  return -1
end

function widget:IsAbove(mx, my)
  if #silos == 0 and totalQueued == 0 then return false end
  local x1, y1, x2, y2 = panelRect()
  return inRect(mx, my, x1, y1, x2, y2)
end

--------------------------------------------------------------------
-- Remember the player's nuke target so Repeat can hand it to replacement
-- silos even after the original silo has gone dry and its command queue has
-- changed.
--------------------------------------------------------------------
function widget:CommandNotify(cmdID, params, options)
  if cmdID == CMD.ATTACK and #armedIDList > 0 and params then
    -- Capture the target regardless of the cached RPT display state. The
    -- actual silo repeat state is checked by rotateCooldownSilos(). This makes
    -- hand-offs work even when the widget was reloaded while Repeat was on.
    local actualRepeat = readActualRepeatState()
    if not actualRepeat then return false end
    lastRepeatTarget = {}
    for i = 1, #params do
      lastRepeatTarget[i] = params[i]
    end
    needsRetarget = false
  end
  return false
end

--------------------------------------------------------------------
-- Upkeep
--------------------------------------------------------------------
function widget:GameFrame(frame)
  if frame - lastScan >= SCAN_INTERVAL then
    lastScan = frame
    rescan()
  end
  if frame - lastRotateCheck >= ROTATE_INTERVAL then
    lastRotateCheck = frame
    rotateCooldownSilos()
  end
end

function widget:PlayerChanged()
  myTeamID = spGetMyTeamID()
  armed = 0
  armedIDList = {}
  lastRepeatTarget = nil
  rescan()
end

function widget:Initialize()
  if Spring.GetSpectatingState and Spring.GetSpectatingState() then
    -- Nothing to manage as a spectator.
    widgetHandler:RemoveWidget()
    return
  end
  myTeamID = spGetMyTeamID()
  rescan()
end

function widget:GetConfigData()
  return { x = UI.x, y = UI.y }
end

function widget:SetConfigData(data)
  if type(data) ~= "table" then return end
  local vsx, vsy = spGetViewGeometry()
  local h = UI.ROW + UI.STAT_ROW + UI.PAD * 3
  -- Clamped on load: a position saved on a wider monitor must not
  -- strand the panel off-screen.
  if type(data.x) == "number" then
    UI.x = clamp(data.x, 0, (vsx or 1920) - UI.W)
  end
  if type(data.y) == "number" then
    UI.y = clamp(data.y, 0, (vsy or 1080) - h)
  end
end
