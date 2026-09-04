-- Bumped every time this file is edited and pushed, echoed on load (see
-- widget:Initialize). Added 2026-09-02 specifically because it became hard
-- to tell, purely from a console log, whether a given test was actually
-- running the latest fix or a stale copy left over from before a reload --
-- this removes that ambiguity going forward: every future log's very first
-- line says exactly which build produced the rest of it.
local WIDGET_BUILD = "2026-09-03zz6"

function widget:GetInfo()
    return {
        name    = "Cone-of-Fire",
        desc    = "T1/T2 static defense structures with a 1000+ range plasma or laser weapon (see ARC_UNIT_NAMES) can be locked to a player-defined cone-of-fire + range cap so Fire-at-Will or Return Fire never targets outside your chosen safe zone -- prevents splash-damage friendly fire into your own base.",
        author  = "Armis71 + Claude",
        date    = "2026-09-02",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true,
    }
end

--------------------------------------------------------------------------------
-- CONTROLS -- everything you can actually DO with this widget, in one place.
--------------------------------------------------------------------------------
-- Ctrl+C (or the "Cone-of-Fire" command-panel button) on a selected unit
--   from ARC_UNIT_NAMES below (build zz: every T1/T2 STATIC defense
--   structure with a plasma- or laser-type weapon of range 1000+, not just
--   Ragnarok/Calamity/Starfall any more -- deliberately excludes ships/
--   vehicles/bots/aircraft, since the cone's fixed world-space angle only
--   stays meaningful on something that doesn't move after setup) -- draw a
--   new cone: scroll
--   wheel to widen/narrow, left-click to lock the angle, move the mouse to
--   set the range, left-click again to activate. Select MULTIPLE at once
--   before pressing Ctrl+C to link them into a SHARED cone/range -- every
--   unit ends up covering the exact same zone, each angled correctly for
--   its own position.
-- Right-click during the RANGE step -- back up to the CONE (angle) step to
--   re-adjust it, instead of cancelling. Right-click again from there (or
--   Escape twice, any time) -- cancel setup entirely.
-- The small "X" under a deployed unit -- remove its cone-of-fire config
--   permanently (same as "Remove Permanently" on the command panel).
-- Ctrl+Click any "X" -- clear EVERY cone-of-fire config currently visible
--   on screen at once, not just that one unit.
-- Ctrl+Click directly on an already-configured unit's own model -- toggle
--   just that unit's cone illustration (the wedge/line/degree labels) on
--   or off, without touching its actual enforcement. Ctrl+Click it again
--   to bring the illustration back.
-- /conefirehide -- every unit's cone illustration automatically hides
--   itself the instant that unit starts actively engaging a target, and
--   reappears the instant it goes idle again -- keeps the screen clean
--   during an actual fight. Purely visual; never affects enforcement.
-- /conefireon -- the default: cone illustrations are always shown.
-- /conefiredisable -- removes cone-of-fire from EVERY unit in the game at
--   once (not just what's on screen) -- the same as clicking every "X" in
--   one go.
-- /conefirewedge -- toggles the red aim-sweep wedge (below) on/off for
--   every unit at once. On by default.
-- /conefiredefault -- resets /conefirehide-vs-on and /conefirewedge back
--   to their original defaults in one command.
-- (/conefirehide-vs-on and /conefirewedge are now saved across sessions --
--   they'll stay as you last set them next time you load into a game.)
-- The small "?" next to "X" -- opens an in-game panel listing every
--   control above, so none of this needs to be looked up in the .lua file.
--   Close it again with any "?", or the "X" in the panel's own upper-right
--   corner (works even if the unit that opened it no longer has cone-of-
--   fire active at all).
-- A small red wedge (two converging lines) -- while actively engaging,
--   shows the gap between where the turret is still turning FROM and the
--   target it's turning TOWARD, shrinking as it catches up and vanishing
--   once it's fully aimed (an approximation -- see the notes.md build-zs
--   entry for why the engine won't give an exact live turret angle).
--------------------------------------------------------------------------------
-- USER-TWEAKABLE SETTINGS -- read this first if you just want to change how
-- the widget behaves, not how it works.
--------------------------------------------------------------------------------
-- HOW TO TWEAK: every value below is a plain number (or a small list of unit
-- names). Change the number, save the file, then reload the widget in-game
-- so it picks up the new value -- open the widget list (the gear/puzzle-
-- piece icon, or its usual hotkey) and toggle "Cone-of-Fire" off then back
-- on, or just leave/rejoin the game. You do NOT need to understand the rest
-- of this file to change anything in this block; nothing here can break the
-- widget syntactically as long as you only change the number/true/false to
-- its right, not the punctuation around it. If in doubt, change one value
-- at a time and retest -- that also makes it obvious which change did what.

-- Which units this widget applies to -- add or remove a line to change
-- which units get the cone-of-fire command. The name on the left is the
-- unit's internal def name (not its display name); `= true` means
-- "included." To add a unit, copy a line and change the name (removing a
-- unit is just deleting its line, or flipping it to `= false`).
--
-- build zz, per the user ("All T1/T2 units that has a range of 1000+ and
-- fires plasma or laser"): originally just the three T2 "LRPC" (long-range
-- plasma cannon) static defense towers and their Scavenger-faction "Mini"
-- equivalents. Expanded by writing a one-off Lua script (scan_units.lua,
-- not part of this widget) that loads every unit def under bar-repo/units/
-- and checks: (1) tech level 1 or 2 -- customparams.techlevel, with the
-- BAR convention that a T1 unit usually omits this field entirely (nil ==
-- T1, confirmed by checking known T1 units like armguard/corpun, which
-- have no techlevel field at all, against known T2/T3/T4 units, which
-- always set one explicitly); (2) has at least one weapon of type "Cannon"
-- (BAR's in-game term for these is "plasma cannon", e.g. armvulc's own
-- weapon is literally named "Rapid-fire long-range plasma cannon" in its
-- weapondef) or "BeamLaser"/"LaserCannon" ("laser"); (3) THAT SPECIFIC
-- weapon's own range is >= 1000 elmos -- deliberately NOT the unit's
-- overall max range across every weapon, since several matches (nuke/
-- anti-nuke silos, ships carrying both a gun and a missile/torpedo
-- launcher) pair a short-range Cannon with a much longer-range
-- StarburstLauncher/MissileLauncher/TorpedoLauncher, which must not count
-- toward the threshold.
--
-- build zz1, per the user ("you included the ships. probably not great
-- since ships move?") -- correct, and it's not ships-specific: cfg.angle
-- is a fixed WORLD-SPACE bearing, locked in at setup time and never
-- rotated afterward (see ShouldShowConeGui/EnforceArcOnUnit -- the cone is
-- redrawn every frame at the unit's CURRENT position, but always pointed
-- the same absolute direction). That's exactly right for a building, which
-- never moves, so the cone always covers the same real patch of map -- the
-- entire point, per this widget's own description, is protecting a fixed
-- area (your base) from friendly fire. For anything that MOVES after
-- setup -- a ship, tank, bot, or aircraft -- the cone's real-world coverage
-- drifts along with it and can end up pointed somewhere that no longer
-- matches player intent, or even stop covering the base entirely. So the
-- scan-matched ships/vehicles/bots/seaplanes (19 of the original 44 zz
-- matches) were removed again here, leaving only the 25 units that are
-- actual static defense structures (buildings, never move) -- the
-- category this widget's cone-locking design is actually correct for.
-- The removed ones, for reference, were: armdronecarry, armepoch,
-- armmship, armtrident (Armada ships); corblackhy, cordronecarry,
-- cormship, corprince, corsentinel (Cortex ships), cortrem (Cortex tank);
-- legadvaabot (Legion bot), leginf, legvcarry, legmed (Legion vehicles),
-- legspcarrier (Legion seaplane), leganavyantinukecarrier,
-- leganavyartyship, leganavyflagship, leganavymissileship (Legion ships).
--
-- Excluded on purpose (still applies): Raptors (units/other/raptors/*,
-- always AI-only, a player can never select/command one to put a cone-of-
-- fire on it), the Scavenger Boss encounter unit and commander-evolution
-- skins (both throw Lua errors when loaded standalone -- they pull in
-- engine globals like Spring/VFS that only exist at actual runtime -- and
-- neither is a normal player-buildable unit anyway), and MissileLauncher/
-- StarburstLauncher/TorpedoLauncher/AircraftBomb/Flame/DGun/Melee/Shield/
-- LightningCannon weapon types (guided munitions, bombs, melee, etc. --
-- not "plasma or laser" as asked).
--
-- build zz3: real in-game display names filled in, per the user ("armamb
-- is not ambusher it's a rattlesnake / armguard is Gauntlet -- use this as
-- reference"), from the official beyondallreason.info defense-buildings
-- pages for each faction (armada-defense-buildings, cortex-defense-
-- buildings, legion-defense-buildings) rather than guessed from memory --
-- the two guesses the user caught (armamb "Ambusher", armguard "Guardian")
-- were both wrong, and cross-checking the rest against those pages turned
-- up two more of my own earlier guesses that were also wrong (armanni
-- "Annihilator" -> actually Pulsar; armbrtha "Big Bertha" -> actually
-- Basilica, though "Big Bertha" is a common legacy/community nickname).
-- The four Scavenger-faction units (armminivulc/corminibuzz/
-- legministarfall/armbotrail) aren't on those three pages -- they're a
-- separate PvE-only faction -- so they keep their prior generic
-- description rather than a guessed name.
local ARC_UNIT_NAMES = {
    -- Armada
    armvulc                 = true, -- Ragnarok (T2 static defense "LRPC" tower), Cannon range 5750
    armminivulc             = true, -- Mini Ragnarok (Scavengers T2 static defense tower), Cannon range 1300
    armamb                  = true, -- Rattlesnake (Armada T2 static defense tower), Cannon range 1380
    armanni                 = true, -- Pulsar (Armada T2 static defense tower), BeamLaser range 1400
    armbrtha                = true, -- Basilica (Armada T2 static defense "LRPC" tower), Cannon range 4650
    armguard                = true, -- Gauntlet (Armada T1 static defense tower), Cannon range 1220
    armbotrail              = true, -- Scavengers T2 static defense tower, Cannon range 5250

    -- Cortex
    corbuzz                 = true, -- Calamity (T2 static defense "LRPC" tower), Cannon range 6100
    corminibuzz             = true, -- Mini Calamity (Scavengers T2 static defense tower), Cannon range 1450
    corbhmth                = true, -- Cerberus (Cortex T2 static defense tower), Cannon range 1650
    corint                  = true, -- Basilisk (Cortex T2 static defense "LRPC" tower), Cannon range 4950
    corpun                  = true, -- Agitator (Cortex T1 static defense tower), Cannon range 1245
    cortoast                = true, -- Persecutor (Cortex T2 static defense tower), Cannon range 1390

    -- Legion
    legstarfall              = true, -- Starfall (T2 static defense "LRPC" tower), Cannon range 6100
    legministarfall          = true, -- Mini Starfall (Scavengers T2 static defense tower), Cannon range 1400
    legacluster               = true, -- Eviscerator (Legion T2 static defense tower), Cannon range 1380
    legbastion                = true, -- Bastion (Legion T2 static defense tower), BeamLaser range 1100
    legcluster                = true, -- Amputator (Legion T1 static defense tower), Cannon range 1000
    leghive                   = true, -- Hive (Legion T1 static defense tower), Cannon range 1100
    legfhive                  = true, -- Naval Hive (Legion T1 static defense tower), Cannon range 1100
    leglupara                 = true, -- Lupara (Legion T1 static defense tower), Cannon range 1125
    leglraa                   = true, -- Xyston (Legion T2 anti-air static defense tower), LaserCannon range 2000
    leglrpc                   = true, -- Olympus (Legion T2 static defense "LRPC" tower), Cannon range 4800
    legperdition               = true, -- Perdition (Legion T2 static defense tower), Cannon range 2300
    legrampart                 = true, -- Rampart (Legion T2 economy/defense building), Cannon range 1600
}

-- How wide the cone starts out when you begin setup on a unit, in degrees
-- of TOTAL width (the cone extends this many degrees each side of center,
-- so 90 here means 45 degrees left + 45 degrees right of where you aim).
-- You can still widen/narrow it with the mouse wheel during setup -- this
-- only sets the starting point. Must stay between the min/max below.
local DEFAULT_HALF_WIDTH_DEG = 90
-- How narrow you're allowed to make the cone with the mouse wheel, in
-- degrees of TOTAL width. Going below ~10 degrees starts to make the cone
-- fiddly to aim by hand -- lower this only if you specifically want a very
-- tight, sniper-like firing lane.
local MIN_HALF_WIDTH_DEG = 10
-- How wide you're allowed to make the cone with the mouse wheel, in degrees
-- of TOTAL width. 360 means "unrestricted" (a full circle -- effectively
-- the same as not using this widget at all, just with the fire-control
-- benefits still active). Lower this if you never want to accidentally
-- wheel all the way out to an unrestricted cone.
local MAX_HALF_WIDTH_DEG = 360
-- How many degrees of the cone's TOTAL width change per single mouse-wheel
-- notch during setup. build za briefly split this into a fine/coarse pair
-- plus an on/off switch; build zb collapsed that back down to just this
-- one variable, per the user, who'd rather set the exact step they want
-- directly. Set it to 1 for the most precise control, 2 for a slightly
-- faster feel, 15 or 30 for coarse/rough adjustment -- any whole number
-- from 1 to 30 is intended to work well; it's clamped to that range below
-- (in the "compiled" section) just so an accidental 0 or a huge number
-- can't produce a broken/unusable wheel step. Default is 10 (build zg,
-- back to the original pre-build-za feel, per the user).
local WHEEL_STEP_DEG = 10
-- The smallest range cap you're allowed to set, in elmos (the game's world-
-- distance unit -- for reference, armvulc's own weapon range is 5750
-- elmos). Exists purely so the range can't be accidentally shrunk to
-- ~0 and stop the unit from ever engaging anything. Lower this if you
-- specifically want to allow a very short-range cone.
local MIN_RANGE_CAP = 300
-- How long (real seconds) you have between two presses of Escape for the
-- second one to count as "cancel setup," rather than being treated as two
-- separate, unrelated presses. Raise this if double-tapping Escape to
-- cancel feels like it isn't registering; lower it if a single accidental
-- extra tap is cancelling setup when you didn't mean it to.
local ESCAPE_DOUBLE_TAP_WINDOW = 0.6
-- How long (real seconds) the camera takes to pan/zoom out when you enter
-- cone-of-fire setup on a unit. Raise for a slower, smoother transition;
-- lower (or set to a very small number) for a near-instant snap.
local ZOOM_OUT_TRANSITION_TIME = 1.2
-- build zz4, per the user ("put all the unit ranges in to categories say
-- any unit over 3000 range zoom all the way out, smaller ranges like 1000
-- the zoom shouldn't be all the way out"): how far the camera zooms out on
-- entering setup (see ZoomOutForSetup), tiered by the unit's own native
-- weapon range instead of always zooming all the way out regardless of
-- range (the old behavior -- fine for a 6000-range Ragnarok, way too far
-- for a 1000-range Gauntlet, whose whole cone then shrinks to a speck in
-- the middle of the screen). Ordered ascending by `maxRange`; the first
-- tier whose `maxRange` the unit's own range is <= wins. `dist` is a
-- Spring/BAR camera-state "dist" value (same field ZoomOutForSetup always
-- used before) -- ZOOM_OUT_HUGE_DIST is the same deliberately-absurd
-- value as before (engine-clamped to the real max zoom every frame, see
-- its own comment) for the top tier; the smaller tiers are a first-pass
-- guess at a comfortable "whole cone visible without zooming out past it"
-- distance and are the ones most worth tuning by eye in-game -- raise a
-- tier's `dist` if that range of units still looks too zoomed-in, lower
-- it if the cone looks lost/tiny on screen.
local ZOOM_OUT_RANGE_TIERS = {
    { maxRange = 1500, dist = 3500 },            -- short range (~1000-1500, e.g. Gauntlet/Hive/Lupara/Pulsar) -- build zz5: was 2200, per the user ("2200 for it and its equivalent is too low ... maybe 3500 zoom level for anything with a 1400")
    { maxRange = 3000, dist = 4500 },            -- medium range (~1500-3000, e.g. Xyston/Perdition)
    { maxRange = math.huge, dist = nil },        -- long range (3000+, e.g. Ragnarok/Basilica/Olympus) -- dist filled in below, once ZOOM_OUT_HUGE_DIST exists
}
-- How long (sim frames, ~30 per real second at NORMAL 1x game speed -- at
-- a faster game speed the same number of frames passes in less real time,
-- and vice versa at slower speeds) this widget keeps attacking the last
-- position it personally confirmed an enemy at, once that enemy drops out
-- of both line-of-sight and radar. This is the delay between "target goes
-- out of sight" and the unit actually going quiet -- during this whole
-- window the unit keeps firing at that last-known spot each time it
-- reloads, which may be wasted shots if the target has actually moved on
-- or died. Raise this if targets that duck behind cover briefly (a hill, a
-- cloak, a radar gap) are being given up on too early; lower it (or set it
-- to 0 to disable this fallback entirely) if you'd rather the unit stop
-- firing the instant it loses sight of something, even at the cost of
-- sometimes giving up on a target that would have reappeared a moment
-- later. 450 = ~15 real seconds at 1x game speed.
local GHOST_MEMORY_FRAMES = 450
-- How often (sim frames, same ~30/real-second-at-1x-speed caveat as above)
-- this widget re-sends its current order even when nothing has changed, as
-- a safety net in case a single order silently failed to land. Purely
-- defensive -- shouldn't normally matter. Lower it if you suspect orders
-- are occasionally getting dropped and want faster recovery; there's
-- little reason to raise it.
local ATTACK_REFRESH_FRAMES = 150
-- How often (sim frames, same caveat) this widget prints its throttled
-- status/diagnostic lines to the console while actively enforcing a cone.
-- Lower this for more frequent (noisier) logging when troubleshooting;
-- raise it to quiet the console down during normal play. Doesn't affect
-- behavior at all, only how chatty the console log is.
local STOP_ECHO_THROTTLE_FRAMES = 30
-- Where the small yellow cone-cursor icon (the "<" shape shown near your
-- mouse while you're aiming a cone) is drawn relative to your actual mouse
-- pointer, in screen pixels. X is right-positive, Y is UP-positive (screen
-- coordinates grow upward in this game's UI, so a bigger negative Y value
-- pushes the icon further DOWN). Raise CONE_ICON_OFFSET_X and/or make
-- CONE_ICON_OFFSET_Y more negative if the icon still overlaps your system
-- cursor; move them the other way to tuck it in closer.
local CONE_ICON_OFFSET_X = 20
local CONE_ICON_OFFSET_Y = -22
-- Size of the cone-cursor icon, in screen pixels: CONE_ICON_LEN is how far
-- it extends from its point (the apex, at the offset above) out to its
-- open end; CONE_ICON_HALF is how far that open end spreads above/below
-- the centerline. Bigger numbers = a bigger icon.
local CONE_ICON_LEN = 16
local CONE_ICON_HALF = 14
-- How long (real seconds) the icon's yellow fill takes to grow from the
-- point (empty) out to the full wedge (completely filled) before snapping
-- back to empty and starting over. Lower = a faster, more urgent-looking
-- fill; higher = a slower, calmer one.
local CONE_ICON_PULSE_SECONDS = 2.5
-- build zh: how many screen pixels ABOVE your actual mouse pointer (not
-- the cone-cursor icon, which sits off to the side per CONE_ICON_OFFSET_X/
-- Y above) the small "Cone"/"Range" mode-name label is drawn -- a quick
-- reminder of which of the two setup stages you're currently in, right
-- where you're actually looking. Raise this if it feels too close to the
-- cursor; lower it to tuck it in closer.
local CURSOR_MODE_LABEL_OFFSET_Y = 30
-- build zs: how fast (degrees per real second) this widget ASSUMES a
-- turret can rotate, for the red "still turning to face its target" sweep
-- (see simulatedAimAngle above for why this has to be an assumption
-- rather than real data). Raise this if the red sweep visibly lags behind
-- how fast the turret actually looks like it's turning in-game; lower it
-- if the sweep closes/disappears faster than the turret actually finishes
-- turning.
-- build zu: user reported 90 was visibly much faster than a deployed
-- Ragnarok's real turret slew -- dropped to 28 (a full 180-degree swing
-- takes ~6.4s) as a closer empirical match.
-- build zv: user reported the wedge was STILL visibly faster than the
-- real turret even at 28. Two things changed this build: (1) the early
-- snap-to-done used to be triggered by the engine's `angleGood` flag,
-- which turned out (per source review, see simulatedAimAngle's own
-- declaration above) to go true well before the turret model actually
-- finishes turning for many turreted weapons -- that's now replaced with
-- HasWeaponJustFired, a real fire-event detector, so the wedge can no
-- longer close early just because angleGood lied; (2) the rate itself is
-- also dropped further, from 28 to 15 (a 180-degree swing now takes 12s),
-- as extra margin on top of that fix. Still a guess -- there's no engine
-- API for real turret slew speed -- keep tuning if it's still off in
-- either direction.
local AIM_SWEEP_TURN_RATE_DEG_PER_SEC = 15
-- build zu: user reported the old fixed 350-elmo sweep was much shorter
-- than the cone itself and even shorter than where the "N deg (cone
-- center)" label sits, making it look broken/undersized. The sweep radius
-- is now computed per-unit from cfg.rangeCap at the draw call site (see
-- DrawAimSweep call below) so it reaches the same distance as the green
-- wedge/orange center line. This constant is kept only as the fallback
-- used if rangeCap is ever missing/invalid.
local AIM_SWEEP_RADIUS = 350

-- --- end of user-tweakable settings -- everything below this point is ---
-- --- implementation detail, not meant to be edited casually.          ---
local DEFAULT_HALF_WIDTH = math.rad(DEFAULT_HALF_WIDTH_DEG / 2)
local MIN_HALF_WIDTH     = math.rad(MIN_HALF_WIDTH_DEG / 2)
local MAX_HALF_WIDTH     = math.rad(MAX_HALF_WIDTH_DEG / 2)
-- WHEEL_STEP_DEG (set above, in the USER-TWEAKABLE SETTINGS block) is
-- expressed in degrees of TOTAL cone width (matching how the user thinks
-- about it, and how the "N°" label describes it) -- clamped to the
-- documented 1-30 range in case it's ever set to something outside it,
-- then converted here to the HALF-width radian step that previewHalfWidth
-- actually stores and is adjusted by (dividing by 2 since TOTAL width is
-- twice the half-width).
local WHEEL_STEP = math.rad(math.max(1, math.min(30, WHEEL_STEP_DEG)) / 2)
local AIM_SWEEP_TURN_RATE_RAD_PER_SEC = math.rad(AIM_SWEEP_TURN_RATE_DEG_PER_SEC)

--------------------------------------------------------------------------------
-- DESIGN NOTES (read before touching this file)
--------------------------------------------------------------------------------
-- This widget does NOT replace or override Fire-at-Will/Hold Fire/Return Fire
-- as the player's own choice -- it GATES them: the unit is only ever allowed
-- to actually be in whatever fire state the player picked while a real
-- target sits inside the drawn cone+range; the rest of the time it's held
-- on Hold Fire regardless of the player's chosen stance, and restored the
-- instant a valid target enters the cone. The ONE exception is DeployDraft:
-- per the user, finishing setup itself switches the unit to Fire-at-Will
-- (restricted to the cone) as a one-time convenience, so it starts
-- defending immediately without a separate manual click -- everything
-- AFTER that single deploy-time action stays purely subtractive, same as
-- described above (the player can freely switch away from Fire-at-Will any
-- time and the ongoing gating never switches it back on its own).
--
-- This design went through two earlier, both-confirmed-inadequate attempts
-- this session, worth understanding so nobody re-tries them the same way:
--   1. Reissue CMD.STOP every frame a locked target is found outside the
--      cone (via Spring.GetUnitWeaponTarget). CONFIRMED IN-GAME not to
--      work: 20+ seconds of "STOP issued" once a second against an
--      unchanging locked target, unit fired the entire time. LATER
--      UNDERSTOOD WHY (2026-09-02, by reading the actual engine source,
--      rts/Sim/Units/CommandAI/CommandAI.cpp): Stop genuinely does drop the
--      current weapon target (`CCommandAI::ExecuteStop` calls
--      `weapon->DropCurrentTarget()`), it was never a no-op -- but a
--      Fire-at-Will unit's `AutoTarget()` (rts/Sim/Weapons/Weapon.cpp) runs
--      again on its very next SlowUpdate once fireState is still
--      FIRESTATE_FIREATWILL, and instantly re-locks the same target since
--      it's still the closest/only valid one under the engine's own native
--      rules. So every Stop we issued WAS working, just getting silently
--      undone one frame later, forever -- indistinguishable from "no
--      effect" at a 1-second echo throttle. Fixed properly (see below):
--      pair a single Stop with simultaneously forcing fireState below
--      FIRESTATE_FIREATWILL, so AutoTarget can't re-run to undo it.
--   2. Reissue CMD.FIRE_STATE=Hold Fire every frame instead, reactively,
--      same trigger. CONFIRMED IN-GAME to have a REAL but PARTIAL effect --
--      user's own words: "it fires and stops briefly like fire at will is
--      fighting against the hold fire, it goes back and forth... once i
--      delete the cone of fire mode, [it] starts shooting with no
--      interference so it shoots faster rate." A genuine tug-of-war: our
--      order only fires AFTER a bad lock is detected, so Fire-at-Will's own
--      targeting AI keeps getting a head start and wins often enough to
--      still get shots off.
-- Both were REACTIVE (fight an engagement that's already forming/formed).
-- The fix that's actually in place now is PREVENTIVE instead: every frame,
-- HasValidTargetInCone() runs an INDEPENDENT spatial query (Spring.
-- GetUnitsInCylinder + ally-team + bearing/distance check), OR'd with
-- `lockedInCone` (the unit's own CURRENT weapon lock, via
-- Spring.GetUnitWeaponTarget, independently bearing/range-checked against
-- the same cone -- a fallback for the spatial query's possible LOS/radar
-- blind spot in unsynced Lua, see the fix log for 2026-09-02). If NEITHER
-- says a valid target exists, fire state is held on Hold Fire continuously
-- -- not toggled against a live re-acquisition attempt, just held there
-- every frame, so there's no race left to lose: Fire-at-Will's AI never
-- gets a window to lock onto anything NEW outside the cone in the first
-- place (confirmed straight from the engine source,
-- rts/Sim/Weapons/Weapon.cpp `CWeapon::AllowWeaponAutoTarget()`:
-- `if (owner->fireState < FIRESTATE_FIREATWILL) return false;` -- that
-- function gates ALL of AutoTarget(), so holding fireState below
-- Fire-at-Will is a genuine, engine-level block on new targets, not a
-- guess). The moment either check finds a real target in the cone, fire
-- state is restored immediately and native targeting/priority/leading
-- takes over completely normally within that window.
--
-- One more piece, added 2026-09-02: the very first frame a unit transitions
-- into suppression also gets a single CMD.STOP, paired with the
-- simultaneous fireState-forcing (not reissued every frame after that --
-- see EnforceArcOnUnit for why). This exists for a target that was
-- legitimately locked while genuinely inside the cone and then drifted
-- outside it while still within the unit's native weapon range --
-- fireState alone doesn't retroactively drop an existing lock (confirmed
-- from CommandAI.cpp: CMD_FIRE_STATE just does `owner->fireState =
-- value`, nothing else), so without this the unit could otherwise keep
-- firing at that one drifted-out target indefinitely even with the gate
-- otherwise working correctly.
--
-- Reaction time / residual risk: even with gating, if a target WAS
-- legitimately inside the cone (fire state genuinely open, Fire-at-Will
-- genuinely engaged) and then steps outside it, there's still up to one
-- frame of lag before the gate closes again -- same class of caveat as
-- always, and about as good as any client-side (unsynced LuaUI) widget can
-- do; true zero-lag enforcement needs a synced gadget shipped in BAR's own
-- mod archive, which a personal widget file can't provide. Told to the user
-- as an open caveat from the start of this project.
--
-- Why this widget doesn't just clamp the turret's/weapon's physical aim
-- angle directly, instead of gating fire state (asked by the user,
-- 2026-09-02): checked directly against the engine source before
-- answering, not guessed. A weapon's firing-arc constraint (`mainDir` /
-- angle-vs-mainDir check in `CWeapon::TestTargetAngleConstraint`,
-- rts/Sim/Weapons/Weapon.cpp) is a C++ member compiled once from the
-- WeaponDef when the unit is created -- there is no per-unit-instance Lua
-- setter for it. The one Lua call that writes live weapon state,
-- Spring.SetUnitWeaponState, was checked key-by-key against its actual
-- implementation (rts/Lua/LuaSyncedCtrl.cpp, SetSingleUnitWeaponState) and
-- does not expose mainDir/arc at all -- only reload/salvo/accuracy/
-- range/avoidFlags/etc. Even if it did, that function lives in
-- LuaSyncedCtrl (SYNCED-only), meaning it could only ever be called from a
-- synced gadget shipped in BAR's mod archive, not from this personal
-- client-side widget. Given that, gating fireState is the closest
-- equivalent actually reachable from Lua here: since AutoTarget() itself is
-- hard-gated on fireState at the engine level (see above), holding it below
-- Fire-at-Will is functionally "the turret doesn't turn to acquire anything
-- new outside the cone" -- just implemented through fire-state rather than
-- a direct angle clamp, because there's no angle-clamp lever this widget
-- can reach.
--
-- THE NEXT MYSTERY (2026-09-02, build h -> i): a fresh log with the
-- Suppressing diagnostic confirmed working (build h's hasAnyLock fix is
-- real -- "Suppressing unit..." now DOES fire during genuine out-of-cone
-- lock stretches) revealed something worse: across a full 56-SECOND
-- continuous suppression episode, "firestate readback" stayed at 2
-- (Fire-at-Will) and "still has a weapon target" stayed true THE ENTIRE
-- TIME, despite `Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE,
-- {FIRESTATE_HOLDFIRE}, {})` being sent every single frame throughout. That
-- means our own core enforcement lever was having ZERO measurable effect,
-- not "landing but getting raced" -- and since the widget never checked
-- GiveOrderToUnit's return value, it had no way to know.
--
-- Traced this by reading the actual engine call path this widget uses
-- (confirmed from source, rts/Lua/LuaUnsyncedCtrl.cpp -- this is UNSYNCED
-- LuaUI code, so it's the LuaUnsyncedCtrl::GiveOrderToUnit implementation,
-- NOT the LuaSyncedCtrl one BAR's own synced gadgets use): unsynced
-- GiveOrderToUnit does NOT call CCommandAI directly at all -- it does
-- `if (!CanGiveOrders(L)) { push false; return; }` FIRST, and if that
-- passes, sends the order as a network AI-command packet
-- (`clientNet->Send(...SendAICommand(...))`) rather than applying it
-- in-process. Either of those steps -- a false CanGiveOrders (checked
-- against `gs->PreSimFrame()`, `gs->noHelperAIs` i.e. the lobby "disable
-- helper AIs" setting, and `CanControlTeam`/ally-control rules -- source:
-- rts/Lua/LuaUnsyncedCtrl.cpp `CanGiveOrders()`), or the packet simply never
-- landing/being processed server-side, would look EXACTLY like what the log
-- showed: our call executes without erroring, but nothing changes, forever.
-- Every previous call site in this file (the Hold-Fire FIRE_STATE order, both
-- CMD.STOP calls, and the Deploy-time Fire-at-Will order) discarded this
-- return value, so this failure mode was completely invisible until now.
--
-- Not yet confirmed which (if any) of the above is the actual cause -- so
-- rather than guess again, build i's ONLY change is to capture and echo
-- GiveOrderToUnit's own boolean return for the FIRE_STATE order (added to
-- the existing Suppressing diagnostic) and for both CMD.STOP call sites (new
-- throttled echoes). If the next log shows `ok: false`, that's a definitive,
-- sourced answer (almost certainly gs.noHelperAIs or ally-control, both
-- fixable player-side, outside this widget's control -- see the log's exact
-- report to the user for next steps). If it shows `ok: true` every time yet
-- the readback still never moves, that instead points at something
-- server/gadget-side silently overriding it after a successful send
-- (e.g. a BAR gameplay gadget's own AllowCommand veto or a competing
-- fire-state writer), which is a different investigation entirely.
--
-- build j (2026-09-02): user's next screenshot hand-drew "up"/"right"
-- compass arrows from their unit and argued the actual cone (logged as
-- center=45, half-width=45) didn't match those directions. That comparison
-- implicitly assumes screen-up is a fixed world direction at both the
-- moment the cone was aimed and the moment of the screenshot -- true only
-- if the camera wasn't rotated in between, which this widget has no way to
-- guarantee (BAR's camera is freely rotatable). Rather than argue geometry
-- from a screenshot a third time, build j draws two reference lines
-- directly in world space (same transform as the wedge, so camera rotation
-- can't desync them): a bright centerline at the cone's own angle, and a
-- cyan tick at angle=0 (the same zero-reference the logged numbers use),
-- each with an on-screen degree label (DrawAngleReferenceLabels, called
-- from DrawScreen). Next screenshot settles it directly: if the centerline
-- doesn't sit in the visual middle of the wedge, that's a real bug; if it
-- does but still doesn't match where the user expected "up"/"right" to
-- be, that confirms it was a camera-rotation/screen-perspective read, not
-- a code issue.
--
-- build k (2026-09-02): the build-i diagnostic came back and gave a clean,
-- unambiguous answer to its own question -- GiveOrderToUnit returns `true`
-- on literally every single FIRE_STATE and STOP call, every time, for an
-- 85-second/70-sample test. That rules OUT the "silently refused locally"
-- theory (CanGiveOrders / gs.noHelperAIs) -- confirmed further from the
-- user's own infolog.txt (nohelperais=0 in this session's modoptions).
-- `true` here only ever meant "the network send happened," never "the
-- server applied it" (confirmed straight from
-- rts/Lua/LuaUnsyncedCtrl.cpp -- the boolean is pushed unconditionally
-- right after `clientNet->Send(...)`, no acknowledgement involved), so this
-- pointed at something AFTER the send silently discarding or overriding it.
--
-- Chased that exhaustively against BAR's actual current gadget source
-- (beyond-all-reason/Beyond-All-Reason, luarules/gadgets/) rather than
-- guessing: grepped every `gadgetHandler:RegisterAllowCommand(...)` call in
-- the whole gadget set (this is the ONLY mechanism that can route a command
-- to a gadget's `AllowCommand` veto callin at all) and read the body of
-- every one that could plausibly see CMD_FIRE_STATE (i.e. registered for
-- CMD_FIRE_STATE itself or CMD.ANY): `unit_firestate_handler.lua` (gated
-- behind an experimental mod option, confirmed off), `game_apm_broadcast.lua`
-- (always returns true), `unit_death_animations.lua` (only vetoes an
-- actively-dying unit), `unit_wanted_speed.lua` / `unit_airunitsturnradius.lua`
-- (both always return true for non-matching cmdIDs), `cmd_paused_is_paused.lua`
-- (only while the game is paused, confirmed not the case in the test log).
-- None of them can explain this. Also re-checked (and ruled out, from
-- source) two more theories: `LuaUtils::ParseCommand` dropping a param
-- value of literally `0` (it doesn't -- pushes every numeric table entry
-- regardless of value) and `CanChangeFireState()`/`canFireControl` being
-- false for this unitDef (ruled out by the unit's own behavior: armvulc's
-- real BAR unitdef sets `firestate = 0` i.e. Hold Fire as its BUILT-IN
-- default, yet the unit is observed actively engaging within 15 frames of
-- Deploy's FIRE_STATE=2 order -- which only works if that exact mechanism
-- is fully functional on this unitDef; the asymmetry is specifically
-- "0 after 2" failing, not FIRE_STATE changes categorically failing).
--
-- Net result: exhausted the list of explanations findable by reading
-- source. Build k adds one more free diagnostic point (`Spring.
-- GetUnitIsStunned` -- covers both real EMP/paralysis AND
-- under-construction, folded into the existing Suppressing echo) since it's
-- a real, cheap-to-check BAR mechanic that silently blocks unit orders and
-- hadn't been ruled out yet. But the single most decisive next step can
-- only come from the user, not more source-reading: does a plain, manual,
-- player-clicked Hold Fire (no widget involved at all) on this exact unit,
-- while it currently has a locked target, actually change
-- Spring.GetUnitStates(unitID).firestate? If even a manual click can't move
-- it off 2, this isn't a widget bug at all -- it's some in-game condition
-- specific to this unit/session, and the fix is elsewhere. If a manual
-- click DOES work, that reopens the AICOMMAND-network-path theory
-- specifically (rts/Net/GameServer.cpp's ValidateAICommandTeam / the
-- NETMSG_AICOMMAND path our widget's calls take, vs. whatever path a real
-- UI click takes) as the one remaining, not-yet-fully-eliminated
-- possibility.
--
-- NOT independently verified against the live engine this session (flagged
-- for in-game testing, same as prior widgets in this project):
--   - Exact multi-return shape of Spring.TraceScreenRay for a ground hit
--     (coded defensively to handle either a table or 3 separate numbers).
--   - Spring.GetUnitsInCylinder(x, z, radius) and Spring.AreTeamsAllied
--     confirmed against the official Lua API docs (parameter shapes/return
--     types), but not watched return live gameplay data yet.
--
-- build n (2026-09-03): REARCHITECTED from reactive fire-state gating to
-- proactive explicit-order commanding, per the user's direction after
-- discussing whether the engine was the blocker (it wasn't -- see build l).
-- Root problem with builds h-m: FireState is the ONLY lever unsynced Lua
-- has, and it only ever gates whether native AutoTarget is ALLOWED to go
-- looking for a fresh target on its own -- it can't tell AutoTarget WHICH
-- target to pick. So every version of the old design could only ever
-- react AFTER AutoTarget had already (possibly wrongly) chosen, and every
-- fix in that family (RELOCK_GRACE_FRAMES, RETRY_COOLDOWN_FRAMES, ...) was
-- narrowing a race that couldn't be closed, not fixing a bug.
--
-- Confirmed directly from engine source this session
-- (rts/Sim/Weapons/Weapon.cpp CWeapon::CanFire, rts/Sim/Units/Unit.cpp
-- CUnit::AttackUnit/AttackGround, rts/Sim/Units/CommandAI/CommandAI.cpp
-- CCommandAI::ExecuteAttack/GiveCommandReal):
--   1. CWeapon::CanFire() -- the function that actually gates every shot --
--      never once reads owner->fireState. It only checks aim angle, salvo/
--      reload timers, HaveTarget(), stockpile, and submersion. fireState
--      ONLY gates two things: CWeapon::AllowWeaponAutoTarget() (native
--      AutoTarget's own fresh-target search) and
--      CMobileCAI::GenerateAttackCmd() (the CAI spontaneously inventing a
--      new attack command while idle). An EXPLICIT CMD_ATTACK order given
--      by this widget bypasses fireState entirely and WILL fire, even on a
--      unit parked on Hold Fire the whole time.
--   2. CCommandAI::GiveCommandReal(): any non-shift command (exactly what
--      Spring.GiveOrderToUnit(unitID, CMD.ATTACK, {...}, {}) sends, since
--      cmdOptions is always {} here) clears the ENTIRE existing command
--      queue and calls ClearTargetLock() -- which itself drops any standing
--      attack target -- before the new order is applied. So switching this
--      widget's commanded target from one unit (or ground point) to another
--      needs no separate CMD.STOP first; issuing the new CMD.ATTACK alone
--      cancels the old one as a side effect. (This matches the existing
--      "only CMD.STOP breaks a locked attack order" finding from the
--      explicit-user-target case a few builds back -- same mechanism.)
--
-- New design: on Deploy, force Hold Fire ONCE (not every frame) and leave
-- it there permanently while the cone is enabled -- its only remaining job
-- is to stop the CAI from auto-inventing its own (potentially out-of-cone)
-- target during any gap where this widget hasn't given an order of its
-- own. Every GameFrame, find the closest currently-known (LOS or radar --
-- see FindBestLiveTargetInCone) enemy inside the cone+range and command an
-- explicit CMD.ATTACK directly at ITS unit ID -- the widget picks, not
-- AutoTarget, so there's no target-choice race left to lose. If nothing is
-- currently visible, fall back for a bounded window (GHOST_MEMORY_FRAMES)
-- to an Attack-GROUND order at the last position this widget itself
-- confirmed something at while it WAS visible -- this is the "or has been
-- in LOS previously" case the user asked for, and it's not a fog-of-war
-- leak: Spring.GetUnitPosition/GetUnitsInCylinder are already gated to only
-- ever return currently-visible units (confirmed from
-- rts/Lua/LuaUtils.cpp::IsUnitVisible and rts/Lua/LuaSyncedRead.cpp
-- ParseUnit), so this is purely the widget remembering what it already
-- legitimately saw -- exactly what a player does when they attack a ghost
-- building icon on their own screen. Orders are only reissued when the
-- desired action actually changes (plus a rare ATTACK_REFRESH_FRAMES
-- safety-net re-affirmation), not every frame, so this shouldn't reproduce
-- the network-packet-spam "clicking" failure mode from earlier builds.
-- RELOCK_GRACE_FRAMES/RETRY_COOLDOWN_FRAMES/NO_TARGET_GRACE_FRAMES and all
-- the toggle-tracking state they needed are gone -- there's no toggle left
-- to debounce.
--------------------------------------------------------------------------------

local spGetSelectedUnits   = Spring.GetSelectedUnits
local spGetUnitPosition    = Spring.GetUnitPosition
local spGetUnitDirection   = Spring.GetUnitDirection
local spGetUnitDefID       = Spring.GetUnitDefID
local spValidUnitID        = Spring.ValidUnitID
local spGetUnitWeaponTarget= Spring.GetUnitWeaponTarget
local spGetUnitWeaponCanFire = Spring.GetUnitWeaponCanFire
local spGetUnitWeaponState = Spring.GetUnitWeaponState -- build zv: real fire-event detection, see HasWeaponJustFired
local spGetUnitIsStunned   = Spring.GetUnitIsStunned
local spGiveOrderToUnit    = Spring.GiveOrderToUnit
local spGetMouseState      = Spring.GetMouseState
local spGetModKeyState     = Spring.GetModKeyState -- build zi/zj: alt, ctrl, meta, shift -- confirmed against the engine's own LuaUnsyncedRead.cpp
local spGetCameraState     = Spring.GetCameraState
local spSetCameraState     = Spring.SetCameraState
local spTraceScreenRay     = Spring.TraceScreenRay
local spWorldToScreenCoords= Spring.WorldToScreenCoords
local spGetGroundHeight    = Spring.GetGroundHeight
local spGetUnitRadius      = Spring.GetUnitRadius
local spEcho                = Spring.Echo

local glColor   = gl.Color
local glText    = gl.Text
local glRect    = gl.Rect
local glLineWidth = gl.LineWidth
local glBeginEnd = gl.BeginEnd
local glVertex  = gl.Vertex
local glPushMatrix = gl.PushMatrix
local glPopMatrix  = gl.PopMatrix
local glTranslate  = gl.Translate
local glGetTextWidth = gl.GetTextWidth -- build u: used to keep the angle-reference labels from overlapping (see DrawAngleReferenceLabels)
local GL_LINE_LOOP = GL.LINE_LOOP
local GL_TRIANGLE_FAN = GL.TRIANGLE_FAN
local GL_LINES = GL.LINES

local arcUnitDefIDs = {} -- [unitDefID] = true, resolved in Initialize

--------------------------------------------------------------------------------
-- INTERNAL CONSTANTS (camera/drawing plumbing -- not meant for casual
-- tweaking; the settings players actually want to change are all gathered
-- in the USER-TWEAKABLE SETTINGS block near the very top of this file)
--------------------------------------------------------------------------------
local ZOOM_OUT_HUGE_DIST       = 1e9       -- deliberately absurd; CSpringController::Update()
                                            -- clamps curDist to [minDist,maxDist] every frame
                                            -- (confirmed against the engine source), so this
                                            -- reliably lands on the real max zoom regardless
                                            -- of map size, without needing to know that value.
ZOOM_OUT_RANGE_TIERS[#ZOOM_OUT_RANGE_TIERS].dist = ZOOM_OUT_HUGE_DIST -- build zz4: fill in the top tier now that this exists

-- Added 2026-09-03, replacing the old SWITCH_OFFSET_Y fixed-PIXEL offset:
-- the user's own screenshots showed the "X" button drifting up into the
-- middle of the unit model when zoomed in close, because a constant
-- screen-pixel offset from the unit's projected anchor point stays the
-- same number of pixels regardless of how large the unit renders on
-- screen -- fine zoomed out (where the whole model only spans a few dozen
-- pixels anyway), visibly wrong zoomed in (where the model's true base can
-- be 150+ pixels below that same anchor point). This is now a WORLD-space
-- distance (elmos) added to the unit's own collision radius
-- (Spring.GetUnitRadius) instead -- see GetSwitchScreenRect, which
-- measures the unit's actual on-screen size each frame via a second
-- projected point and scales the button's screen offset by that, so the
-- button tracks the unit's real rendered base at every zoom level.
local REMOVE_BUTTON_GROUND_MARGIN = 14     -- elmos beyond the unit's own radius
local REMOVE_W, REMOVE_H = 18, 18          -- "X" (disable) button screen size, px

-- build zo, per the user ("put a '?' next to X and when you click on it a
-- tooltip showing you all the functions"): a second, smaller world-
-- anchored button next to "X" that toggles a full controls-reference
-- panel -- see GetHelpScreenRect/DrawControlsHelpPanel/CONTROLS_HELP_ROWS.
local HELP_W, HELP_H = 16, 16              -- "?" (help) button screen size, px
local HELP_BUTTON_GAP_PX = 6               -- gap between "X" and "?", px

-- Real engine FIRESTATE_* values (rts/Sim/Units/CommandAI/CommandAI.h),
-- confirmed matching what Spring.GetUnitStates().firestate returns and what
-- Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {v}, {}) expects.
local FIRESTATE_HOLDFIRE, FIRESTATE_RETURNFIRE, FIRESTATE_FIREATWILL = 0, 1, 2
-- Minimum ground-position drift (elmos) before a fresh ghost-memory sighting
-- counts as "a different Attack-ground target" worth reissuing the order
-- for, rather than the same spot within normal position noise. Technical/
-- internal -- not one of the USER-TWEAKABLE SETTINGS near the top, since
-- there's rarely a reason to touch it.
local GROUND_POS_EPS = 32

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
-- arcConfig[unitID] = { angle=rad, halfWidth=rad, rangeCap=elmos, enabled=bool }
local arcConfig = {}
-- pendingDraft[unitID] = { angle=, halfWidth=, rangeCap= } -- transient, only
-- populated between the angle-lock and range-lock clicks; DeployDraft()
-- commits it into arcConfig and clears it the instant range is locked.
local pendingDraft = {}
-- [unitID] = sim frame of the last "STOP issued" diagnostic echo (throttle
-- state for EnforceArcOnUnit; declared up here, not next to
-- EnforceArcOnUnit below, specifically so it's visible as an upvalue to
-- widget:UnitDestroyed, which is defined earlier in the chunk than
-- EnforceArcOnUnit -- Lua locals are only visible to code that comes after
-- their declaration).
local lastStopEchoFrame = {}
-- [unitID] = the unit's real fire state (1=Return Fire, 2=Fire-at-Will) to
-- restore once it's safe -- present only while this widget is actively
-- forcing that unit to Hold Fire to block an out-of-cone/range engagement.
-- 0 is a valid stored value (means "was already Hold Fire, nothing to
-- restore, but still actively suppressed") and is truthy in Lua, so
-- `if suppressedFireState[unitID] then` correctly detects "currently
-- suppressing" either way.
local suppressedFireState = {}
-- Added 2026-09-03 (build n), replacing the old reactive toggle state.
-- [unitID] = what this widget currently has the unit explicitly commanded
-- to do: "unit" (attacking a specific live enemy unit ID),
-- "ground" (attacking a remembered last-known position), or "none" (Stop
-- issued, nothing valid in the cone). nil means "never commanded anything
-- yet this deployment."
local currentActionKind = {}
-- [unitID] = the enemy unit ID currently commanded, only meaningful when
-- currentActionKind[unitID] == "unit".
local currentActionTargetID = {}
-- [unitID] = { x=, y=, z= } currently commanded ground-attack point, only
-- meaningful when currentActionKind[unitID] == "ground".
local currentActionPos = {}
-- [unitID] = sim frame the current action was last (re)issued -- both the
-- "did this actually change" gate and the ATTACK_REFRESH_FRAMES safety-net
-- re-affirmation read this.
local lastActionFrame = {}
-- [unitID] = { x=, y=, z=, frame= } -- the most recent position this widget
-- itself confirmed a live (LOS/radar-visible) enemy at inside the cone.
-- Refreshed every frame a live target exists; consulted as the Attack-
-- ground fallback for up to GHOST_MEMORY_FRAMES once nothing is live any
-- more. See the build-n DESIGN NOTES entry above.
local ghostContact = {}

-- build zs, per the user ("this one is useless [the build-zr aim line] /
-- Does the engine let you know where the turret is pointing at? ... can
-- you use the 2 points ... like the death star getting into position").
-- [unitID] = this widget's own SELF-TRACKED estimate of the weapon's
-- current aim bearing (radians, this file's usual angle convention --
-- see BearingTo), for units currently actively engaging something. Exists
-- because of a hard engine limitation, researched and confirmed against
-- the source (rts/Lua/LuaSyncedRead.cpp, Spring.GetUnitWeaponVectors):
-- for a Cannon-type weapon (what every arc-eligible unit here uses,
-- confirmed from their own unit defs) the engine only exposes
-- weapon->wantedDir -- the pure geometric bearing to the current target,
-- which jumps instantly on retarget -- never the real, physically-
-- turning-over-time model orientation (weapon->weaponDir), which the
-- engine only exposes through this same call for Missile/Torpedo/
-- Starburst weapons. No Lua call was found that exposes the real angle
-- for a Cannon weapon directly. So instead of drawing that unusable
-- instantly-snapping bearing (build zr, now removed), this widget
-- SIMULATES a plausible turning motion itself -- see
-- UpdateSimulatedAimAngles below -- interpolating this value toward the
-- target bearing at an assumed rate (AIM_SWEEP_TURN_RATE_DEG_PER_SEC,
-- USER-TWEAKABLE SETTINGS -- a guess, since actual turret slew speed is
-- baked into each unit's own compiled COB script and isn't exposed as
-- data either). nil until a unit first starts engaging something; cleared
-- in RestoreFireStateIfSuppressed alongside the other per-unit tracking
-- tables above.
-- build zv, per the user ("the ragnarok took 6 seconds to fire after the
-- widget finished [i.e. the wedge]" -- the wedge was closing well before
-- the real shot): this used to also self-correct/snap early via
-- Spring.GetUnitWeaponCanFire's ignoreAngleGood trick (IsWeaponAngleGood,
-- removed this build) whenever the engine's internal `angleGood` flag
-- went true. Re-reading rts/Sim/Weapons/Weapon.cpp disproved that as a
-- reliable "turret finished turning" signal: CWeapon::CheckAimingAngle
-- checks the target against `mainDir` (the weapon's configured firing-arc
-- tolerance), NOT its actual current modeled orientation -- the source
-- comment literally says "angleGood checks unit/maindir, not the
-- weapon's current dir" -- and for any weapon with allowNonBlockingAim
-- (common on turreted units, to avoid stutter), CWeapon::CallAimingScript
-- never even waits for the COB aiming script's real completion callback
-- before considering angleGood good. In short: angleGood can and does go
-- true well before the 3D turret model has actually finished its
-- animated rotation, which explains exactly the reported symptom (the
-- simulated wedge snapping closed early). See HasWeaponJustFired below
-- for the real, ground-truth signal used now instead.
local simulatedAimAngle = {}
-- build zv: [unitID] = the weapon-1 reloadFrame (Spring.GetUnitWeaponState
-- "reloadFrame") this widget last observed for that unit, used by
-- HasWeaponJustFired to detect the exact frame a real shot left the
-- barrel (reloadFrame jumping forward is the engine committing to a new
-- reload countdown, which only happens on an actual fire event). nil
-- until first observed; cleared in RestoreFireStateIfSuppressed alongside
-- simulatedAimAngle.
local lastReloadFrame = {}

-- build zi, per the user: global runtime switch for the "/conefirehide" /
-- "/conefireon" chat commands (see ConeFireOff/ConeFireOn and
-- widget:Initialize's AddAction registrations below). false (the default,
-- matching "/conefireon" / "cone GUI is always on") means the illustrative
-- wedge/line/labels for every deployed cone draw normally, same as ever;
-- true (set by "/conefirehide") hides that illustration for any unit that's
-- actively engaging something in its cone RIGHT NOW (see
-- ShouldShowConeGui below), so the screen stays clean during an actual
-- fight and the illustration reappears the instant that unit goes idle
-- again. This is purely visual -- it never touches enforcement itself,
-- only whether the wedge/line/labels are DRAWN.
local autoHideGuiWhileFiring = false

-- build zw, per the user: global runtime switch for the "/conefirewedge"
-- chat command -- true (the default) draws the red aim-sweep wedge
-- (simulatedAimAngle/DrawAimSweep, see their own declarations above) as
-- usual; false hides it entirely for every unit, in case a player finds
-- it distracting or just wants the plain cone/range illustration. Purely
-- visual, same as autoHideGuiWhileFiring above -- never touches
-- enforcement, and never touches whether simulatedAimAngle itself keeps
-- being tracked/updated (UpdateSimulatedAimAngles keeps running regardless,
-- so the wedge picks up mid-turn instantly if toggled back on rather than
-- restarting from hull-facing).
local showAimSweepWedge = true

-- build zo: whether the on-screen controls-reference panel (toggled by
-- clicking any unit's "?" button, see GetHelpScreenRect/MousePress/
-- DrawControlsHelpPanel) is currently shown. Global, not per-unit -- one
-- panel, same content, regardless of which unit's "?" opened it.
local showControlsHelp = false

-- build zo/zp: screen position (set at the moment a "?" is clicked, see
-- widget:MousePress) the panel opens next to -- see DrawControlsHelpPanel
-- for how this gets clamped so the panel always stays fully on screen
-- regardless of where on screen that "?" happened to be.
local helpPanelAnchorX, helpPanelAnchorY = nil, nil

-- build zt, per the user: "make sure you ahve a close option for the ?
-- tooltip using X upper right corner" -- the panel used to only close by
-- clicking a "?" again, which broke down exactly as the user described:
-- disabling cone-of-fire on the unit whose "?" opened the panel (via its
-- "X") removes that unit from arcConfig entirely, taking its "?" button
-- with it -- leaving the panel open with no "?" left anywhere to click,
-- unless some OTHER unit still happens to have one. This close button is
-- independent of any unit -- always closes the panel regardless of what
-- happens to whichever unit opened it. Screen rect recomputed each frame
-- the panel is drawn (DrawControlsHelpPanel) and read back by
-- widget:MousePress -- nil whenever the panel isn't currently shown.
local helpPanelCloseRect = nil

-- build zo, reworked zp into a 2-column {label, desc} table per the user
-- ("also make it 2 columns 1st column are the commans or subject and the
-- 2nd colum the descrption"): column 1 is the control itself (a key/
-- click/command), column 2 explains what it does. Mirrors the CONTROLS
-- block at the top of this file (kept in sync with it by hand) plus the
-- CHAT COMMANDS section, so everything a player can actually DO with this
-- widget is reachable in-game without opening the .lua file itself.
local CONTROLS_HELP_ROWS = {
    { label = "Ctrl+C",              desc = "On selected unit(s) (or the Cone-of-Fire command-panel button) -- draw a new cone. Select MULTIPLE first to link them into one shared cone/range." },
    { label = "While aiming",        desc = "Scroll wheel widens/narrows the cone, left-click locks the angle, then move the mouse to set the range, left-click again to activate." },
    { label = "Right-click",         desc = "During the RANGE step, backs up to the CONE (angle) step to re-adjust it. Right-click again (or Escape twice, any time) -- cancels setup entirely." },
    { label = "\"X\"",               desc = "Remove that unit's cone-of-fire permanently." },
    { label = "Ctrl+Click \"X\"",    desc = "Clear every cone-of-fire config currently on screen at once." },
    { label = "Ctrl+Click unit",     desc = "Toggle just that unit's cone illustration on/off. Always overrides /conefirehide auto-hide (below), and stays as you left it until Ctrl+Clicked again." },
    { label = "/conefirehide",       desc = "Auto-hides the cone illustration on any unit the instant it starts actively engaging a target, and shows it again once it goes idle. Saved across sessions." },
    { label = "/conefireon",         desc = "The default -- cone illustrations are always shown." },
    { label = "/conefiredisable",    desc = "Removes cone-of-fire from EVERY unit in the game at once (not just what's on screen)." },
    { label = "/conefirewedge",      desc = "Toggles the red aim-sweep wedge (below) on/off for every unit at once. On by default. Saved across sessions." },
    { label = "/conefiredefault",    desc = "Resets /conefirehide-vs-on and /conefirewedge back to their original defaults (always shown, wedge on)." },
    { label = "\"?\"",               desc = "Toggle this panel. Click any \"?\" again, or the \"X\" in this panel's own upper-right corner, to close it." },
    { label = "Red wedge",           desc = "While actively engaging, shows the gap between the turret's current heading and its target, shrinking as it turns and disappearing once fully aimed. An approximation -- the engine doesn't expose the real live turret angle for this weapon type. Toggle with /conefirewedge." },
}

-- Whether unit `unitID`'s cone illustration (wedge outline + centerline +
-- the "N° (cone center)"/"N°" labels) should be drawn THIS frame. Shared
-- by DrawWorldPreUnit and DrawAngleReferenceLabels so the two stay in
-- sync -- called per-unit, per-frame, so kept cheap (a couple of table
-- reads, no Spring API calls).
--
-- `cfg.guiOverride` is a per-unit manual OVERRIDE set by Ctrl+Click
-- directly on an already-configured unit (see widget:MousePress): nil
-- means "no override, use the automatic rule below"; true means
-- "force-hidden"; false means "force-shown". Deliberately a full
-- override rather than an independent hide reason (build zm fix, per
-- the user: "if i have conefirehide, if i ctrl+click on a firing unit it
-- still hides the cone diagram" -- with a plain independent flag,
-- Ctrl+Click while a unit is actively firing under "/conefirehide" was a
-- complete no-op, since the auto-hide rule below would re-hide it
-- regardless of what the manual flag said). Now Ctrl+Click always wins,
-- in either direction, and stays exactly as the player left it -- even
-- across that unit going idle and firing again -- until they Ctrl+Click
-- it again to release the override.
--
-- With no override, `autoHideGuiWhileFiring` (the "/conefirehide" mode)
-- combined with this specific unit actively engaging something right
-- now decides it -- `currentActionKind[unitID]` is "unit" or "ground"
-- only while EnforceArcOnUnit has it actively commanded to attack, and
-- reverts to "none" (or nil, before its first target) the instant
-- nothing valid remains in its cone -- an existing, always-up-to-date
-- signal that needed no new per-frame weapon queries to reuse here.
local function ShouldShowConeGui(unitID, cfg)
    if cfg.guiOverride ~= nil then return not cfg.guiOverride end
    if autoHideGuiWhileFiring then
        local kind = currentActionKind[unitID]
        if kind == "unit" or kind == "ground" then return false end
    end
    return true
end

local MODE_NONE, MODE_ANGLE, MODE_RANGE = 0, 1, 2
local mode = MODE_NONE
local modeUnitID = nil
-- build ze, per the user ("multiple ragnaroks... shares exactly the final
-- cone and range"): every arc-capable unit that was selected when setup
-- began (Ctrl+C), in selection order. modeUnitID (above) is always
-- modeGroupUnitIDs[1] -- the one the interactive preview is actually aimed
-- from -- while the rest ride along silently until the range is locked,
-- at which point each of them gets its OWN derived angle/halfWidth/
-- rangeCap so its cone's edges land on the exact same two world points as
-- modeUnitID's cone (see GetConeEdgePoints/DeriveLinkedCone and the
-- MousePress MODE_RANGE deploy step). nil, or a single-entry array, means
-- "no linking, business as usual" -- covers both the plain single-unit
-- Ctrl+C flow and the command panel's "Reconfigure Arc" (which only ever
-- runs with exactly one unit selected to begin with).
local modeGroupUnitIDs = nil
local previewAngle = 0
local previewHalfWidth = DEFAULT_HALF_WIDTH
local previewRangeCap = 0
local modeNativeRange = 0

local lastEscapeTime = nil

--------------------------------------------------------------------------------
-- CUSTOM COMMAND IDS
--------------------------------------------------------------------------------
local CMD_FIREARC_SETUP    = 31901
local CMD_FIREARC_UNDEPLOY = 31904
-- 31902/31903 (Deploy/Cancel) retired 2026-09-02: locking the range now
-- deploys immediately, so there's no pending-draft state left needing
-- separate confirm/discard commands.

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function NormalizeAngle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

local function IsArcUnit(unitDefID)
    return unitDefID ~= nil and arcUnitDefIDs[unitDefID]
end

local function GetWeaponRange(unitDefID)
    local ud = UnitDefs[unitDefID]
    if not ud or not ud.weapons or not ud.weapons[1] then return 0 end
    local wd = WeaponDefs[ud.weapons[1].weaponDef]
    if not wd then return 0 end
    return wd.range or 0
end

-- Defensive: handles either (type, {x,y,z}) or (type, x,y,z) return shapes.
local function GetMouseGroundPos()
    local mx, my = spGetMouseState()
    if not mx then return nil end
    local typ, a, b, c = spTraceScreenRay(mx, my, true)
    if typ ~= "ground" or a == nil then return nil end
    if type(a) == "table" then
        return a[1], a[2], a[3]
    end
    return a, b, c
end

local function BearingTo(ux, uz, tx, tz)
    return math.atan2(tx - ux, tz - uz)
end

-- widgetHandler:CommandsChanged() (the vanilla-Spring "force
-- widget:CommandsChanged() to re-run on every widget right now" method)
-- does NOT exist on BAR's widgetHandler -- confirmed in-game: "attempt to
-- call method 'CommandsChanged' (a nil value)". Command panel rebuilds are
-- driven by real engine events (selection change chief among them), so the
-- reliable way to force one from Lua is to reselect the current selection.
--
-- IMPORTANT (2026-09-02 revision): the first version of this called
-- Spring.SelectUnitArray(sel) with the SAME array that was already
-- selected. That is suspected to have been a no-op on BAR's engine build --
-- some Spring/Recoil versions skip firing the selection-changed event when
-- the passed-in selection is identical to the current one, since nothing
-- "changed". If that's what's happening, Deploy would silently never
-- appear after locking the range, arcConfig would never get populated, and
-- the cone would never actually be enforced -- which matches the user
-- report ("it still shoots outside of it at will") as a total failure
-- rather than an occasional miss. To guarantee a REAL transition (and
-- therefore guarantee the event fires on any engine build), briefly
-- deselect to empty and then reselect the real array.
local function ForceCommandPanelRefresh()
    local sel = spGetSelectedUnits()
    if #sel > 0 then
        Spring.SelectUnitArray({})
        Spring.SelectUnitArray(sel)
    end
end

-- Restores a unit's real fire state if this widget currently has it forced
-- to Hold Fire (see suppressedFireState above). Must be called any time a
-- unit stops being actively enforced for a reason OTHER than the bad
-- target clearing on its own -- Pausing, permanently removing, or the unit
-- dying -- otherwise it could get stuck on Hold Fire forever with nothing
-- left to ever restore it.
-- Rewritten 2026-09-03 (build n) for the new one-shot Hold-Fire lifecycle:
-- Deploy sets Hold Fire exactly once (see DeployDraft) rather than every
-- frame, so undoing it is now a genuine restore-to-original, not an
-- undo-this-frame's-toggle. Also clears every piece of per-unit commanding
-- state and, critically, issues a final CMD.STOP -- without it, a standing
-- Attack order this widget gave (which fireState changes alone do NOT
-- cancel; only CMD.STOP does, per the build-n DESIGN NOTES) would keep
-- executing indefinitely even after the cone is disabled/removed, leaving
-- the unit stuck attacking whatever it was last told to instead of
-- genuinely returning to normal behavior.
local function RestoreFireStateIfSuppressed(unitID)
    local restore = suppressedFireState[unitID]
    if restore then
        if spValidUnitID(unitID) then
            if restore > FIRESTATE_HOLDFIRE then
                spGiveOrderToUnit(unitID, CMD.FIRE_STATE, {restore}, {})
            end
            spGiveOrderToUnit(unitID, CMD.STOP, {}, {})
        end
        suppressedFireState[unitID] = nil
    end
    currentActionKind[unitID] = nil
    currentActionTargetID[unitID] = nil
    currentActionPos[unitID] = nil
    lastActionFrame[unitID] = nil
    ghostContact[unitID] = nil
    simulatedAimAngle[unitID] = nil -- build zs, see its declaration below
    lastReloadFrame[unitID] = nil -- build zv, see its declaration below
end

-- build ze: shared-cone helpers for a linked multi-unit deploy (see
-- modeGroupUnitIDs above and the MousePress MODE_RANGE handler below,
-- which is the only caller of both of these). Per the user: when more
-- than one arc-capable unit is selected together for setup, every unit
-- should end up defending the exact same patch of the map -- "it shares
-- exactly the final cone and range" -- even though each unit sits at a
-- different position and therefore needs its own angle (and, in general,
-- its own range cap too) to make its own straight cone edges land on that
-- same shared area. The trick: reduce "the cone" to just the two points
-- in WORLD space where the reference unit's own two edges meet its own
-- range boundary, then, for every other unit, work BACKWARDS from those
-- two fixed points to that unit's own angle/halfWidth/rangeCap. Two
-- units' cones sharing those same two points is exactly the "2 red
-- circles" the user's screenshot showed; this generalizes to any number
-- of units by deriving each one independently from the same pair of
-- points.

-- Given a unit's own final angle/halfWidth/rangeCap (its cone, apex at
-- ux,uz), returns the world (x,z) coordinates of the two points where its
-- LEFT and RIGHT edges meet its own range boundary.
local function GetConeEdgePoints(ux, uz, angle, halfWidth, rangeCap)
    local leftAngle = angle - halfWidth
    local rightAngle = angle + halfWidth
    local lx = ux + math.sin(leftAngle) * rangeCap
    local lz = uz + math.cos(leftAngle) * rangeCap
    local rx = ux + math.sin(rightAngle) * rangeCap
    local rz = uz + math.cos(rightAngle) * rangeCap
    return lx, lz, rx, rz
end

-- Works backwards from two shared world points (lx,lz and rx,rz -- see
-- GetConeEdgePoints above) to derive what a DIFFERENT unit sitting at
-- ox,oz needs its OWN angle/halfWidth/rangeCap to be so its own cone's two
-- edges terminate at those exact same two points. `angle` is the bisector
-- of this unit's bearings to the two points (NormalizeAngle handles either
-- point being "left" or "right" from this unit's own point of view --
-- position differences between linked units can flip which side looks
-- closer to which bearing, and the bisector math below is symmetric either
-- way); `halfWidth` is half the angular gap between those two bearings.
-- `rangeCap` is set to whichever of the two points is FARTHER from this
-- unit, so both shared points are guaranteed to sit within its own
-- configured range (the nearer point then sits a bit inside the boundary,
-- rather than both landing exactly on it -- unavoidable unless the two
-- points happen to be exactly equidistant from this unit). Clamped to this
-- unit's own native weapon range and the normal MIN/MAX half-width dial
-- limits -- same limits manual setup already enforces -- so a unit
-- positioned at an extreme angle relative to the shared points still gets
-- a valid, if imperfect, cone rather than an invalid one.
local function DeriveLinkedCone(ox, oz, nativeRange, lx, lz, rx, rz)
    local bearingL = BearingTo(ox, oz, lx, lz)
    local bearingR = BearingTo(ox, oz, rx, rz)
    local diff = NormalizeAngle(bearingR - bearingL)
    local angle = NormalizeAngle(bearingL + diff / 2)
    local halfWidth = math.abs(diff) / 2
    if halfWidth < MIN_HALF_WIDTH then halfWidth = MIN_HALF_WIDTH end
    if halfWidth > MAX_HALF_WIDTH then halfWidth = MAX_HALF_WIDTH end
    local distL = math.sqrt((lx - ox) * (lx - ox) + (lz - oz) * (lz - oz))
    local distR = math.sqrt((rx - ox) * (rx - ox) + (rz - oz) * (rz - oz))
    local rangeCap = math.max(distL, distR)
    if rangeCap < MIN_RANGE_CAP then rangeCap = MIN_RANGE_CAP end
    if nativeRange and nativeRange > 0 and rangeCap > nativeRange then rangeCap = nativeRange end
    return angle, halfWidth, rangeCap
end

-- Commits a pendingDraft (angle+halfWidth+rangeCap) into the live, enforced
-- arcConfig. Called the instant the range is locked (2nd LMB click) -- no
-- separate confirm step, per the user, 2026-09-02: "i don't like that
-- deploy once you set range that's it." As of build n (2026-09-03), what
-- the unit does afterward is fully owned by this widget -- see the comment
-- just below on why Hold Fire is forced here and what EnforceArcOnUnit
-- does with it from then on.
local function DeployDraft(unitID)
    local d = pendingDraft[unitID]
    if not (d and d.rangeCap) then return false end
    arcConfig[unitID] = {
        angle = d.angle,
        halfWidth = d.halfWidth,
        rangeCap = d.rangeCap,
        enabled = true,
    }
    pendingDraft[unitID] = nil
    -- Rewritten 2026-09-03 (build n): finishing setup now puts the unit on
    -- HOLD FIRE, not Fire-at-Will -- per the user's direction, engagement
    -- from here on is driven entirely by this widget's own explicit
    -- CMD.ATTACK orders in EnforceArcOnUnit (see the build-n DESIGN NOTES
    -- entry for why explicit orders fire regardless of fireState), and Hold
    -- Fire's only remaining job is to stop the native CAI from inventing an
    -- out-of-cone target of its own during any gap where this widget hasn't
    -- given an order yet. Capture whatever fire stance the player had
    -- BEFORE this so RestoreFireStateIfSuppressed can hand it back exactly
    -- once, when the cone is later disabled/removed -- same
    -- capture-then-restore contract as ever, just now set a single time
    -- here instead of re-derived every suppression-entry frame.
    local preDeployStates = Spring.GetUnitStates(unitID)
    local preDeployFS = preDeployStates and preDeployStates.firestate
    suppressedFireState[unitID] = preDeployFS or 0
    currentActionKind[unitID] = "none"
    currentActionTargetID[unitID] = nil
    currentActionPos[unitID] = nil
    lastActionFrame[unitID] = nil
    ghostContact[unitID] = nil
    local deployFsOk = spGiveOrderToUnit(unitID, CMD.FIRE_STATE, {FIRESTATE_HOLDFIRE}, {})
    if not deployFsOk then
        spEcho(string.format(
            "[Cone-of-Fire] WARNING: Deploy's Hold-Fire order for unit %d was rejected by GiveOrderToUnit -- the unit may still be on its previous fire stance until EnforceArcOnUnit's own explicit orders take over.",
            unitID))
    end
    -- Best-effort only now, not load-bearing: this refreshes the command
    -- panel's "Reconfigure Arc"/"Remove Permanently" buttons if they render
    -- on this engine build. The actual restriction is already fully active
    -- via arcConfig regardless of whether this succeeds -- GameFrame's
    -- enforcement loop and the world-anchored On/Pause switch both read
    -- arcConfig directly, with no command-panel dependency at all.
    ForceCommandPanelRefresh()
    return true
end

-- build ze: was FindFirstArcUnitInSelection (returned just the first
-- match) -- now returns EVERY arc-capable unit in the current selection,
-- in selection order, so a multi-select Ctrl+C can link all of them
-- together instead of silently ignoring everything past the first one.
local function FindArcUnitsInSelection()
    local sel = spGetSelectedUnits()
    local out = {}
    for i = 1, #sel do
        local udid = spGetUnitDefID(sel[i])
        if IsArcUnit(udid) then
            out[#out + 1] = sel[i]
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- MODE CONTROL
--------------------------------------------------------------------------------
local function CancelMode()
    if mode ~= MODE_NONE then
        spEcho("[Cone-of-Fire] Cancelled.")
    end
    mode = MODE_NONE
    modeUnitID = nil
    modeGroupUnitIDs = nil
end

-- Zooms/pans the camera out while aiming a cone. Originally always zoomed
-- all the way out to try to show the WHOLE MAP (per the user's earlier
-- request -- "try to display the whole map if you can") -- build zz4, per
-- the user ("put all the unit ranges in to categories say any unit over
-- 3000 range zoom all the way out, smaller ranges like 1000 the zoom
-- shouldn't be all the way out"): that's still exactly right for a long-
-- range unit like Ragnarok, where the cone can span a large chunk of the
-- map -- but for a short-range tower like Gauntlet (range ~1220), zooming
-- all the way out shrank its whole cone down to a speck in the middle of
-- the screen, useless for actually aiming it. Now looks up a zoom distance
-- from ZOOM_OUT_RANGE_TIERS (USER-TWEAKABLE SETTINGS, near the top of this
-- file) keyed by the unit's own native weapon range (GetWeaponRange).
--
-- Only the TOP tier (ZOOM_OUT_HUGE_DIST, the same "whole map" behavior as
-- before) still focuses on the MAP's center rather than the unit -- at
-- that zoom level there's no reason to keep the unit off-center, wherever
-- it lands in the full view is wherever it naturally is on the map. Every
-- other (smaller) tier focuses on the UNIT itself instead -- at a moderate
-- zoom, centering on the map would usually mean NOT actually looking at
-- the unit/cone at all.
--
-- "Zoom all the way out": the actual engine has its own configured max
-- camera distance (CSpringController::Update() clamps curDist to
-- [minDist,maxDist] every frame -- confirmed by reading the engine
-- source), which this can't exceed. On a big map with a comparatively
-- tight max-zoom setting, this may fall short of the literal whole map --
-- that's a hard engine limit, not something a widget can override, so this
-- is genuinely best-effort.
--
-- Only touches fields that already exist on the current camera
-- controller's state table, so it's a no-op (rather than an error) under a
-- camera mode that doesn't have px/pz/dist (e.g. a free-fly camera) -- not
-- independently verified in-game which BAR camera modes that covers.
local function GetZoomOutDistForRange(range)
    for i = 1, #ZOOM_OUT_RANGE_TIERS do
        local tier = ZOOM_OUT_RANGE_TIERS[i]
        if range <= tier.maxRange then
            return tier.dist, (i == #ZOOM_OUT_RANGE_TIERS)
        end
    end
    -- Unreachable (the last tier's maxRange is math.huge), but a safe
    -- fallback to the old always-max-zoom behavior just in case.
    return ZOOM_OUT_HUGE_DIST, true
end

local function ZoomOutForSetup(unitID)
    local ux, uy, uz = spGetUnitPosition(unitID)
    if not ux then return end

    local camState = spGetCameraState()
    if not camState then return end

    local range = GetWeaponRange(spGetUnitDefID(unitID))
    local dist, isMapWideTier = GetZoomOutDistForRange(range)

    -- Game.mapSizeX/mapSizeZ are the standard Spring/BAR globals for map
    -- size in elmos. Fall back to centering on the unit itself if they're
    -- ever unavailable, rather than erroring.
    local focusX, focusZ = ux, uz
    if isMapWideTier and Game and Game.mapSizeX and Game.mapSizeZ then
        focusX = Game.mapSizeX * 0.5
        focusZ = Game.mapSizeZ * 0.5
    end

    if camState.px ~= nil then camState.px = focusX end
    if camState.pz ~= nil then camState.pz = focusZ end
    if camState.dist ~= nil then camState.dist = dist end
    spSetCameraState(camState, ZOOM_OUT_TRANSITION_TIME)
end

-- `group`, when given, is the full set of units this setup session should
-- deploy to once range is locked (see the MousePress MODE_RANGE handler) --
-- defaults to just `{unitID}` (no linking) when omitted, which covers both
-- the plain solo Ctrl+C flow and "Reconfigure Arc" from the command panel.
local function EnterAngleMode(unitID, group)
    modeUnitID = unitID
    modeGroupUnitIDs = group or { unitID }
    mode = MODE_ANGLE
    local existing = arcConfig[unitID]
    previewHalfWidth = existing and existing.halfWidth or DEFAULT_HALF_WIDTH
    -- build zz6, per the user: modeNativeRange used to only get
    -- (re)assigned when transitioning MODE_ANGLE -> MODE_RANGE, so it
    -- stayed stuck at whatever unit was configured LAST across an entire
    -- setup session. Selecting a short-range unit (e.g. a Pulsar, 1400)
    -- right after finishing setup on a long-range one (e.g. a Ragnarok,
    -- 5750) would show the Ragnarok's leftover range in the MODE_ANGLE
    -- preview (via DrawWorldPreUnit's math.max(modeNativeRange, ...)
    -- below) until a full MODE_RANGE pass refreshed it. Refresh it right
    -- here, for whichever unit setup is actually starting on, before any
    -- preview is ever drawn.
    modeNativeRange = GetWeaponRange(spGetUnitDefID(unitID))
    ZoomOutForSetup(unitID)
    if #modeGroupUnitIDs > 1 then
        spEcho(string.format(
            "[Cone-of-Fire] Create SHARED cone-of-fire for %d units: scroll wheel to adjust width, left-click to set. Aiming from the first-selected unit -- the rest will get the same cone boundary, angled for their own position, once you lock the range.",
            #modeGroupUnitIDs))
    else
        spEcho("[Cone-of-Fire] Create cone-of-fire: scroll wheel to adjust width, left-click to set.")
    end
end

local function ToggleMode()
    if mode ~= MODE_NONE then
        CancelMode()
        return
    end
    local group = FindArcUnitsInSelection()
    if #group == 0 then
        spEcho("[Cone-of-Fire] Select a unit this widget applies to first (see ARC_UNIT_NAMES).")
        return
    end
    EnterAngleMode(group[1], group)
end

--------------------------------------------------------------------------------
-- CHAT COMMANDS -- build zi, per the user
--------------------------------------------------------------------------------
-- Three typed-in-chat commands, registered as normal widget actions in
-- widget:Initialize below (Spring routes an unrecognized "/word args" chat
-- line to the same action-dispatch system a keybind uses -- confirmed
-- against the engine's own chat-handling source, CGame::ProcessAction ->
-- GotChatMsg -> the widget's registered action of the same name -- so no
-- separate chat-parsing code is needed here, just three more
-- widgetHandler:AddAction calls).
--
--   /conefirehide      -- turns ON auto-hide: any unit's cone illustration
--                         (wedge/line/labels) hides itself the instant
--                         that unit starts actively engaging something,
--                         and reappears the instant it goes idle again.
--                         Purely visual -- never touches enforcement.
--   /conefireon        -- the default -- cone illustrations are always
--                         shown, regardless of whether a unit is firing.
--   /conefiredisable   -- removes EVERY unit's cone-of-fire config
--                         entirely, all at once -- the same thing clicking
--                         the small red "X" does for one unit at a time,
--                         just for the whole match in one command.
--   /conefirewedge     -- build zw: toggles the red aim-sweep wedge (the
--                         "still turning to face its target" indicator,
--                         see simulatedAimAngle/DrawAimSweep) on/off for
--                         every unit at once. On by default.
--   /conefiredefault   -- build zx: resets /conefirehide-vs-on and
--                         /conefirewedge back to their original defaults
--                         (always shown, wedge on) in one command.
--
-- build zx: the /conefirehide-vs-on and /conefirewedge settings above are
-- now SAVED across sessions (widget:GetConfigData/SetConfigData, BAR's
-- standard per-widget settings persistence) -- they used to silently
-- reset to their defaults on every reload/restart.
local function ConeFireOff()
    autoHideGuiWhileFiring = true
    spEcho("[Cone-of-Fire] /conefirehide -- cone illustration will now hide itself on any unit actively firing (reappears once it goes idle). Type /conefireon to go back to always showing it.")
end

local function ConeFireOn()
    autoHideGuiWhileFiring = false
    spEcho("[Cone-of-Fire] /conefireon -- cone illustration is always shown again (the default).")
end

local function ConeFireDisableAll()
    local count = 0
    for unitID in pairs(arcConfig) do
        arcConfig[unitID] = nil
        RestoreFireStateIfSuppressed(unitID)
        count = count + 1
    end
    ForceCommandPanelRefresh()
    spEcho(string.format("[Cone-of-Fire] /conefiredisable -- removed cone-of-fire from %d unit(s). Ctrl+C to set any of them back up.", count))
end

-- build zw, per the user: "/conefirewedge" -- toggles the red aim-sweep
-- wedge (see showAimSweepWedge's own declaration above) on/off. On by
-- default; typing it again switches it back.
local function ConeFireWedgeToggle()
    showAimSweepWedge = not showAimSweepWedge
    if showAimSweepWedge then
        spEcho("[Cone-of-Fire] /conefirewedge -- red aim-sweep wedge is now ON (the default). Type it again to turn it off.")
    else
        spEcho("[Cone-of-Fire] /conefirewedge -- red aim-sweep wedge is now OFF. Type it again to turn it back on.")
    end
end

-- build zx, per the user (after learning the two settings above now
-- persist across sessions via GetConfigData/SetConfigData -- see those
-- callins near widget:Initialize below -- "lets go and also add another
-- /chat command /conefiredefault which sets it at origina default"):
-- resets every chat-toggleable setting back to its ORIGINAL out-of-the-box
-- default in one shot, regardless of whatever got saved from a previous
-- session -- cone illustration always shown (same as /conefireon) and the
-- aim-sweep wedge on (same as /conefirewedge if it was off).
local function ConeFireResetDefaults()
    autoHideGuiWhileFiring = false
    showAimSweepWedge = true
    spEcho("[Cone-of-Fire] /conefiredefault -- all chat-toggleable settings reset to their original defaults (cone illustration always shown, aim-sweep wedge on).")
end

--------------------------------------------------------------------------------
-- TOGGLE-SWITCH HIT TESTING (world-anchored screen overlay)
--------------------------------------------------------------------------------
-- Returns screen-space rx1,ry1,rx2,ry2 for the world-anchored "X" button --
-- the only remaining per-unit screen control (2026-09-02: the separate
-- On/Pause toggle switch was removed per the user -- "remove the icon on
-- and pause, leave X there so it[']s a way to disable cone of fire control
-- on that unit." X now sits directly under the unit at the switch's old
-- screen offset, rather than off to the side of a switch that no longer
-- exists, and remains the single way to turn Cone-of-Fire off for a unit
-- (removes its saved config entirely -- Ctrl+C sets it back up from
-- scratch, same as always).
--
-- Rewritten 2026-09-03: anchored in WORLD space now, not screen space. The
-- user's own screenshots showed the old fixed-pixel offset (SWITCH_OFFSET_Y)
-- looking right zoomed out but drifting up into the middle of the unit
-- model when zoomed in close -- a constant screen-pixel offset from the
-- projected anchor point doesn't grow along with the unit's on-screen size
-- as the camera moves closer, so it increasingly undershoots the model's
-- actual (now much taller on screen) base. The fix: pick a point in WORLD
-- space that's actually just past the unit's real base -- ground height
-- directly under it, offset toward the camera (+Z, this file's existing
-- "south/front" convention -- see the 0-degree reference tick in
-- DrawAngleReferenceLabels) by the unit's own collision radius
-- (Spring.GetUnitRadius) plus a small margin -- and project THAT single
-- world point to screen coordinates. Because it's the engine's own
-- perspective projection doing the scaling now, not a manual pixel fudge,
-- the button tracks the unit's true rendered base correctly at every zoom
-- level, the same way the model itself does.
-- Shared by GetSwitchScreenRect and GetHelpScreenRect (build zo) -- the
-- single world-anchored screen point both buttons are laid out from, so
-- they always stay glued together at every zoom level.
local function GetButtonAnchorScreen(unitID)
    local ux, uy, uz = spGetUnitPosition(unitID)
    if not ux then return nil end
    local groundY = spGetGroundHeight(ux, uz) or uy
    local radius = spGetUnitRadius(unitID) or 40 -- fallback for the rare case the engine can't report it
    local ax, az = ux, uz + radius + REMOVE_BUTTON_GROUND_MARGIN
    local sx, sy, sz = spWorldToScreenCoords(ax, groundY, az)
    if not sx or (sz and sz < 0) then return nil end -- behind camera
    return sx, sy
end

local function GetSwitchScreenRect(unitID)
    local cx, cy = GetButtonAnchorScreen(unitID)
    if not cx then return nil end
    local rx1 = cx - REMOVE_W * 0.5
    local rx2 = cx + REMOVE_W * 0.5
    local ry1 = cy - REMOVE_H * 0.5
    local ry2 = cy + REMOVE_H * 0.5
    return rx1, ry1, rx2, ry2
end

-- build zo: the "?" button sits immediately to the right of "X", laid out
-- from the exact same world anchor so it tracks it perfectly at any zoom.
local function GetHelpScreenRect(unitID)
    local cx, cy = GetButtonAnchorScreen(unitID)
    if not cx then return nil end
    local hcx = cx + REMOVE_W * 0.5 + HELP_BUTTON_GAP_PX + HELP_W * 0.5
    local rx1 = hcx - HELP_W * 0.5
    local rx2 = hcx + HELP_W * 0.5
    local ry1 = cy - HELP_H * 0.5
    local ry2 = cy + HELP_H * 0.5
    return rx1, ry1, rx2, ry2
end

--------------------------------------------------------------------------------
-- CALLINS
--------------------------------------------------------------------------------
function widget:Initialize()
    spEcho("[Cone-of-Fire] Loaded, build " .. WIDGET_BUILD .. ".")
    local missing = {}
    for name in pairs(ARC_UNIT_NAMES) do
        local ud = UnitDefNames[name]
        if ud then
            arcUnitDefIDs[ud.id] = true
        else
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        spEcho("[Cone-of-Fire] Warning: unit def(s) not found, skipped: " .. table.concat(missing, ", "))
    end

    widgetHandler:AddAction("conefire_togglemode", ToggleMode, nil, "p")
    if #Spring.GetActionHotKeys("conefire_togglemode") == 0 then
        Spring.SendCommands("bind ctrl+c conefire_togglemode")
    end

    -- build zi: three chat commands (typed directly, e.g. "/conefirehide"
    -- in the chat box -- no keybind needed, see the CHAT COMMANDS section
    -- above for how/why typing "/actionname" reaches these same
    -- functions).
    --
    -- build zm FIX: the trailing "types" string on AddAction is NOT just
    -- keypress-state flags ("p"=press/"r"=release/"R"=repeat) -- "t" is a
    -- SEPARATE flag that opts the action into typed-chat/console dispatch
    -- specifically. These three were registered with only "p" (copy-
    -- pasted from conefire_togglemode, which is genuinely keybind-only),
    -- which is why they silently never fired from chat -- confirmed
    -- directly against gui_eco_graph.lua's own working /ecograph* chat
    -- commands, which all use "t". Switched to "t" here; conefire_togglemode
    -- correctly stays "p" since it's Ctrl+C-only by design, never meant to
    -- be typed.
    widgetHandler:AddAction("conefirehide", ConeFireOff, nil, "t")
    widgetHandler:AddAction("conefireon", ConeFireOn, nil, "t")
    widgetHandler:AddAction("conefiredisable", ConeFireDisableAll, nil, "t")
    widgetHandler:AddAction("conefirewedge", ConeFireWedgeToggle, nil, "t")
    widgetHandler:AddAction("conefiredefault", ConeFireResetDefaults, nil, "t")
end

-- build zx, per the user ("those chat commanders are persistent?" -- they
-- were NOT: autoHideGuiWhileFiring/showAimSweepWedge were plain runtime
-- locals with no save/load hook, so they silently reset to their defaults
-- on every widget reload/game restart. GetConfigData/SetConfigData is
-- BAR's/Spring's standard per-widget settings-persistence mechanism --
-- widgetHandler calls GetConfigData to collect what to save (on game
-- exit/widget removal/etc.) and calls SetConfigData with whatever was
-- saved last time, right as this widget instance is created, before
-- widget:Initialize runs. Only these two settings are persisted --
-- everything else (arcConfig, the actual deployed cones) is inherently
-- per-match, tied to that match's own unit IDs, and was never a candidate
-- for this.
function widget:GetConfigData()
    return {
        autoHideGuiWhileFiring = autoHideGuiWhileFiring,
        showAimSweepWedge = showAimSweepWedge,
    }
end

function widget:SetConfigData(data)
    if not data then return end
    -- ~= nil (not a truthy check) so an explicitly-saved `false` is
    -- correctly restored, not silently coerced back to the default.
    if data.autoHideGuiWhileFiring ~= nil then
        autoHideGuiWhileFiring = data.autoHideGuiWhileFiring
    end
    if data.showAimSweepWedge ~= nil then
        showAimSweepWedge = data.showAimSweepWedge
    end
end

function widget:Shutdown()
    widgetHandler:RemoveAction("conefire_togglemode")
    widgetHandler:RemoveAction("conefirehide")
    widgetHandler:RemoveAction("conefireon")
    widgetHandler:RemoveAction("conefiredisable")
    widgetHandler:RemoveAction("conefirewedge")
    widgetHandler:RemoveAction("conefiredefault")
    -- Don't leave any unit stuck on a forced Hold Fire if the widget gets
    -- disabled/reloaded while actively suppressing one.
    for unitID in pairs(suppressedFireState) do
        RestoreFireStateIfSuppressed(unitID)
    end
end

function widget:UnitDestroyed(unitID)
    arcConfig[unitID] = nil
    pendingDraft[unitID] = nil
    lastStopEchoFrame[unitID] = nil
    -- currentActionKind/currentActionTargetID/currentActionPos/
    -- lastActionFrame/ghostContact are all cleared inside
    -- RestoreFireStateIfSuppressed below (it also issues the final Stop --
    -- see its build-n comment for why that's needed here specifically).
    RestoreFireStateIfSuppressed(unitID)
    if modeUnitID == unitID then
        CancelMode()
    end
end

-- build zv, replacing the removed IsWeaponAngleGood (see simulatedAimAngle's
-- own declaration above for why angleGood turned out to be unreliable for
-- this). Did weapon `weaponNum` just, this frame, actually fire a real
-- shot? true/false. Detected via Spring.GetUnitWeaponState's "reloadFrame"
-- (weapon->reloadStatus, confirmed rts/Lua/LuaSyncedRead.cpp -- the sim
-- frame the weapon becomes ready to fire again): that value only ever
-- jumps FORWARD past the current frame at the exact moment a shot is
-- committed (a fresh reload countdown starts) -- comparing it against what
-- was last observed for this unit catches that jump. This is ground
-- truth, not an approximation: the engine's own CanFire gate (which
-- genuinely does include the real angleGood/reload/salvo/etc. checks) had
-- to have passed for the shot to happen at all, so the instant one is
-- detected, the turret is unambiguously known to have really been aimed
-- correctly right then.
local function HasWeaponJustFired(unitID, weaponNum)
    local reloadFrame = spGetUnitWeaponState(unitID, weaponNum, "reloadFrame")
    if not reloadFrame then return false end
    local prev = lastReloadFrame[unitID]
    lastReloadFrame[unitID] = reloadFrame
    if not prev then return false end -- first observation -- nothing to compare against yet
    local n = Spring.GetGameFrame()
    return reloadFrame > prev and reloadFrame > n
end

-- build zy, per the user: "sometimes the wedge is moving opposite of the
-- turret although eventually they both terminate at the same spot ...
-- make the widget spot if available a targeteable structure that's not
-- in the cone and make that the a marker (to fix direction of the red
-- wedge)". The build-zt hull-facing guess (below) is only ever an
-- approximation of the turret's TRUE resting orientation, which can
-- genuinely differ from hull facing -- e.g. Fire-at-Will may already have
-- had the weapon locked onto something (anywhere, not necessarily inside
-- the cone about to be drawn) the instant before Cone-of-Fire took over.
-- When that happens, seeding from hull-facing can start the simulated
-- sweep on the WRONG side of the real turret's actual current angle, so
-- while the assumed turn rate still eventually walks it to the same
-- final target bearing, it visibly rotates the opposite way from the
-- real turret in between.
--
-- Spring.GetUnitWeaponTarget (already aliased as spGetUnitWeaponTarget,
-- used elsewhere in this file for the periodic status diagnostic) reads
-- the weapon's OWN actual live target -- per the engine's own doc
-- comment, "doesn't need to reflect the unit's Attack orders or such" --
-- i.e. ground truth for whatever the barrel is really doing RIGHT NOW,
-- independent of any order this widget itself just issued. If it's
-- currently locked onto some real unit or ground spot that ISN'T the
-- exact target we're about to command it to attack (the "structure not
-- in the cone" the user described -- it doesn't actually need to be
-- checked against the cone geometry specifically, just needs to be a
-- DIFFERENT real thing than our new target, which is proof the turret is
-- genuinely aimed somewhere else right now), that's a real marker for
-- where the turret truly is -- far better than guessing from hull facing.
-- Returns a bearing (radians), or nil if there's no live target right
-- now (a genuinely idle/fresh weapon, hull facing remains the best
-- available guess) or its live target IS the one we're about to command
-- anyway (tells us nothing we don't already know).
local function GetRealWeaponAimBearing(unitID, ux, uz, excludeUnitID)
    local targType, _, arg = spGetUnitWeaponTarget(unitID, 1)
    if targType == 1 then -- locked onto a real unit
        if not arg or arg == excludeUnitID or not spValidUnitID(arg) then return nil end
        local tux, _, tuz = spGetUnitPosition(arg)
        if not tux then return nil end
        return BearingTo(ux, uz, tux, tuz)
    elseif targType == 2 then -- locked onto a ground/pos spot -- arg is {x, y, z}
        if not arg then return nil end
        return BearingTo(ux, uz, arg[1], arg[3])
    end
    return nil -- Target_None (0) or a projectile-intercept lock (3) -- no usable marker
end

-- build zs: advances simulatedAimAngle (declared above) toward each
-- actively-engaged unit's real target bearing, at the assumed
-- AIM_SWEEP_TURN_RATE_RAD_PER_SEC. build zv: snaps early only on a
-- confirmed real fire event (HasWeaponJustFired) rather than the engine's
-- misleading `angleGood` flag -- see simulatedAimAngle's declaration above
-- for why that changed. Runs every widget:Update regardless of setup
-- mode -- unlike the rest of that callin, this has nothing to do with the
-- live setup preview.
local function UpdateSimulatedAimAngles(dt)
    for unitID, cfg in pairs(arcConfig) do
        if spValidUnitID(unitID) then
            local kind = currentActionKind[unitID]
            if kind == "unit" or kind == "ground" then
                local ux, uy, uz = spGetUnitPosition(unitID)
                if ux then
                    local tx, tz, tid
                    if kind == "unit" then
                        tid = currentActionTargetID[unitID]
                        if tid and spValidUnitID(tid) then
                            local tux, _, tuz = spGetUnitPosition(tid)
                            tx, tz = tux, tuz
                        end
                    else
                        local p = currentActionPos[unitID]
                        if p then tx, tz = p.x, p.z end
                    end
                    if tx then
                        local targetBearing = BearingTo(ux, uz, tx, tz)
                        local current = simulatedAimAngle[unitID]
                        if not current then
                            -- build zy fix: check for a real, live marker
                            -- first (see GetRealWeaponAimBearing above)
                            -- before falling back to the hull-facing
                            -- guess.
                            current = GetRealWeaponAimBearing(unitID, ux, uz, tid)
                            if not current then
                                -- build zt fix, per the user ("its now
                                -- showing any wedge though"): the very
                                -- first engagement ever is the MOST
                                -- common case a player actually watches
                                -- (a freshly-deployed unit swinging onto
                                -- its first target) -- but starting the
                                -- simulation already aligned (the old
                                -- behavior) meant it could NEVER show a
                                -- gap for that first engagement, only on
                                -- a later retarget. Start it from the
                                -- unit's own hull facing instead (the
                                -- turret's resting orientation on a
                                -- freshly-built/idle unit is usually
                                -- close to this) -- an approximation like
                                -- everything else here, but one that
                                -- actually produces a visible sweep on a
                                -- fresh engagement instead of guaranteeing
                                -- none.
                                local fx, _, fz = spGetUnitDirection(unitID)
                                current = fx and BearingTo(0, 0, fx, fz) or targetBearing
                            end
                        end
                        local justFired = HasWeaponJustFired(unitID, 1)
                        if justFired then
                            current = targetBearing -- a real shot just confirmed the aim was good -- snap
                        else
                            local diff = NormalizeAngle(targetBearing - current)
                            local maxStep = AIM_SWEEP_TURN_RATE_RAD_PER_SEC * dt
                            if math.abs(diff) <= maxStep then
                                current = targetBearing
                            else
                                current = NormalizeAngle(current + (diff > 0 and maxStep or -maxStep))
                            end
                        end
                        simulatedAimAngle[unitID] = current
                    end
                end
            end
        end
    end
end

-- Live preview tracking: follows the mouse every frame while in angle/range
-- setup, without needing the button held down (matches the "aim with the
-- mouse, wheel adjusts width, LMB just confirms" flow the user described).
function widget:Update(dt)
    UpdateSimulatedAimAngles(dt)

    if mode == MODE_NONE or not modeUnitID then return end
    if not spValidUnitID(modeUnitID) then
        CancelMode()
        return
    end
    local ux, uy, uz = spGetUnitPosition(modeUnitID)
    if not ux then return end
    local gx, gy, gz = GetMouseGroundPos()
    if not gx then return end

    if mode == MODE_ANGLE then
        previewAngle = BearingTo(ux, uz, gx, gz)
    elseif mode == MODE_RANGE then
        local dx, dz = gx - ux, gz - uz
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < MIN_RANGE_CAP then dist = MIN_RANGE_CAP end
        if dist > modeNativeRange then dist = modeNativeRange end
        previewRangeCap = dist
    end
end

function widget:MouseWheel(up, value)
    if mode == MODE_ANGLE then
        -- build zc, per the user (set WHEEL_STEP_DEG to 15, actual change
        -- per scroll read as ~6; set it to 10, actual change read as
        -- ~16 -- inconsistent in both directions, so not a simple wrong-
        -- constant bug): this previously ignored `value` and applied
        -- exactly one WHEEL_STEP per call to widget:MouseWheel. But the
        -- engine's own callin doc (Callins:MouseWheel, LuaHandle.cpp) is
        -- explicit that `value` is "the amount travelled," not a fixed
        -- 1.0-per-notch flag -- confirmed further from the engine's own
        -- camera code (MouseHandler.cpp), which scales camera movement by
        -- this same raw value (`delta * scrollWheelSpeed`) rather than
        -- treating every call as one fixed unit. Different input devices
        -- (a standard wheel, a free-spin wheel, a trackpad's simulated
        -- wheel) report very different magnitudes per physical scroll, and
        -- can fire this callin more than once for what feels like a single
        -- gesture -- so a fixed "1 step per call" reliably drifted from
        -- the configured WHEEL_STEP_DEG depending on hardware, matching
        -- both directions of the user's report. Scaling by the actual
        -- reported magnitude (`math.abs(value)`) instead keeps the
        -- on-screen change matching WHEEL_STEP_DEG regardless of what's
        -- doing the scrolling.
        local delta = WHEEL_STEP * math.abs(value or 1)
        if up then
            previewHalfWidth = previewHalfWidth - delta
        else
            previewHalfWidth = previewHalfWidth + delta
        end
        if previewHalfWidth < MIN_HALF_WIDTH then previewHalfWidth = MIN_HALF_WIDTH end
        if previewHalfWidth > MAX_HALF_WIDTH then previewHalfWidth = MAX_HALF_WIDTH end
        return true
    elseif mode == MODE_RANGE then
        -- Not used for range (that's mouse-position-driven), but still eat
        -- the scroll so the camera doesn't zoom out from under the player
        -- mid-setup.
        return true
    end
    return false
end

function widget:MousePress(mx, my, button)
    -- build zt: the help panel's own "X" close button -- checked first,
    -- above everything else, so it always works regardless of setup mode
    -- or whether any unit still has a "?" of its own left to click (see
    -- helpPanelCloseRect's declaration for the exact bug this fixes).
    if button == 1 and showControlsHelp and helpPanelCloseRect then
        local r = helpPanelCloseRect
        if mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2 then
            showControlsHelp = false
            spEcho("[Cone-of-Fire] Controls help closed.")
            return true
        end
    end

    if mode == MODE_ANGLE then
        if button == 1 then
            local ux, uy, uz = spGetUnitPosition(modeUnitID)
            modeNativeRange = GetWeaponRange(spGetUnitDefID(modeUnitID))
            pendingDraft[modeUnitID] = {
                angle = previewAngle,
                halfWidth = previewHalfWidth,
            }
            previewRangeCap = modeNativeRange
            mode = MODE_RANGE
            spEcho("[Cone-of-Fire] Select range/distance limit: left-click mouse.")
        elseif button == 3 then
            CancelMode()
        end
        return true
    elseif mode == MODE_RANGE then
        if button == 1 then
            -- No separate "Deploy" step -- per the user, locking the range
            -- should be the final step: it goes live immediately. What the
            -- unit does with it after that (Fire-at-Will, Hold Fire, Return
            -- Fire) is entirely up to whatever fire-state the player sets
            -- normally; the cone/range restriction applies underneath all
            -- three regardless, unaffected by fire-state changes.
            local draft = pendingDraft[modeUnitID]
            if draft then
                draft.rangeCap = previewRangeCap
            end
            local unitID = modeUnitID
            local group = modeGroupUnitIDs
            mode = MODE_NONE
            modeUnitID = nil
            modeGroupUnitIDs = nil
            local ok = DeployDraft(unitID)

            -- build ze: linked-group deploy. If more than one unit was
            -- selected when this setup session began (see ToggleMode/
            -- EnterAngleMode), every OTHER unit in that group now gets its
            -- own derived angle/halfWidth/rangeCap so its cone's edges
            -- land on the exact same two shared world points as `unitID`'s
            -- cone -- "shares exactly the final cone and range," per the
            -- user, generalized to any group size the same way. Uses
            -- `draft` (not arcConfig[unitID]) for the reference angle/
            -- halfWidth/rangeCap since it's already right here with no
            -- extra lookup needed, and DeployDraft above just committed
            -- that exact same data into arcConfig[unitID] anyway.
            local linkedCount = 0
            if ok and draft and group and #group > 1 then
                local rux, ruy, ruz = spGetUnitPosition(unitID)
                if rux then
                    local lx, lz, rx, rz = GetConeEdgePoints(rux, ruz, draft.angle, draft.halfWidth, draft.rangeCap)
                    for i = 1, #group do
                        local otherID = group[i]
                        if otherID ~= unitID and spValidUnitID(otherID) then
                            local ox, oy, oz = spGetUnitPosition(otherID)
                            if ox then
                                local nativeRange = GetWeaponRange(spGetUnitDefID(otherID))
                                local oAngle, oHalfWidth, oRangeCap = DeriveLinkedCone(ox, oz, nativeRange, lx, lz, rx, rz)
                                pendingDraft[otherID] = { angle = oAngle, halfWidth = oHalfWidth, rangeCap = oRangeCap }
                                if DeployDraft(otherID) then
                                    linkedCount = linkedCount + 1
                                end
                            end
                        end
                    end
                end
            end

            if ok then
                if linkedCount > 0 then
                    spEcho(string.format(
                        "[Cone-of-Fire] Active on %d units -- shared cone/range, each angled for its own position. Fire-at-Will enabled on all of them, restricted to the shared cone.",
                        linkedCount + 1))
                else
                    spEcho("[Cone-of-Fire] Active -- Fire-at-Will enabled, restricted to the cone. Switch to Hold Fire/Return Fire any time; the restriction still applies underneath whichever you pick.")
                end
            end
        elseif button == 3 then
            -- build zq, per the user ("right click, goes back create
            -- cone (right click twice cancels all)"): right-click during
            -- the RANGE step now steps back to the ANGLE step instead of
            -- cancelling the whole setup outright. previewAngle/
            -- previewHalfWidth are only ever touched by the ANGLE step
            -- (see widget:MouseMove/MouseWheel above), so they're still
            -- exactly where the player left them -- switching the stage
            -- back is all that's needed, no state to restore. A second
            -- right-click, now back in MODE_ANGLE, hits the branch above
            -- and cancels for real, same as it always has.
            mode = MODE_ANGLE
            spEcho("[Cone-of-Fire] Back to cone width -- scroll wheel to adjust, left-click to set. Right-click again to cancel entirely.")
        end
        return true
    end

    -- Not in setup mode: check the world-anchored "X" button (the sole
    -- remaining per-unit screen control -- see GetSwitchScreenRect).
    if button == 1 then
        for unitID, cfg in pairs(arcConfig) do
            if spValidUnitID(unitID) then
                local rx1, ry1, rx2, ry2 = GetSwitchScreenRect(unitID)
                if rx1 and mx >= rx1 and mx <= rx2 and my >= ry1 and my <= ry2 then
                    -- build zj, per the user (screenshot of a row of 5
                    -- deployed Ragnaroks, each with its own "X"): holding
                    -- Ctrl while clicking ANY "X" clears every cone-of-fire
                    -- config whose "X" is CURRENTLY ON SCREEN, not just the
                    -- one actually clicked -- a fast way to clear a whole
                    -- visible group/base's worth of cones at once instead
                    -- of clicking each one individually. Deliberately
                    -- scoped to on-screen units only (matches "clears all
                    -- Xs" -- the ones the player can actually see right
                    -- now), not literally every configured unit in the
                    -- game -- that's what /conefiredisable (build zi) is
                    -- for. A plain click (no Ctrl) still only removes the
                    -- one unit whose "X" was actually clicked, unchanged.
                    local _, ctrlHeld = spGetModKeyState()
                    if ctrlHeld then
                        local count = 0
                        for otherID in pairs(arcConfig) do
                            if spValidUnitID(otherID) then
                                local orx1 = GetSwitchScreenRect(otherID)
                                if orx1 then
                                    arcConfig[otherID] = nil
                                    RestoreFireStateIfSuppressed(otherID)
                                    count = count + 1
                                end
                            end
                        end
                        ForceCommandPanelRefresh()
                        spEcho(string.format(
                            "[Cone-of-Fire] Ctrl+Click -- removed cone-of-fire from %d on-screen unit(s). Ctrl+C to set any of them back up.",
                            count))
                    else
                        arcConfig[unitID] = nil
                        RestoreFireStateIfSuppressed(unitID)
                        ForceCommandPanelRefresh()
                        spEcho("[Cone-of-Fire] Removed permanently -- run Ctrl+C to set it up again.")
                    end
                    return true
                end

                -- build zo: the "?" button -- toggles the controls-help
                -- panel (see DrawControlsHelpPanel). No Ctrl needed, and
                -- unlike "X" this never touches the unit's config at all.
                local hx1, hy1, hx2, hy2 = GetHelpScreenRect(unitID)
                if hx1 and mx >= hx1 and mx <= hx2 and my >= hy1 and my <= hy2 then
                    showControlsHelp = not showControlsHelp
                    -- build zp, per the user ("make that position aware"):
                    -- remember where THIS "?" was on screen so the panel
                    -- opens next to it instead of always the same fixed
                    -- spot -- see DrawControlsHelpPanel for the clamping
                    -- that keeps it fully on screen from any anchor.
                    helpPanelAnchorX, helpPanelAnchorY = (hx1 + hx2) * 0.5, (hy1 + hy2) * 0.5
                    spEcho("[Cone-of-Fire] Controls help " ..
                        (showControlsHelp and "shown -- click any \"?\" again to close it." or "closed."))
                    return true
                end
            end
        end

        -- build zi: Ctrl+Click directly on an already cone-of-fire-
        -- configured unit's own MODEL (not its "X" button) toggles just
        -- that unit's cone ILLUSTRATION visibility (wedge/line/labels) --
        -- independent of the "X" button, which still always removes the
        -- config entirely regardless of this toggle. Deliberately gated on
        -- Ctrl rather than a plain click: a plain left-click on a unit is
        -- the engine's own normal SELECT action, and hijacking that would
        -- make an already-configured unit impossible to select normally --
        -- Ctrl+Click mirrors this widget's existing Ctrl+C convention
        -- instead of colliding with core unit selection. Only checked once
        -- the "X" buttons above have all missed, so a click that lands on
        -- an "X" is never ambiguous with this.
        local _, ctrlHeldOnUnit = spGetModKeyState()
        if ctrlHeldOnUnit then
            local typ, hitUnitID = spTraceScreenRay(mx, my, false)
            if typ == "unit" and hitUnitID then
                local cfg = arcConfig[hitUnitID]
                if cfg then
                    -- build zm fix: override relative to what's actually
                    -- on screen RIGHT NOW (which may currently be hidden
                    -- only because of "/conefirehide" auto-hide, not a
                    -- prior manual override) rather than blindly flipping
                    -- guiOverride -- see ShouldShowConeGui above for why.
                    local currentlyShown = ShouldShowConeGui(hitUnitID, cfg)
                    cfg.guiOverride = currentlyShown
                    spEcho(string.format(
                        "[Cone-of-Fire] Ctrl+Click on unit %d -- cone illustration %s.",
                        hitUnitID, currentlyShown and "hidden (Ctrl+Click again to show it)" or "shown again (stays shown even while firing, until Ctrl+Click again)"))
                    return true
                end
            end
        end
    end

    return false
end

function widget:KeyPress(key, mods, isRepeat)
    if mode == MODE_NONE then return false end
    -- 27 = SDL/ASCII escape keycode.
    if key == 27 then
        if isRepeat then return true end
        local now = Spring.GetGameSeconds and Spring.GetGameSeconds() or os.clock()
        if lastEscapeTime and (now - lastEscapeTime) <= ESCAPE_DOUBLE_TAP_WINDOW then
            CancelMode()
            lastEscapeTime = nil
        else
            lastEscapeTime = now
            spEcho("[Cone-of-Fire] Press Escape again to cancel.")
        end
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- COMMAND PANEL
--------------------------------------------------------------------------------
function widget:CommandsChanged()
    local sel = spGetSelectedUnits()
    if #sel ~= 1 then return end
    local unitID = sel[1]
    local unitDefID = spGetUnitDefID(unitID)
    if not IsArcUnit(unitDefID) then return end

    -- widgetHandler.customCommands isn't guaranteed to already be a table
    -- when CommandsChanged fires (confirmed in-game: "attempt to get length
    -- of local 'customCommands' (a nil value)") -- lazily create it rather
    -- than assume the handler pre-populated it.
    if not widgetHandler.customCommands then
        widgetHandler.customCommands = {}
    end
    local customCommands = widgetHandler.customCommands

    -- No more "pending draft waiting for a Deploy click" state -- locking
    -- the range now activates the cone immediately (per the user, 2026-09-02
    -- follow-up: a separate Deploy step wasn't wanted), so there's nothing
    -- left for a Deploy/Cancel pair of buttons to do here.
    if arcConfig[unitID] then
        customCommands[#customCommands + 1] = {
            id = CMD_FIREARC_SETUP,
            type = CMDTYPE.ICON,
            name = 'Reconfigure Arc',
            tooltip = 'Redraw the cone-of-fire (Ctrl+C)',
            action = 'firearc_setup',
        }
        customCommands[#customCommands + 1] = {
            id = CMD_FIREARC_UNDEPLOY,
            type = CMDTYPE.ICON,
            name = 'Remove Permanently',
            tooltip = 'Delete this cone-of-fire config entirely (same as the small remove button next to the On/Pause switch) -- you\'ll need to run Ctrl+C again to set it back up',
            action = 'firearc_undeploy',
        }
    else
        customCommands[#customCommands + 1] = {
            id = CMD_FIREARC_SETUP,
            type = CMDTYPE.ICON,
            name = 'Cone-of-Fire',
            tooltip = 'Draw a cone-of-fire + range restriction (Ctrl+C)',
            action = 'firearc_setup',
        }
    end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    local sel = spGetSelectedUnits()
    local unitID = sel[1]

    if cmdID == CMD_FIREARC_SETUP then
        if unitID and IsArcUnit(spGetUnitDefID(unitID)) then
            EnterAngleMode(unitID)
        end
        return true
    elseif cmdID == CMD_FIREARC_UNDEPLOY then
        if unitID then
            arcConfig[unitID] = nil
            RestoreFireStateIfSuppressed(unitID)
        end
        spEcho("[Cone-of-Fire] Removed permanently -- run Ctrl+C to set it up again.")
        ForceCommandPanelRefresh()
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- ENFORCEMENT (the actual friendly-fire guard)
--------------------------------------------------------------------------------
-- Rewritten 2026-09-03 (build n). See the build-n DESIGN NOTES entry near
-- the top of this file for the full rationale and the engine-source
-- findings behind it. Short version: builds h-m all tried to gate NATIVE
-- Fire-at-Will/AutoTarget from picking a bad target -- but fireState can
-- only ever block AutoTarget's own fresh-target search, never choose which
-- target it picks, so every version of that approach could only react to
-- AutoTarget's choice after the fact. This version doesn't gate AutoTarget
-- at all: it leaves the unit on Hold Fire permanently (set once, at
-- Deploy) and does 100% of the actual targeting itself, via explicit
-- CMD.ATTACK orders -- which fire regardless of fireState (confirmed from
-- CWeapon::CanFire never reading owner->fireState). There is no longer a
-- "gate" to flap open and closed, so RELOCK_GRACE_FRAMES/
-- RETRY_COOLDOWN_FRAMES/NO_TARGET_GRACE_FRAMES and their state are gone.
-- (STOP_ECHO_THROTTLE_FRAMES itself now lives in the USER-TWEAKABLE
-- SETTINGS block near the top of this file.)

-- Finds the closest enemy or neutral unit this widget can CURRENTLY see
-- (Spring.GetUnitsInCylinder only ever returns units the local team
-- currently has in LOS or on radar -- confirmed from
-- rts/Lua/LuaUtils.cpp::IsUnitVisible -- so this can't leak fog-of-war
-- information) sitting inside the cone+range. Returns the target's unit
-- ID and position, or nil if nothing currently qualifies.
local function FindBestLiveTargetInCone(unitID, cfg, ux, uz)
    local myTeam = Spring.GetUnitTeam(unitID)
    local nearby = Spring.GetUnitsInCylinder(ux, uz, cfg.rangeCap)
    if not nearby then return nil end
    local bestID, bestX, bestY, bestZ, bestDist
    for i = 1, #nearby do
        local otherID = nearby[i]
        if otherID ~= unitID then
            local otherTeam = Spring.GetUnitTeam(otherID)
            -- "Not allied" catches enemies and gaia/neutral critters alike
            -- (both are valid targets) while excluding our own team/allies.
            if otherTeam and myTeam and not Spring.AreTeamsAllied(myTeam, otherTeam) then
                local ox, oy, oz = spGetUnitPosition(otherID)
                if ox then
                    local dx, dz = ox - ux, oz - uz
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist <= cfg.rangeCap then
                        local bearing = BearingTo(ux, uz, ox, oz)
                        local diff = NormalizeAngle(bearing - cfg.angle)
                        if math.abs(diff) <= cfg.halfWidth then
                            if not bestDist or dist < bestDist then
                                bestID, bestX, bestY, bestZ, bestDist = otherID, ox, oy, oz, dist
                            end
                        end
                    end
                end
            end
        end
    end
    return bestID, bestX, bestY, bestZ
end

local function EnforceArcOnUnit(unitID, cfg, n)
    if not cfg.enabled then
        RestoreFireStateIfSuppressed(unitID)
        return
    end
    if not spValidUnitID(unitID) then
        arcConfig[unitID] = nil
        RestoreFireStateIfSuppressed(unitID)
        return
    end

    local ux, uy, uz = spGetUnitPosition(unitID)
    if not ux then return end

    -- Step 1: what SHOULD this unit be doing right now?
    --   "unit"   -- a real, currently-visible enemy sits inside the cone+
    --              range. Always the first choice when one exists.
    --   "ground" -- nothing is currently visible in the cone, but this
    --              widget itself confirmed something there within the last
    --              GHOST_MEMORY_FRAMES -- attack that remembered spot, the
    --              same way a player attacks a ghost building icon on their
    --              own screen. This is the "or has been in LOS previously"
    --              case the user asked for.
    --   "none"   -- neither -- hold position, don't fire.
    local liveID, lx, ly, lz = FindBestLiveTargetInCone(unitID, cfg, ux, uz)

    local wantKind, wantID, wantX, wantY, wantZ

    if liveID then
        wantKind, wantID = "unit", liveID
        -- Refresh ghost memory with this real, currently-confirmed sighting
        -- -- this IS the fallback data GHOST_MEMORY_FRAMES draws from once
        -- nothing is live any more.
        ghostContact[unitID] = { x = lx, y = ly, z = lz, frame = n }
    else
        local ghost = ghostContact[unitID]
        if ghost and (n - ghost.frame) < GHOST_MEMORY_FRAMES then
            local dx, dz = ghost.x - ux, ghost.z - uz
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist <= cfg.rangeCap then
                local bearing = BearingTo(ux, uz, ghost.x, ghost.z)
                local diff = NormalizeAngle(bearing - cfg.angle)
                if math.abs(diff) <= cfg.halfWidth then
                    wantKind, wantX, wantY, wantZ = "ground", ghost.x, ghost.y, ghost.z
                end
            end
        end
    end

    if not wantKind then
        wantKind = "none"
    end

    -- Step 2: does that differ from what's already commanded? Orders are
    -- real network packets (see the build-i/k DESIGN NOTES on
    -- GiveOrderToUnit) so this only issues one on an actual change, plus a
    -- rare ATTACK_REFRESH_FRAMES safety-net re-affirmation -- never every
    -- frame, so this shouldn't reproduce the order-spam "clicking" failure
    -- mode from earlier builds.
    local curKind = currentActionKind[unitID]
    local changed
    if curKind ~= wantKind then
        changed = true
    elseif wantKind == "unit" then
        changed = currentActionTargetID[unitID] ~= wantID
    elseif wantKind == "ground" then
        local p = currentActionPos[unitID]
        changed = not p or math.abs(p.x - wantX) > GROUND_POS_EPS or math.abs(p.z - wantZ) > GROUND_POS_EPS
    else
        changed = false
    end

    local dueForRefresh = lastActionFrame[unitID] and (n - lastActionFrame[unitID]) >= ATTACK_REFRESH_FRAMES

    -- Step 3: act. Issuing CMD.ATTACK (unit or ground) or CMD.STOP with no
    -- SHIFT_KEY option -- exactly what these calls send -- clears the
    -- unit's entire existing command queue and drops any standing attack
    -- target as a side effect (confirmed from
    -- rts/Sim/Units/CommandAI/CommandAI.cpp CCommandAI::GiveCommandReal /
    -- ClearTargetLock), so switching targets never needs a separate Stop
    -- first -- the new order alone cancels the old one.
    if changed or (dueForRefresh and wantKind ~= "none") then
        if wantKind == "unit" then
            local ok = spGiveOrderToUnit(unitID, CMD.ATTACK, {wantID}, {})
            spEcho(string.format(
                "[Cone-of-Fire] Commanding unit %d to Attack in-cone target %d -- GiveOrderToUnit returned: %s",
                unitID, wantID, tostring(ok)))
        elseif wantKind == "ground" then
            local ok = spGiveOrderToUnit(unitID, CMD.ATTACK, {wantX, wantY, wantZ}, {})
            spEcho(string.format(
                "[Cone-of-Fire] Commanding unit %d to Attack-ground at last-known in-cone contact (%.0f, %.0f) -- GiveOrderToUnit returned: %s",
                unitID, wantX, wantZ, tostring(ok)))
        else
            local ok = spGiveOrderToUnit(unitID, CMD.STOP, {}, {})
            spEcho(string.format(
                "[Cone-of-Fire] Nothing in cone for unit %d -- issuing Stop -- GiveOrderToUnit returned: %s",
                unitID, tostring(ok)))
        end
        currentActionKind[unitID] = wantKind
        currentActionTargetID[unitID] = (wantKind == "unit") and wantID or nil
        currentActionPos[unitID] = (wantKind == "ground") and { x = wantX, y = wantY, z = wantZ } or nil
        lastActionFrame[unitID] = n
    end

    -- Periodic (throttled) status diagnostic, purely informational: cross-
    -- checks what this widget commanded against what the unit's weapon(s)
    -- actually show as locked, so any mismatch between "what we told it to
    -- do" and "what's actually happening" is visible in the next log --
    -- the same kind of live cross-check that found every real bug in the
    -- old design.
    if not lastStopEchoFrame[unitID] or (n - lastStopEchoFrame[unitID]) >= STOP_ECHO_THROTTLE_FRAMES then
        lastStopEchoFrame[unitID] = n
        local unitDefID = spGetUnitDefID(unitID)
        local ud = UnitDefs[unitDefID]
        local weaponCount = ud and ud.weapons and #ud.weapons or 0
        local lockedTargetID = nil
        for w = 1, weaponCount do
            local targType, _, a = spGetUnitWeaponTarget(unitID, w)
            if targType == 1 then
                lockedTargetID = a
                break
            end
        end
        spEcho(string.format(
            "[Cone-of-Fire] Status for unit %d -- commanded: %s%s, weapon's own live lock: %s",
            unitID, wantKind,
            wantKind == "unit" and (" (unit " .. tostring(wantID) .. ")")
                or wantKind == "ground" and string.format(" (%.0f, %.0f)", wantX, wantZ) or "",
            tostring(lockedTargetID)))
    end
end

function widget:GameFrame(n)
    for unitID, cfg in pairs(arcConfig) do
        EnforceArcOnUnit(unitID, cfg, n)
    end
end

--------------------------------------------------------------------------------
-- DRAWING
--------------------------------------------------------------------------------
local function DrawGroundWedge(ux, uy, uz, angle, halfWidth, radius, r, g, b, a, segments)
    segments = segments or 24
    glColor(r, g, b, a)
    glBeginEnd(GL_TRIANGLE_FAN, function()
        glVertex(ux, uy + 4, uz)
        for i = 0, segments do
            local t = angle - halfWidth + (2 * halfWidth) * (i / segments)
            local px = ux + math.sin(t) * radius
            local pz = uz + math.cos(t) * radius
            local py = (spGetGroundHeight(px, pz) or uy) + 4
            glVertex(px, py, pz)
        end
    end)
end

local function DrawGroundWedgeOutline(ux, uy, uz, angle, halfWidth, radius, r, g, b, a, segments)
    segments = segments or 24
    glColor(r, g, b, a)
    glLineWidth(1.5)
    glBeginEnd(GL_LINE_LOOP, function()
        glVertex(ux, uy + 5, uz)
        for i = 0, segments do
            local t = angle - halfWidth + (2 * halfWidth) * (i / segments)
            local px = ux + math.sin(t) * radius
            local pz = uz + math.cos(t) * radius
            local py = (spGetGroundHeight(px, pz) or uy) + 5
            glVertex(px, py, pz)
        end
    end)
end

-- 2026-09-02 (build j): the user's latest screenshot hand-drew "up" and
-- "right" arrows from their unit and concluded the actual cone (logged as
-- center=45, half-width=45) didn't match -- reasoning from screen-relative
-- compass directions. That reasoning silently assumes the camera is
-- unrotated (screen-up = a fixed world direction) at BOTH the moment the
-- cone was aimed AND the moment of the screenshot -- an assumption this
-- widget never establishes or enforces, and BAR's camera is freely
-- rotatable (drag-rotate), so it's very possible those two moments had
-- different camera headings, making a screen-only comparison unreliable
-- through no fault of the underlying math (already proven self-consistent
-- earlier this session: DrawGroundWedge and BearingTo are exact atan2/
-- sin-cos inverses of one another, so the drawn wedge and the enforcement
-- check can never disagree in WORLD space).
--
-- Fix: stop asking the user to eyeball screen-relative compass directions
-- at all. Draw an extra reference line directly in WORLD space -- the
-- exact same coordinate system and transform as the wedge itself, so
-- whatever the camera is doing, it rotates together with the wedge and a
-- screenshot of it automatically shows correctly aligned:
--   1. CENTERLINE (bright orange, thicker) -- drawn at the cone's own
--      `angle` (its bisector). If this doesn't sit exactly in the visual
--      middle of the wedge, that's a real bug; nothing else it could be.
-- Originally a second, cyan ZERO-REFERENCE tick was also drawn at angle=0
-- (pure +Z, the same convention BearingTo/the logged cone-center number
-- already use) with its own "0 deg (ref)" label, so the logged degree
-- numbers could be checked directly on screen without assuming which way
-- the camera happens to be facing. Removed in build v, per the user: the
-- centerline's own "N deg (cone center)" label already states the number
-- on its own, so the separate 0-deg tick was redundant clutter, not extra
-- information -- see the build-v DESIGN NOTES entry near the top of the
-- file. Only the centerline gets a screen-projected text label now
-- (DrawAngleReferenceLabels below, called from DrawScreen).
local ANGLE_REF_TICK_LENGTH = 500 -- elmos; short and fixed regardless of rangeCap, it's a reference tick, not meant to span the whole cone

local function DrawAngleLine(ux, uy, uz, angle, length, r, g, b, a, width)
    local px = ux + math.sin(angle) * length
    local pz = uz + math.cos(angle) * length
    local py = (spGetGroundHeight(px, pz) or uy) + 6
    glColor(r, g, b, a)
    glLineWidth(width)
    glBeginEnd(GL_LINES, function()
        glVertex(ux, uy + 6, uz)
        glVertex(px, py, pz)
    end)
end

-- build zs, replacing the build-zr straight aim line (per the user:
-- "this one is useless"). Draws a small red filled wedge -- two
-- converging lines from the unit, like the picture the user described --
-- spanning from `simulatedAimAngle[unitID]` (this widget's own
-- self-tracked estimate of the current turret bearing) to the real
-- target bearing, so the player sees an actual shrinking gap as the
-- turret "catches up," Death-Star-targeting-style, rather than one
-- straight line that jumps. See simulatedAimAngle's own declaration
-- above and UpdateSimulatedAimAngles below for the full explanation of
-- why this has to be simulated rather than read straight from the
-- engine. Uses the same DrawGroundWedge/-Outline helpers as the main
-- cone, red-tinted and (build zu) reaching the same radius as the main
-- cone (cfg.rangeCap, passed in by the caller) so it doesn't look
-- undersized next to the green wedge/"N deg" label, and simply isn't
-- drawn once the gap closes to nothing -- the two converging lines
-- "meeting" IS the signal that it's finished turning.
local function DrawAimSweep(ux, uy, uz, currentAngle, targetAngle, radius)
    local diff = NormalizeAngle(targetAngle - currentAngle)
    if math.abs(diff) < math.rad(1) then return end -- converged -- nothing to show
    local midAngle = NormalizeAngle(currentAngle + diff * 0.5)
    local halfWidth = math.abs(diff) * 0.5
    DrawGroundWedge(ux, uy, uz, midAngle, halfWidth, radius, 1.0, 0.15, 0.1, 0.22)
    DrawAngleLine(ux, uy, uz, currentAngle, radius, 1.0, 0.15, 0.1, 0.9, 2.0)
    DrawAngleLine(ux, uy, uz, targetAngle, radius, 1.0, 0.15, 0.1, 0.9, 2.0)
end

function widget:DrawWorldPreUnit()
    -- Live preview while configuring.
    if mode ~= MODE_NONE and modeUnitID and spValidUnitID(modeUnitID) then
        local ux, uy, uz = spGetUnitPosition(modeUnitID)
        if ux then
            local ang, hw, radius
            -- build zw, per the user ("keep yellow tint when creating a
            -- cone, and change color of tint to cyan (same opacity) when
            -- on range mode"): the wedge fill/outline tint now depends on
            -- which setup STAGE is active -- yellow (unchanged) during
            -- MODE_ANGLE, cyan during MODE_RANGE -- as an extra at-a-
            -- glance cue for which stage you're in, on top of the
            -- existing "Cone"/"Range" text label. Same alpha values as
            -- before in both cases, only the hue changes; the orange
            -- angle center-line is left alone (it's the cone's own
            -- reference line, not the stage tint).
            local tr, tg, tb
            if mode == MODE_ANGLE then
                tr, tg, tb = 1.0, 0.85, 0.1 -- yellow
            else
                tr, tg, tb = 0.1, 0.85, 1.0 -- cyan
            end
            if mode == MODE_ANGLE then
                -- build zz6: modeNativeRange is now freshly set for
                -- modeUnitID at the top of EnterAngleMode, so just use it
                -- directly -- the old math.max(modeNativeRange, ...) was
                -- exactly the bug: it let a stale, larger leftover value
                -- from a PREVIOUS unit's session win over this unit's own
                -- correct range.
                radius = modeNativeRange
                if radius <= 0 then radius = 2000 end
                ang, hw = previewAngle, previewHalfWidth
                DrawGroundWedge(ux, uy, uz, ang, hw, radius, tr, tg, tb, 0.18)
                DrawGroundWedgeOutline(ux, uy, uz, ang, hw, radius, tr, tg, tb, 0.9)
                DrawAngleLine(ux, uy, uz, ang, radius, 1.0, 0.6, 0.0, 0.95, 2.5)
            elseif mode == MODE_RANGE then
                local draft = pendingDraft[modeUnitID]
                ang = draft and draft.angle or previewAngle
                hw  = draft and draft.halfWidth or previewHalfWidth
                radius = previewRangeCap
                DrawGroundWedge(ux, uy, uz, ang, hw, radius, tr, tg, tb, 0.18)
                DrawGroundWedgeOutline(ux, uy, uz, ang, hw, radius, tr, tg, tb, 0.9)
                DrawAngleLine(ux, uy, uz, ang, radius, 1.0, 0.6, 0.0, 0.95, 2.5)
            end

            -- build zf, per the user ("if i choose 2+ ragnaroks can show
            -- feedback on both the units instead of one of them"): while
            -- still aiming -- before anything is locked in -- also preview
            -- every OTHER linked unit's DERIVED wedge, using the exact same
            -- GetConeEdgePoints/DeriveLinkedCone math the real deploy step
            -- uses (see the MousePress MODE_RANGE handler). So the player
            -- sees the whole group's shared coverage taking shape live,
            -- not just the reference unit's own wedge, and finds out how
            -- the rest of the group will look only after already
            -- committing. Drawn visibly dimmer than the reference unit's
            -- own preview so it stays clear which one the mouse is
            -- actually driving.
            if ang and hw and radius and radius > 0 and modeGroupUnitIDs and #modeGroupUnitIDs > 1 then
                local lx, lz, rx, rz = GetConeEdgePoints(ux, uz, ang, hw, radius)
                for i = 1, #modeGroupUnitIDs do
                    local otherID = modeGroupUnitIDs[i]
                    if otherID ~= modeUnitID and spValidUnitID(otherID) then
                        local ox, oy, oz = spGetUnitPosition(otherID)
                        if ox then
                            local nativeRange = GetWeaponRange(spGetUnitDefID(otherID))
                            local oAngle, oHalfWidth, oRangeCap = DeriveLinkedCone(ox, oz, nativeRange, lx, lz, rx, rz)
                            -- build zw: matches the reference unit's own
                            -- stage tint above (yellow/cyan), just dimmer.
                            DrawGroundWedge(ox, oy, oz, oAngle, oHalfWidth, oRangeCap, tr, tg, tb, 0.12)
                            DrawGroundWedgeOutline(ox, oy, oz, oAngle, oHalfWidth, oRangeCap, tr, tg, tb, 0.6)
                        end
                    end
                end
            end
        end
    end

    -- Persistent cones for already-configured units.
    for unitID, cfg in pairs(arcConfig) do
        if spValidUnitID(unitID) and unitID ~= modeUnitID and ShouldShowConeGui(unitID, cfg) then
            local ux, uy, uz = spGetUnitPosition(unitID)
            if ux then
                if cfg.enabled then
                    DrawGroundWedgeOutline(ux, uy, uz, cfg.angle, cfg.halfWidth, cfg.rangeCap, 0.2, 1.0, 0.3, 0.55)
                    DrawAngleLine(ux, uy, uz, cfg.angle, cfg.rangeCap, 1.0, 0.6, 0.0, 0.85, 2.0)

                    -- build zs: only while this widget actually has the
                    -- unit commanded to attack something (see
                    -- EnforceArcOnUnit/currentActionKind) AND has a
                    -- simulated bearing tracked for it yet (see
                    -- UpdateSimulatedAimAngles) -- otherwise there's no
                    -- meaningful "current aim" to show.
                    -- build zw: /conefirewedge master on/off switch --
                    -- checked here (drawing only) rather than in
                    -- UpdateSimulatedAimAngles, so simulatedAimAngle keeps
                    -- being tracked even while hidden and the wedge picks
                    -- up mid-turn instantly if toggled back on.
                    local kind = currentActionKind[unitID]
                    local simAngle = showAimSweepWedge and simulatedAimAngle[unitID]
                    if (kind == "unit" or kind == "ground") and simAngle then
                        local targetAngle
                        if kind == "unit" then
                            local tid = currentActionTargetID[unitID]
                            if tid and spValidUnitID(tid) then
                                local tux, _, tuz = spGetUnitPosition(tid)
                                if tux then targetAngle = BearingTo(ux, uz, tux, tuz) end
                            end
                        else
                            local p = currentActionPos[unitID]
                            if p then targetAngle = BearingTo(ux, uz, p.x, p.z) end
                        end
                        if targetAngle then
                            -- build zu: reach the same distance as the
                            -- main cone (green wedge / orange center
                            -- line) instead of a short fixed radius.
                            DrawAimSweep(ux, uy, uz, simAngle, targetAngle, cfg.rangeCap or AIM_SWEEP_RADIUS)
                        end
                    end
                else
                    DrawGroundWedgeOutline(ux, uy, uz, cfg.angle, cfg.halfWidth, cfg.rangeCap, 0.6, 0.6, 0.6, 0.3)
                end
            end
        end
    end
    glColor(1, 1, 1, 1)
end

-- Screen-space text labels for the two reference lines drawn above --
-- gl.Text needs 2D screen coords (same pattern as the "X" button, see
-- GetSwitchScreenRect), so this is called from DrawScreen, not
-- DrawWorldPreUnit, even though it's conceptually part of the same feature.
-- build u, per the user (two screenshots showing "Cone = 70 degrees",
-- "66 deg (cone center)" and "0 deg (ref)" all crowded/overlapping near the
-- unit whenever the cone's center angle happens to sit close to the 0-deg
-- reference direction): push the cone-center label further out along its
-- line (CONE_CENTER_LABEL_DIST_MULT, was a fixed 1.15x -- see labelFor
-- below), and, since that alone can't help when the cone center angle
-- itself is genuinely close to 0 deg, also run a small screen-space
-- separation pass across all of one unit's labels every frame so any two
-- that would render too close simply push each other directly apart --
-- "like negative-negative magnets," per the user's own description --
-- until there's enough room for both to read cleanly, however the camera
-- angle/zoom happens to project them that frame.
local CONE_CENTER_LABEL_DIST_MULT = 2.0 -- build ze: was 1.6 (originally 1.15) -- still clashing with the unit icon on zoom-out per the user, pushed further again
local WIDTH_LABEL_DIST_FRACTION = 0.85  -- build x: was 0.6 -- how far out the "N°" width label sits, as a fraction of labelDist (the cone-center label's own distance) -- 0.6 still read as "too close to the unit icon" once zoomed out, per the user
local WIDTH_LABEL_EXTRA_PX = 45 -- build ze: was 30 (build y) -- bumped again alongside CONE_CENTER_EXTRA_PX below
local CONE_CENTER_EXTRA_PX = 45 -- build ze: the cone-center label previously had NO fixed-pixel push at all (only WIDTH_LABEL did, since build y) -- per the user ("move the cone center stat... further out, notice 99 degrees is clashing with unit icon"), both labels now get the same kind of zoom-invariant pixel push, not just the width one
local LABEL_SEPARATION_PADDING_PX = 6   -- extra breathing room kept between two labels' text boxes once separated, beyond just touching

-- build ze: pushes an already-projected screen point (sx,sy) further away
-- from a unit's own screen position by a fixed number of pixels, along the
-- line connecting them. Used by both the "N° (cone center)" and "N°"
-- width labels below so their placement means the same thing at any zoom
-- level -- a pure world-space offset (labelDist/widthLabelDist) covers a
-- shrinking number of screen pixels the further the camera zooms out,
-- which is exactly why both labels kept reading as "clashing with the
-- unit icon" after repeated world-space-only tweaks (builds u, w, x).
-- Falls back to the unpushed point if the unit's own screen projection or
-- the direction vector is ever degenerate (behind the camera, or exactly
-- on top of the label) -- same defensive style as the rest of this file's
-- screen-coord handling.
local function PushAwayFromUnit(sx, sy, ux, uy, uz, extraPx)
    local usx, usy, usz = spWorldToScreenCoords(ux, uy, uz)
    if not usx or (usz and usz < 0) then return sx, sy end
    local dx, dy = sx - usx, sy - usy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.01 then return sx, sy end
    return sx + (dx / dist) * extraPx, sy + (dy / dist) * extraPx
end

-- Nudges a set of screen-space text labels apart from each other so none
-- overlap. `labels` is an array of {x, y, text, size, ...} -- x/y are
-- mutated in place. Each label's half-width in screen pixels is measured
-- with gl.GetTextWidth (returns width for size=1; the actual on-screen
-- width scales linearly with the font size passed to gl.Text, confirmed
-- from the engine's own LuaOpenGL::GetTextWidth/CglFont::GetTextWidth), so
-- this works correctly even though "Cone = 70 degrees" and "0 deg (ref)"
-- aren't the same length or font size. A handful of passes is enough for
-- 3 labels to settle -- this isn't a general physics simulation, just
-- enough repulsion to stop text visibly overlapping.
local function SeparateLabels(labels)
    for i = 1, #labels do
        local lbl = labels[i]
        lbl.halfW = glGetTextWidth(lbl.text) * lbl.size * 0.5 + LABEL_SEPARATION_PADDING_PX
    end
    for pass = 1, 4 do
        for i = 1, #labels do
            for j = i + 1, #labels do
                local a, b = labels[i], labels[j]
                local dx, dy = b.x - a.x, b.y - a.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local minDist = a.halfW + b.halfW
                if dist < minDist then
                    if dist < 0.01 then
                        dx, dy, dist = 1, 0, 0.01 -- same point (degenerate) -- pick an arbitrary push axis
                    end
                    local nx, ny = dx / dist, dy / dist
                    local push = (minDist - dist) * 0.5
                    a.x, a.y = a.x - nx * push, a.y - ny * push
                    b.x, b.y = b.x + nx * push, b.y + ny * push
                end
            end
        end
    end
end

local function DrawAngleReferenceLabels()
    local function labelFor(ux, uy, uz, angle, halfWidth)
        local labels = {}

        -- build v, per the user: the "0 deg (ref)" tick/label (both the
        -- cyan line and its text) was removed entirely -- it didn't add
        -- anything the "N deg (cone center)" label doesn't already say on
        -- its own, and it was the main source of visual clutter/overlap
        -- near the unit. See DrawWorldPreUnit for the matching removal of
        -- its three DrawAngleLine(..., 0, ...) draw calls.
        local labelDist = ANGLE_REF_TICK_LENGTH * CONE_CENTER_LABEL_DIST_MULT
        local cx = ux + math.sin(angle) * labelDist
        local cz = uz + math.cos(angle) * labelDist
        local csx, csy, csz = spWorldToScreenCoords(cx, uy, cz)
        if csx and not (csz and csz < 0) then
            -- build ze: same fixed-pixel push the width label already got
            -- in build y, now applied here too -- see PushAwayFromUnit.
            csx, csy = PushAwayFromUnit(csx, csy, ux, uy, uz, CONE_CENTER_EXTRA_PX)
            labels[#labels + 1] = { x = csx, y = csy, text = string.format("%.0f\194\176 (cone center)", math.deg(angle)), size = 11, r = 1.0, g = 0.6, b = 0.0, a = 0.95 }
        end

        -- Added 2026-09-03, per the user: a live readout of the cone's
        -- actual TOTAL width (this widget stores the HALF-width
        -- internally, hence the *2 -- see cfg.halfWidth throughout this
        -- file), placed along the centerline so it sits visibly INSIDE the
        -- drawn wedge. Unlike the two labels above (fixed reference
        -- points), this one updates every single frame the cone is being
        -- widened/narrowed with the mouse wheel -- the same live number
        -- DrawSetupPrompt already prints at the top of the screen, just
        -- readable right where you're actually looking while you adjust
        -- it. Also shown for already-deployed cones (see the two call
        -- sites below), so a quick glance confirms what each one is
        -- currently set to.
        --
        -- build w, per the user (screenshot with a hand-drawn red circle):
        -- shortened the text from "Cone = 90 degrees" to just "90°", and
        -- fixed its placement -- it was previously anchored at a FIXED
        -- 275-elmo distance (`ANGLE_REF_TICK_LENGTH * 0.55`) regardless of
        -- how far out the cone itself actually extends. During the
        -- MODE_ANGLE setup stage, the drawn wedge follows the weapon's
        -- full native range (5750+ elmos for these units), so 275 elmos is
        -- barely past the apex -- the two edges haven't visually spread
        -- apart enough yet for the label to land inside them, so it ended
        -- up looking like it was floating up by the mouse cursor/cone icon
        -- instead of inside the cone, exactly as the user's screenshot
        -- showed. Anchoring it as a FRACTION of `labelDist` (the same
        -- distance the "N deg (cone center)" label above already uses,
        -- which the same screenshot shows landing correctly inside the
        -- wedge) ties both labels' placement to the same reference point
        -- instead of an unrelated fixed constant, so this label now always
        -- sits well inside the cone regardless of the wedge's actual
        -- length.
        if halfWidth then
            local widthLabelDist = labelDist * WIDTH_LABEL_DIST_FRACTION
            local wx = ux + math.sin(angle) * widthLabelDist
            local wz = uz + math.cos(angle) * widthLabelDist
            local wsx, wsy, wsz = spWorldToScreenCoords(wx, uy, wz)
            if wsx and not (wsz and wsz < 0) then
                -- build y, per the user ("more out say 30 more pixels
                -- out"): a further world-space distance tweak would still
                -- only be an approximate, zoom-dependent nudge (the same
                -- world-space offset covers very different screen-pixel
                -- distances at different zoom levels) -- a literal pixel
                -- request is answered more precisely by pushing the
                -- already-projected SCREEN point outward, along the
                -- direction from the unit's own screen position to this
                -- label's screen position, by a fixed pixel amount that
                -- means the same thing at any zoom. build ze: extracted
                -- into the shared PushAwayFromUnit helper once the
                -- cone-center label needed the exact same treatment.
                wsx, wsy = PushAwayFromUnit(wsx, wsy, ux, uy, uz, WIDTH_LABEL_EXTRA_PX)
                labels[#labels + 1] = { x = wsx, y = wsy, text = string.format("%.0f\194\176", math.deg(halfWidth) * 2), size = 13, r = 1.0, g = 1.0, b = 1.0, a = 0.95 }
            end
        end

        SeparateLabels(labels)

        for i = 1, #labels do
            local lbl = labels[i]
            glColor(lbl.r, lbl.g, lbl.b, lbl.a)
            glText(lbl.text, lbl.x, lbl.y, lbl.size, "c")
        end
    end

    if mode ~= MODE_NONE and modeUnitID and spValidUnitID(modeUnitID) then
        local ux, uy, uz = spGetUnitPosition(modeUnitID)
        if ux then
            local angle, halfWidth
            if mode == MODE_ANGLE then
                angle = previewAngle
                halfWidth = previewHalfWidth
            else
                local draft = pendingDraft[modeUnitID]
                angle = draft and draft.angle or previewAngle
                halfWidth = draft and draft.halfWidth or previewHalfWidth
            end
            labelFor(ux, uy, uz, angle, halfWidth)
        end
    end

    for unitID, cfg in pairs(arcConfig) do
        if cfg.enabled and unitID ~= modeUnitID and spValidUnitID(unitID) and ShouldShowConeGui(unitID, cfg) then
            local ux, uy, uz = spGetUnitPosition(unitID)
            if ux then
                labelFor(ux, uy, uz, cfg.angle, cfg.halfWidth)
            end
        end
    end
    glColor(1, 1, 1, 1)
end

local function DrawSetupPrompt()
    if mode == MODE_NONE then return end
    local msg
    if mode == MODE_ANGLE then
        msg = string.format("Cone-of-Fire: scroll wheel to adjust width (%.0f deg), left-click to set",
            math.deg(previewHalfWidth) * 2)
    elseif mode == MODE_RANGE then
        msg = string.format("Cone-of-Fire: move mouse to set range (%.0f), left-click to activate",
            previewRangeCap)
    end
    if msg then
        local vsx, vsy = Spring.GetViewGeometry()
        glColor(1, 1, 1, 1)
        glText(msg, vsx * 0.5, vsy - 60, 16, "oc")
    end
end

-- Small Lua-drawn cursor icon while in setup mode, same technique as the
-- Clone Builder widget's "duplicate" cursor icon (no image assets needed).
--
-- Rewritten 2026-09-03, per the user:
--   1. Moved further from the mouse position (CONE_ICON_OFFSET_X/Y, in the
--      USER-TWEAKABLE SETTINGS block) -- it was clashing with/overlapping
--      the system cursor at the old, smaller offset (later dialed back in
--      once too far was the new complaint -- see the notes.md history).
--   2. Re-oriented to point at the 3 o'clock position -- apex (point of
--      origin) on the left, opening toward the right, like a "<" -- rather
--      than the old apex-at-bottom/opening-upward orientation. The apex
--      stays anchored at the icon's local origin (0,0,0) either way; only
--      the two open-end vertices moved from (+-CONE_ICON_HALF,
--      CONE_ICON_LEN) [up] to (CONE_ICON_LEN, +-CONE_ICON_HALF) [right].
--   3. Animated FILL (not a moving line -- the user's own follow-up
--      screenshots showed the first attempt, a bright segment sliding
--      along the two edges, and asked for the interior filled instead): a
--      solid yellow triangle now grows from the apex out to the full
--      wedge, looping continuously. Implemented as a GL_TRIANGLE_FAN of
--      (apex, edge1 point at t, edge2 point at t) -- since both edges are
--      straight lines from the apex, cutting them at the same fraction t
--      and filling that gives exactly a smaller, similar triangle that
--      grows in place, reading as the fill sweeping from the point of
--      origin out to the outer boundary. Driven by Spring.GetGameSeconds()
--      (falls back to os.clock() if unavailable) modulo
--      CONE_ICON_PULSE_SECONDS, so it's a real-time animation independent
--      of sim frame rate or game speed.
local function DrawConeCursorIcon()
    if mode == MODE_NONE then return end
    local mx, my = spGetMouseState()
    if not mx then return end

    -- build zh, per the user (screenshot with a hand-drawn red circle
    -- directly above the mouse pointer): a small always-visible label
    -- naming the CURRENT setup stage -- "Cone" during MODE_ANGLE (choosing
    -- the cone's width), "Range" during MODE_RANGE (choosing the distance
    -- cap) -- right above the actual mouse pointer, not the cone-cursor
    -- icon (which sits off to the side via CONE_ICON_OFFSET_X/Y). Drawn
    -- from the RAW mouse position, before the icon's own glTranslate
    -- below, since it's anchored to the cursor itself, not the icon.
    local stageLabel = (mode == MODE_ANGLE) and "Cone" or (mode == MODE_RANGE) and "Range" or nil
    if stageLabel then
        glColor(1, 1, 1, 0.95)
        glText(stageLabel, mx, my + CURSOR_MODE_LABEL_OFFSET_Y, 13, "c")
        glColor(1, 1, 1, 1)
    end

    glPushMatrix()
    glTranslate(mx + CONE_ICON_OFFSET_X, my + CONE_ICON_OFFSET_Y, 0)

    -- Always-visible dim outline of the full wedge shape (apex + both
    -- edges + base), so the icon's true size/shape reads clearly at every
    -- point in the animation, including the instant it resets back to
    -- empty.
    glColor(1, 0.85, 0.1, 0.5)
    glLineWidth(2)
    glBeginEnd(GL_LINES, function()
        glVertex(0, 0, 0); glVertex(CONE_ICON_LEN, CONE_ICON_HALF, 0)
        glVertex(0, 0, 0); glVertex(CONE_ICON_LEN, -CONE_ICON_HALF, 0)
        glVertex(CONE_ICON_LEN, CONE_ICON_HALF, 0); glVertex(CONE_ICON_LEN, -CONE_ICON_HALF, 0)
    end)

    -- The growing fill itself.
    local now = Spring.GetGameSeconds and Spring.GetGameSeconds() or os.clock()
    local t = (now % CONE_ICON_PULSE_SECONDS) / CONE_ICON_PULSE_SECONDS -- 0..1, loops
    glColor(1, 0.85, 0.15, 0.6)
    glBeginEnd(GL_TRIANGLE_FAN, function()
        glVertex(0, 0, 0)
        glVertex(CONE_ICON_LEN * t, CONE_ICON_HALF * t, 0)
        glVertex(CONE_ICON_LEN * t, -CONE_ICON_HALF * t, 0)
    end)

    glPopMatrix()
    glColor(1, 1, 1, 1)
end

-- 2026-09-02: the On/Pause toggle switch was removed per the user (see
-- GetSwitchScreenRect) -- this now draws only the "X" button, which is the
-- single remaining per-unit screen control for disabling Cone-of-Fire on
-- that unit. Function name kept as-is (still called from DrawScreen,
-- renaming has no functional benefit).
local function DrawToggleSwitches()
    for unitID, cfg in pairs(arcConfig) do
        if spValidUnitID(unitID) then
            local rx1, ry1, rx2, ry2 = GetSwitchScreenRect(unitID)
            if rx1 then
                glColor(0.5, 0.05, 0.05, 0.9)
                glRect(rx1, ry1, rx2, ry2)
                glColor(0, 0, 0, 0.8)
                glLineWidth(1)
                glBeginEnd(GL_LINE_LOOP, function()
                    glVertex(rx1, ry1, 0); glVertex(rx2, ry1, 0)
                    glVertex(rx2, ry2, 0); glVertex(rx1, ry2, 0)
                end)
                glColor(1, 1, 1, 1)
                glText("X", (rx1 + rx2) * 0.5, ry1 + 4, 11, "c")
            end

            -- build zo: the "?" (help) button, right next to "X".
            local hx1, hy1, hx2, hy2 = GetHelpScreenRect(unitID)
            if hx1 then
                glColor(0.1, 0.3, 0.55, 0.9)
                glRect(hx1, hy1, hx2, hy2)
                glColor(0, 0, 0, 0.8)
                glLineWidth(1)
                glBeginEnd(GL_LINE_LOOP, function()
                    glVertex(hx1, hy1, 0); glVertex(hx2, hy1, 0)
                    glVertex(hx2, hy2, 0); glVertex(hx1, hy2, 0)
                end)
                glColor(1, 1, 1, 1)
                glText("?", (hx1 + hx2) * 0.5, hy1 + 3, 11, "c")
            end
        end
    end
    glColor(1, 1, 1, 1)
end

-- build zp, per the user ("black on white. Look at eco graph tooltips" /
-- "also make it 2 columns 1st column are the commans or subject and the
-- 2nd colum the descrption"): restyled to match gui_eco_graph.lua's own
-- light tooltip convention (near-opaque white fill, thin dark border,
-- black text) instead of this widget's own dark/yellow styling, and laid
-- out as label|description columns rather than one wrapped paragraph per
-- control.
local HELP_PANEL_PADDING = 12
local HELP_PANEL_FONT_SIZE = 13
local HELP_PANEL_LINE_H = 17
local HELP_PANEL_ROW_GAP = 5      -- extra vertical space between rows
local HELP_PANEL_COL1_W = 150     -- column 1 ("label") fixed width, px
local HELP_PANEL_COL_GAP = 14     -- gap between column 1 and column 2
local HELP_PANEL_COL2_W = 380     -- column 2 ("desc") wrap width, px
local HELP_PANEL_MARGIN = 8       -- kept this far from every screen edge
local HELP_PANEL_CLOSE_SIZE = 16  -- the upper-right "X" close button, px

-- Greedy word-wrap using the same gl.GetTextWidth technique as the angle-
-- reference labels (see LABEL_SEPARATION_PADDING_PX above): GetTextWidth
-- returns a size-1-normalized width, so the actual pixel width at a given
-- font size is that times the font size (confirmed against the engine's
-- own LuaOpenGL::GetTextWidth).
local function WrapHelpLine(text, maxWidthPx, fontSize)
    local lines = {}
    local current = ""
    for word in text:gmatch("%S+") do
        local candidate = (current == "") and word or (current .. " " .. word)
        if glGetTextWidth(candidate) * fontSize > maxWidthPx and current ~= "" then
            lines[#lines + 1] = current
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then
        lines[#lines + 1] = current
    end
    return lines
end

-- build zp: CONTROLS_HELP_ROWS is static, so each row's description only
-- actually gets wrapped once (the first time the panel is opened) and
-- cached here -- cheap enough not to matter, but no reason to redo it
-- every single frame the panel happens to stay open.
local cachedHelpRows
local function GetHelpRows()
    if cachedHelpRows then return cachedHelpRows end
    local out = {}
    for i = 1, #CONTROLS_HELP_ROWS do
        local row = CONTROLS_HELP_ROWS[i]
        out[#out + 1] = {
            label = row.label,
            descLines = WrapHelpLine(row.desc, HELP_PANEL_COL2_W, HELP_PANEL_FONT_SIZE),
        }
    end
    cachedHelpRows = out
    return out
end

-- build zo, per the user ("put a '?' next to X and when you click on it a
-- tooltip showing you all the functions"); build zp added position-
-- awareness ("make that position aware") -- opens next to whichever "?"
-- was actually clicked (helpPanelAnchorX/Y, set in widget:MousePress)
-- instead of one fixed screen spot, then clamps so it always stays fully
-- on screen (within HELP_PANEL_MARGIN of every edge) no matter where on
-- screen that "?" was. Drawn last (on top of everything else in
-- DrawScreen) so it's never obscured. Fixed to the screen, not any
-- particular unit -- there is only ever one panel regardless of which
-- unit's "?" opened it.
local function DrawControlsHelpPanel()
    if not showControlsHelp then return end
    local vsx, vsy = Spring.GetViewGeometry()
    local rows = GetHelpRows()

    local titleFontSize = 15
    local panelW = HELP_PANEL_PADDING * 2 + HELP_PANEL_COL1_W + HELP_PANEL_COL_GAP + HELP_PANEL_COL2_W
    local panelH = HELP_PANEL_PADDING * 2 + titleFontSize + 10
    for i = 1, #rows do
        panelH = panelH + (#rows[i].descLines) * HELP_PANEL_LINE_H + HELP_PANEL_ROW_GAP
    end

    -- Anchor next to the "?" that was clicked (falls back to screen
    -- center if none has been clicked yet this load), opening down-and-
    -- right from it, same convention as gui_eco_graph.lua's own hover
    -- tooltips -- then clamp fully on screen from there.
    local anchorX = helpPanelAnchorX or (vsx * 0.5)
    local anchorY = helpPanelAnchorY or (vsy * 0.5)

    local px1 = anchorX + 16
    local py2 = anchorY - 10
    local px2 = px1 + panelW
    local py1 = py2 - panelH

    if px2 > vsx - HELP_PANEL_MARGIN then
        px2 = vsx - HELP_PANEL_MARGIN
        px1 = px2 - panelW
    end
    if px1 < HELP_PANEL_MARGIN then
        px1 = HELP_PANEL_MARGIN
        px2 = px1 + panelW
    end
    if py1 < HELP_PANEL_MARGIN then
        py1 = HELP_PANEL_MARGIN
        py2 = py1 + panelH
    end
    if py2 > vsy - HELP_PANEL_MARGIN then
        py2 = vsy - HELP_PANEL_MARGIN
        py1 = py2 - panelH
    end

    glColor(1, 1, 1, 0.94)
    glRect(px1, py1, px2, py2)
    glColor(0, 0, 0, 0.35)
    glLineWidth(1)
    glBeginEnd(GL_LINE_LOOP, function()
        glVertex(px1, py1, 0); glVertex(px2, py1, 0)
        glVertex(px2, py2, 0); glVertex(px1, py2, 0)
    end)

    glColor(0, 0, 0, 1)
    glText("Cone-of-Fire -- Controls", px1 + HELP_PANEL_PADDING, py2 - HELP_PANEL_PADDING - titleFontSize + 4, titleFontSize, "l")

    -- build zt: "X" close button, upper-right corner -- always closes the
    -- panel regardless of any unit's state (see helpPanelCloseRect above).
    local cx2 = px2 - 6
    local cx1 = cx2 - HELP_PANEL_CLOSE_SIZE
    local cy2 = py2 - 6
    local cy1 = cy2 - HELP_PANEL_CLOSE_SIZE
    helpPanelCloseRect = { x1 = cx1, y1 = cy1, x2 = cx2, y2 = cy2 }
    glColor(0.75, 0.1, 0.1, 0.9)
    glRect(cx1, cy1, cx2, cy2)
    glColor(0, 0, 0, 0.5)
    glLineWidth(1)
    glBeginEnd(GL_LINE_LOOP, function()
        glVertex(cx1, cy1, 0); glVertex(cx2, cy1, 0)
        glVertex(cx2, cy2, 0); glVertex(cx1, cy2, 0)
    end)
    glColor(1, 1, 1, 1)
    glText("X", (cx1 + cx2) * 0.5, cy1 + 3, 11, "c")

    local col1X = px1 + HELP_PANEL_PADDING
    local col2X = col1X + HELP_PANEL_COL1_W + HELP_PANEL_COL_GAP
    -- thin divider between the two columns, spanning the full row area
    glColor(0, 0, 0, 0.15)
    glBeginEnd(GL_LINES, function()
        glVertex(col2X - HELP_PANEL_COL_GAP * 0.5, py1 + HELP_PANEL_PADDING * 0.5, 0)
        glVertex(col2X - HELP_PANEL_COL_GAP * 0.5, py2 - HELP_PANEL_PADDING - titleFontSize - 6, 0)
    end)

    glColor(0, 0, 0, 1)
    local ty = py2 - HELP_PANEL_PADDING - titleFontSize - 10
    for i = 1, #rows do
        local row = rows[i]
        glText(row.label, col1X, ty, HELP_PANEL_FONT_SIZE, "l")
        for j = 1, #row.descLines do
            glText(row.descLines[j], col2X, ty, HELP_PANEL_FONT_SIZE, "l")
            ty = ty - HELP_PANEL_LINE_H
        end
        ty = ty - HELP_PANEL_ROW_GAP
    end
    glColor(1, 1, 1, 1)
end

function widget:DrawScreen()
    DrawSetupPrompt()
    DrawConeCursorIcon()
    DrawToggleSwitches()
    DrawAngleReferenceLabels()
    DrawControlsHelpPanel()
end
