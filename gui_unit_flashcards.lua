function widget:GetInfo()
    return {
        name    = "Unit Flashcards",
        desc    = "Casino-style flashcard deck for memorizing BAR unit/structure names and stats, by faction, tier and type.",
        author  = "Armis71, Claude",
        date    = "2026-10-30",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true,
    }
end

local spGetMouseState = Spring.GetMouseState
local spGetConfigInt  = Spring.GetConfigInt
local spSetConfigInt  = Spring.SetConfigInt
local spEcho          = Spring.Echo
-- Round 13 (quiz-complete confetti): Spring.GetTimer/DiffTimers rather than
-- os.clock -- same reasoning gui_unit_chatter.lua already documents in this
-- project (finer resolution, and it's what the engine's own code uses),
-- and these two get called every frame for 4 seconds straight so caching
-- them as locals is worth it here unlike the file's other, rarely-called
-- Spring.* calls.
local spGetTimer      = Spring.GetTimer
local spDiffTimers    = Spring.DiffTimers

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local ICON = {
    W = 120, H = 100,
    bgColor     = {0, 0, 0, 0.55},
    borderColor = {1, 1, 1, 0.35},
}

local FACTIONS = {"arm", "cor", "leg"}
local FACTION_LABEL = {arm = "Armada", cor = "Cortex", leg = "Legion"}
local FACTION_COLOR = {
    arm = {0.45, 0.65, 1.0, 1},
    cor = {1.0, 0.45, 0.4, 1},
    leg = {0.55, 0.9, 0.5, 1},
}
local TIERS = {1, 2, 3}
local TIER_LABEL = {[1] = "T1", [2] = "T2", [3] = "T3"}

local TYPES = {"bot", "vehicle", "air", "sea", "structure"}
local TYPE_LABEL = {bot = "Bots", vehicle = "Vehicles", air = "Air", sea = "Sea", structure = "Structures"}

local CARD_W, CARD_H = 300, 420
local CARD_BORDER = 10
local CARD_RADIUS_STEPS = 6 -- fake-rounded-corner fan segments

-- Quiz mode (round 5): 1 correct name + up to 19 decoys, split evenly
-- left/right of the card.
local QUIZ_CHOICE_TOTAL = 20
local QUIZ_PER_SIDE     = QUIZ_CHOICE_TOTAL / 2

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local panelVisible = false

local iconRect  = {x1 = 0, y1 = 0, x2 = 0, y2 = 0}
local iconDrag  = {active = false, startX = 0, startY = 0, offsetX = 0, offsetY = 0, moved = false}
local iconPos   = {x = 40, y = 40} -- bottom-left, screen space; loaded in Initialize

local panelPos  = {x = 180, y = 40} -- bottom-left, screen space; loaded in Initialize
local panelDrag = {active = false, startX = 0, startY = 0, offsetX = 0, offsetY = 0}
-- Real clamp floor (PANEL_W/PANEL_H) is computed below, once the panel
-- layout constants exist -- see round 4 fix notes near ComputePanelSize().

-- selection[faction][tier] = true/false ; multi-select, rebuilds the deck
-- pool whenever any cell changes.
local selection = {}
for _, f in ipairs(FACTIONS) do
    selection[f] = {}
    for _, t in ipairs(TIERS) do
        selection[f][t] = false
    end
end

-- typeSelection[type] = true/false ; multi-select secondary filter. Empty
-- selection (no type toggled) means "no type filter" -- everything from
-- the faction/tier selection shows, same as before this filter existed.
local typeSelection = {}
for _, t in ipairs(TYPES) do
    typeSelection[t] = false
end

local allUnitsCache  = nil   -- built once: { {id=,name=,faction=,tier=,unitType=,isCommander=,ud=}, ... }
local labTypeByID    = nil   -- built once alongside allUnitsCache: [unitDefID] = "bot"/"vehicle"/"air"/"sea"
local deckPool       = {}    -- filtered by current selection
local shuffledDeck   = {}    -- current shuffle order, consumed front-to-back
local deckCursor     = 0

local currentCard  = nil     -- entry from deckPool, or nil if pool is empty
local flipped       = false
local cardHover     = false
local panelRects    = {} -- faction/tier buttons, type buttons, all-random button, card rect --
                          -- rebuilt only when the layout actually changes (see RelayoutPanelIfNeeded
                          -- below, round 16 perf fix), not on every single DrawScreen frame

-- Quiz mode (round 5, exhaustive draw added round 6): a secondary way to
-- test yourself -- instead of (or alongside) just flipping, pick the
-- right name from a list of decoys flanking the card. quizChoices is
-- rebuilt for every new card (see RefreshQuizChoices);
-- quizAnswered/quizPickedIndex track this ONE card's answer so a second
-- click doesn't re-score it; quizScore persists across cards until quiz
-- mode is turned off and back on. Round 6: unlike normal free-play (which
-- shuffles deckPool forever, same card able to reappear many times),
-- quiz mode deals from quizDeck -- deckPool shuffled ONCE per quiz round,
-- consumed front-to-back with no repeats -- and sets quizFinished once
-- every selected card has been shown.
local quizMode        = false
local quizChoices     = {}    -- { {name=, correct=}, ... } for the current card
local quizAnswered    = false
local quizPickedIndex = nil
-- Round 15: "if i don't select a choice but click on the card, put a
-- reminder to quiz taker to select a choice else turn off/quit quiz."
-- True once the player has already flipped (peeked at) the current quiz
-- card and then tries to click/space PAST it without ever picking a
-- choice -- ActivateCard refuses to advance while this would otherwise
-- happen, and the hint line below the card nags them instead. Cleared the
-- moment they actually answer (PickQuizChoice) or a new card is dealt
-- (RefreshQuizChoices).
local quizSkipAttempted = false
local quizScore       = {correct = 0, total = 0}
local quizDeck        = {}    -- deckPool, shuffled once per quiz round, consumed front-to-back
local quizDeckCursor  = 0
local quizFinished    = false

-- Round 13: "if on a quiz and i get 100% right, can you make a confetti
-- fireworks effect last like 4 seconds." Fires once, at the exact moment
-- a quiz round ends (DrawNextCard's quizFinished transition) with a
-- perfect score. confettiParticles is a plain array of per-particle
-- starting conditions (position/velocity/spin/color) computed ONCE at
-- trigger time; DrawConfetti below is a pure function of elapsed time
-- against those starting conditions (no per-frame physics integration,
-- so there's nothing to drift or desync even if the panel is hidden and
-- reopened mid-burst).
local confettiActive     = false
local confettiStartTime  = nil
local confettiParticles  = {}
local fireworkBursts     = {} -- round 14: {x, y, t0, color, particles={{vx,vy},...}}
local celebrationMessage = nil -- round 15: the big popup line, picked to match the just-finished selection

local CONFETTI_DURATION = 4    -- seconds
local CONFETTI_FADE     = 0.6  -- seconds of fade-out at the very end
local CONFETTI_COUNT    = 160  -- round 14: "thicker or more confetti" -- was 90
local CONFETTI_GRAVITY  = 220  -- px/s^2, pulling particles back down
local CONFETTI_SPAWN_MARGIN = 60 -- px beyond the panel's own left/right edges

-- Round 14: fireworks, going off one after another throughout the same
-- window the confetti is falling. Each burst is a short-lived radial
-- spray of sparks from one point, timed by its OWN t0 against the same
-- elapsed-since-trigger clock confetti already uses.
local FIREWORK_BURST_COUNT         = 5
local FIREWORK_PARTICLES_PER_BURST = 40
local FIREWORK_LIFETIME            = 1.1  -- seconds a single burst takes to fade out
local FIREWORK_GRAVITY             = 160  -- px/s^2
local FIREWORK_MIN_SPEED           = 90   -- px/s
local FIREWORK_MAX_SPEED           = 230  -- px/s
local FIREWORK_SPARK_SIZE          = 2.5

local CONFETTI_COLORS = {
    {0.95, 0.25, 0.30}, {0.25, 0.65, 0.95}, {0.95, 0.80, 0.20},
    {0.35, 0.85, 0.45}, {0.75, 0.40, 0.95}, {0.95, 0.55, 0.15},
}

-- Shared by BuildConfettiParticles and BuildFireworkBursts (round 14:
-- "keep the confetti celebration around the widget window" -- previously
-- this spawned across the ENTIRE screen via Spring.GetViewGeometry();
-- both effects now spawn relative to the panel's own last-laid-out
-- bounds instead, so the celebration stays framed around the widget
-- rather than covering the whole view). Falls back to a rough
-- screen-relative box only if the panel has somehow never been laid out
-- yet (shouldn't happen in practice -- a celebration only ever fires
-- while the panel is visible and DrawPanel has already run at least
-- once -- but a missing panelRects.bounds shouldn't ever be able to
-- crash this).
local function ConfettiSpawnArea()
    local bounds = panelRects.bounds
    if bounds then
        return bounds.x1 - CONFETTI_SPAWN_MARGIN, bounds.x2 + CONFETTI_SPAWN_MARGIN,
            bounds.y1, bounds.y2
    end
    local vsx, vsy = Spring.GetViewGeometry()
    return vsx * 0.25, vsx * 0.75, vsy * 0.35, vsy * 0.85
end

-- One-shot: every particle's full trajectory is fixed at spawn time
-- (DrawConfetti below only ever samples elapsed time against these, never
-- integrates a per-frame step), so the burst looks identical regardless
-- of framerate and can't drift or desync if the panel is hidden and
-- reopened mid-burst. Defined up here (rather than alongside DrawPanel,
-- where the rest of the drawing code lives) because BuildQuizDeck and
-- DrawNextCard -- both much further down this file in load order, but
-- textually earlier -- need to call MaybeTriggerConfetti/StopConfetti
-- below, and a `local function` isn't visible to code written before it.
local function BuildConfettiParticles()
    local areaX1, areaX2, _, areaY2 = ConfettiSpawnArea()
    local particles = {}
    for i = 1, CONFETTI_COUNT do
        particles[i] = {
            x0        = areaX1 + math.random() * (areaX2 - areaX1),
            y0        = areaY2 + 40 + math.random() * 80, -- start just above the panel's top edge
            vx        = (math.random() - 0.5) * 140,      -- sideways drift, px/s
            vy0       = 40 + math.random() * 80,           -- initial little upward pop, px/s (y grows upward)
            size      = 7 + math.random() * 6,             -- round 14: thicker pieces (was 5-10)
            spin0     = math.random() * 360,
            spinSpeed = (math.random() - 0.5) * 540,       -- deg/s
            color     = CONFETTI_COLORS[((i - 1) % #CONFETTI_COLORS) + 1],
        }
    end
    return particles
end

-- Round 14: a handful of radial sparks-bursts, ignited at staggered times
-- (t0, each relative to the same confettiStartTime the falling confetti
-- uses) spread across the celebration's window so they go off one after
-- another rather than all at once. Centers are picked from roughly the
-- panel's own upper half up through just above it, same "around the
-- widget" framing as the confetti.
local function BuildFireworkBursts()
    local areaX1, areaX2, areaY1, areaY2 = ConfettiSpawnArea()
    local burstY1 = areaY1 + (areaY2 - areaY1) * 0.5
    local burstY2 = areaY2 + 50

    local bursts = {}
    local span = math.max(0, CONFETTI_DURATION - FIREWORK_LIFETIME - 0.3)
    for i = 1, FIREWORK_BURST_COUNT do
        local particles = {}
        for j = 1, FIREWORK_PARTICLES_PER_BURST do
            local angle = math.random() * math.pi * 2
            local speed = FIREWORK_MIN_SPEED + math.random() * (FIREWORK_MAX_SPEED - FIREWORK_MIN_SPEED)
            particles[j] = {vx = math.cos(angle) * speed, vy = math.sin(angle) * speed}
        end
        bursts[i] = {
            x = areaX1 + math.random() * (areaX2 - areaX1),
            y = burstY1 + math.random() * (burstY2 - burstY1),
            t0 = 0.15 + ((i - 1) / FIREWORK_BURST_COUNT) * span + math.random() * 0.25,
            color = CONFETTI_COLORS[((i - 1) % #CONFETTI_COLORS) + 1],
            particles = particles,
        }
    end
    return bursts
end

-- MaybeTriggerConfetti/StopConfetti themselves live further down this
-- file (right after AllCellsOn), since the celebration banner message
-- they also set needs to inspect the current faction/tier/type
-- selection -- see BuildCelebrationMessage there for why.

local function DrawConfetti()
    if not confettiActive then return end
    local elapsed = spDiffTimers(spGetTimer(), confettiStartTime)
    if elapsed >= CONFETTI_DURATION then
        confettiActive = false
        fireworkBursts = {}
        return
    end

    local alpha = 1
    local fadeStart = CONFETTI_DURATION - CONFETTI_FADE
    if elapsed > fadeStart then
        alpha = math.max(0, 1 - (elapsed - fadeStart) / CONFETTI_FADE)
    end

    for _, p in ipairs(confettiParticles) do
        local x = p.x0 + p.vx * elapsed
        local y = p.y0 + p.vy0 * elapsed - 0.5 * CONFETTI_GRAVITY * elapsed * elapsed
        local rot = p.spin0 + p.spinSpeed * elapsed
        gl.PushMatrix()
        gl.Translate(x, y, 0)
        gl.Rotate(rot, 0, 0, 1)
        gl.Color(p.color[1], p.color[2], p.color[3], alpha)
        gl.Rect(-p.size / 2, -p.size * 0.45, p.size / 2, p.size * 0.45)
        gl.PopMatrix()
    end

    for _, burst in ipairs(fireworkBursts) do
        local localT = elapsed - burst.t0
        if localT >= 0 and localT < FIREWORK_LIFETIME then
            local burstAlpha = (1 - localT / FIREWORK_LIFETIME) * alpha
            gl.Color(burst.color[1], burst.color[2], burst.color[3], burstAlpha)
            for _, sp in ipairs(burst.particles) do
                local x = burst.x + sp.vx * localT
                local y = burst.y + sp.vy * localT - 0.5 * FIREWORK_GRAVITY * localT * localT
                gl.Rect(x - FIREWORK_SPARK_SIZE, y - FIREWORK_SPARK_SIZE,
                    x + FIREWORK_SPARK_SIZE, y + FIREWORK_SPARK_SIZE)
            end
        end
    end

    gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- TIER DETECTION (ported from gui_battle_tracker.lua's UnitTechLevel)
--------------------------------------------------------------------------------

local function UnitTechLevel(ud)
    if not ud then return 1 end
    local cp = ud.customParams
    local tl = cp and tonumber(cp.techlevel)
    if tl then
        -- Round 16: a handful of real buildings (amphibious sub pens,
        -- hover/seaplane platforms -- armamsub/armfhp/armhp/armplat and
        -- their Cortex equivalents) carry customParams.techlevel = 1.5,
        -- BAR's own "available from T1, bridges into T2" convention for
        -- these specific structures. TIERS in this widget is only
        -- {1, 2, 3} -- a bare 1.5 never equals any of those, so every one
        -- of these buildings was silently unselectable in EVERY tier,
        -- forever (found via a live roster-count diagnostic: they showed
        -- up as "odd tier" entries never bucketed into T1/T2/T3 at all).
        -- Floored down to the tier they're actually available at (T1),
        -- rather than up, since none of them need a T2 lab prerequisite.
        local tier = math.floor(tl)

        -- Round 16 fix: "Butler is T2, see the official wiki" (and the
        -- same for Cortex's Twitcher). Confirmed directly against the
        -- real game archive: armhack (Butler), corhack (Twitcher),
        -- armhacs (Voyager), armhacv (Consul), corhacs (Pathfinder),
        -- corhacv (Printer), and corhaca (Experimental Construction
        -- Aircraft) all carry customParams.techlevel = 3 -- the tier of
        -- the lab/plant that unlocks them (Experimental Bot Lab /
        -- Experimental Vehicle Plant / Experimental Aircraft Plant,
        -- all real techlevel-3 buildings) -- but customParams.unitgroup
        -- = "buildert2" on every one of them, BAR's own separate marker
        -- for a unit's actual gameplay/cost tier. These are a known real
        -- design pattern: mobile utility constructors costed and
        -- balanced as T2, deliberately gated behind the T3 Experimental
        -- lab rather than the T2 Advanced one. Scanned the ENTIRE real
        -- archive for every unit with a "builder<N>" unitgroup tag and
        -- found exactly these 7 disagree with their own techlevel --
        -- every other buildert1/2/3-tagged constructor already agrees
        -- with its own techlevel, so this correction only ever fires for
        -- this specific family, never for a normal combat unit (which
        -- carries unitgroup = "weapon", no tier digit to conflict with
        -- techlevel in the first place).
        local ug = cp.unitgroup
        local ugTier = ug and ug:match("^buildert?(%d)$")
        ugTier = ugTier and tonumber(ugTier)
        if ugTier and ugTier ~= tier then
            return ugTier
        end
        return tier
    end
    local metal = ud.metalCost or 0
    if metal >= 1800 then
        return 3
    elseif metal >= 350 then
        return 2
    else
        return 1
    end
end

--------------------------------------------------------------------------------
-- TYPE DETECTION (new, round 3)
--------------------------------------------------------------------------------

-- Internal defNames of every faction's own lab/plant/platform/shipyard,
-- mapped to the type bucket of whatever it builds. Sourced from this
-- project's own already-vetted labDisplayNames table
-- (gui_team_base_tracker.lua), cross-referenced by lab purpose.
-- Round 8: armamsub/coramsub/legamphlab ("amphibious complex") deliberately
-- left OUT of this table. Verified against the real game archive that these
-- buildings produce a GENUINE MIX of amphibious bots and amphibious
-- vehicles from the same buildOptions list (e.g. armamsub builds both
-- armjeth/armaak/armdecom, which are real bots, AND armpincer/armbeaver/
-- armcroc, which are real vehicles) -- there is no single correct bucket
-- for "everything this building produces", so bulk-tagging it any one way
-- was always wrong for roughly half its output. Round 8 also removed the
-- fabricated "armapt3" (not a real defName in the live game data) in favor
-- of the real T3 air lab names below, and added every other missing T3
-- lab/plant/shipyard discovered by cross-referencing the real archive.
local LAB_TYPE = {
    -- Bot labs (incl. T3 gantries, which mainly produce T3 bots)
    armlab = "bot", corlab = "bot", leglab = "bot",
    armalab = "bot", coralab = "bot", legalab = "bot",
    armhalab = "bot", corhalab = "bot", leghalab = "bot",
    armshltx = "bot", armshltxuw = "bot",
    corgant = "bot", corgantuw = "bot",

    -- Vehicle plants
    armvp = "vehicle", corvp = "vehicle", legvp = "vehicle",
    armavp = "vehicle", coravp = "vehicle", legavp = "vehicle",
    armhavp = "vehicle", corhavp = "vehicle", leghavp = "vehicle",

    -- Air labs/plants (seaplane platforms build aircraft, so they're
    -- "air" too, not "sea")
    armap = "air", corap = "air", legap = "air",
    armaap = "air", coraap = "air", legaap = "air",
    armhaap = "air", corhaap = "air", armhaapuw = "air", corhaapuw = "air",
    armplat = "air", corplat = "air", legsplab = "air",

    -- Naval/hover (shipyards + hovercraft platforms)
    armhp = "sea", corhp = "sea", leghp = "sea",
    armfhp = "sea", corfhp = "sea", legfhp = "sea",
    armsy = "sea", corsy = "sea", legsy = "sea",
    armhasy = "sea", corhasy = "sea",
    armasy = "sea", corasy = "sea", legadvshipyard = "sea",
}

-- Reverse-maps every lab's real buildOptions (confirmed to be an array
-- of unitDefIDs, not defNames -- see drag_copy_builder.lua's
-- BuilderCanBuildType, which compares buildOptions entries directly
-- against a target unitDefID) to that lab's own type bucket. Built once,
-- cached alongside allUnitsCache.
local function BuildLabTypeMap()
    local map = {}
    for _, ud in pairs(UnitDefs) do
        local bucket = LAB_TYPE[ud.name]
        if bucket and ud.buildOptions then
            for _, buildDefID in ipairs(ud.buildOptions) do
                if not map[buildDefID] then
                    map[buildDefID] = bucket
                end
            end
        end
    end
    return map
end

-- Round 8: BAR's own unit art pipeline tags every real UnitDef with
-- customParams.subfolder (e.g. "ArmBots", "CorVehicles/T2",
-- "ArmBuildings/SeaFactories", "Legion/Hovercraft") -- confirmed directly
-- against the live game archive. This is per-UNIT, authoritative, and
-- immune to the lab-reverse-map's "which of two labs that both build this
-- same unit got scanned first" ambiguity (the actual root cause of
-- vehicles/mines leaking into a Bots-only selection -- see round 8 notes).
-- It's checked before the lab map below, which becomes a fallback only
-- for the handful of cases subfolder doesn't disambiguate (chiefly
-- Legion's "Legion/Constructors" and "Legion/T3" buckets, which cover
-- several different chassis types under one folder).
--
-- Round 16 fix: "The Hive" (leghive/legfhive) turned up as a Legion T1
-- Bot instead of a Structure. Confirmed directly against the real game
-- archive: every other Legion static defense (legrl, legflak, etc.) has
-- no canmove field at all (so the engine's own ud.isBuilding ends up
-- true and ClassifyUnitType never even reaches this function for them),
-- but leghive/legfhive explicitly set canmove = true -- presumably for
-- its drone-launch animation -- which makes the engine compute
-- ud.isBuilding = false for just these two, despite them being
-- stationary turrets (maxacc = 0, turnrate = 1, footprint 3x3, no real
-- movement). Their subfolder is "Legion/Defenses" / "Legion/SeaDefenses"
-- (and every other faction's static defenses already match the
-- "buildings" rule above via "ArmBuildings/..."/"CorBuildings/..." --
-- only Legion's defense folder lacks that word), so added a dedicated
-- "defen" match here rather than widening "buildings" itself.
local function SubfolderBucket(ud)
    local cp = ud.customParams
    local sf = cp and cp.subfolder
    if not sf then return nil end
    local lower = sf:lower()
    if lower:find("buildings", 1, true) then return "structure" end
    if lower:find("defen", 1, true) then return "structure" end
    if lower:find("gantry", 1, true) then return "bot" end
    if lower:find("bots", 1, true) then return "bot" end
    if lower:find("vehicles", 1, true) then return "vehicle" end
    if lower:find("hovercraft", 1, true) then return "sea" end
    if lower:find("seaplanes", 1, true) then return "air" end
    if lower:find("aircraft", 1, true) then return "air" end
    if lower:find("ships", 1, true) then return "sea" end
    return nil
end

-- Structures are their own bucket (always, regardless of what builds
-- them). customParams.mine is checked explicitly too, as a second safety
-- net -- confirmed via the real armmine1 def that mines have no
-- isFactory/isBuilding flag of their own (round 8). Mobile units are then
-- classified by their own subfolder tag (see SubfolderBucket above),
-- falling back to whichever lab's buildOptions claims them, and finally
-- to the same canFly/floater/canHover movement checks gui_unit_chatter.lua's
-- own classification in this project already relies on, defaulting
-- unclassified mobile ground units to "bot".
local function ClassifyUnitType(ud, labMap)
    if ud.customParams and ud.customParams.mine then
        return "structure"
    end
    if ud.isFactory or ud.isBuilding then
        return "structure"
    end
    local sfBucket = SubfolderBucket(ud)
    if sfBucket then return sfBucket end
    local bucket = labMap[ud.id]
    if bucket then return bucket end
    if ud.canFly then return "air" end
    if ud.canHover or ud.floater or (ud.minWaterDepth or 0) > 0 then return "sea" end
    return "bot"
end

--------------------------------------------------------------------------------
-- DISPLAY NAME (round 3 fix: ud.humanName can exist but be EMPTY ("") for
-- some units, which is truthy in Lua so a plain `or` fallback never kicks
-- in -- fixed with the fallback chain below: ud.translatedHumanName ->
-- ud.humanName -> ud.name, each checked for non-whitespace content, not
-- just non-nil. Round 7 adds the raw-localization-key guard below)
--------------------------------------------------------------------------------

-- Round 7: a card turned up in-game showing the literal, untranslated
-- string "units.names.arm_leftshoulder_nationwars_..." as its name --
-- clearly a translation lookup key that failed to resolve to real text,
-- leaking out through ud.translatedHumanName on an otherwise normal
-- unit. Real BAR display names are never dotted like this, so NonBlank
-- now also rejects any candidate containing a literal "." -- the chain
-- then correctly falls through past it to humanName, then ud.name,
-- instead of displaying the broken key.
local function NonBlank(s)
    return s and s:match("%S") and not s:find(".", 1, true) and s or nil
end

local function ResolveDisplayName(entry)
    if entry.isCommander then
        return (FACTION_LABEL[entry.faction] or "") .. " Commander"
    end
    local ud = entry.ud
    return NonBlank(ud.translatedHumanName) or NonBlank(ud.humanName) or ud.name
end

--------------------------------------------------------------------------------
-- UNIT ROSTER
--------------------------------------------------------------------------------

-- Scans every UnitDef once, keeping only ones that plausibly belong to a
-- memorizable faction roster: name starts with arm/cor/leg, has real stats
-- (health > 0), and isn't a commander upgrade-level variant (armcomlvl10
-- etc, which would otherwise show up as duplicate "commanders" at every
-- tier). Scavenger/Raptor content never matches the arm/cor/leg prefix so
-- it's excluded automatically, same reasoning gui_eco_graph.lua's
-- DetectFaction and gui_armada_labs_gallery.lua's roster both already rely
-- on.
--
-- Round 7: three more non-real-unit categories turned up in-game and are
-- excluded the same way:
--   - Commander grave/effigy markers (the "R.I.P." tombstone build
--     picture) -- this project's own cmdr_kill_tracker.lua already hard-
--     blacklists these exact defNames for the same reason ("Hard
--     blacklist: respawn pads and effigies" -- armrespawn/correspawn,
--     and anything matching "effigy"), so this reuses that precedent
--     rather than guessing a new one. Round 11 follow-up (user asked to
--     double check this was actually fixed): the real defNames, straight
--     from the archive, are "comeffigylvl1" through "comeffigylvl5" --
--     prefix "com", never "arm"/"cor"/"leg", so they were already caught
--     by the prefix check above on their own, AND by the "lvl%d" check
--     (every one of them is a numbered level), AND by the "effigy"
--     substring check -- triple-redundant, so there's no path for one to
--     reach a card today. Also added a fourth, authoritative check --
--     customParams.iseffigy, a real flag BAR sets on exactly these units
--     -- as a safety net in case a future patch ever adds a per-faction
--     variant that isn't also "com"-prefixed/"lvl"-numbered.
--   - Any entry whose internal name itself is dotted. Real BAR unitDef
--     names are plain identifiers and never contain a ".".
--   - Cosmetic "Nation Wars" skin-pack entries, seen in-game with a
--     perfectly normal internal name but their translatedHumanName
--     literally reading "units.names.arm_leftshoulder_nationwars_..."
--     (an unresolved localization key), plus nonsense placeholder stats
--     (1000/10000/10000/5,600,000). Matched narrowly on the exact
--     "units.names." prefix actually observed, rather than "any dot
--     anywhere in a display string" -- a real human-readable name
--     legitimately CAN contain a period (an abbreviation like "Veh."),
--     so that broader check is only used as a display-fallback skip in
--     ResolveDisplayName below, never to drop a whole unit from the
--     roster.
--
-- Round 10: each faction has MULTIPLE real, separate UnitDefs all flagged
-- customParams.iscommander = true, not just the one base commander and
-- its numbered upgrade levels (already excluded by the "lvl%d" check
-- above). Confirmed against the real archive: Armada alone has armcom
-- (the base commander), armcomcon, AND armcomnew -- three distinct
-- UnitDefIDs, none of them "lvl%d"-named, so none were being filtered
-- out. armcomcon even sets customParams.i18nfromunit = "armcom", BAR's
-- own way of saying "show this unit's name as armcom's name" -- i.e. the
-- game itself treats these as the same conceptual unit for display
-- purposes, not three different things to learn. Since ResolveDisplayName
-- already collapses every commander down to "<Faction> Commander"
-- regardless of which of these IDs it is, having all three in the roster
-- meant the commander card was silently 2-3x overrepresented in every
-- faction's pool -- the actual cause of the user's "I saw Armada
-- Commander like 5 times" report.
--
-- Only one commander survives per faction now, chosen deterministically
-- (not by whatever order pairs(UnitDefs) happens to visit things in,
-- which Lua never guarantees): prefer whichever candidate is NOT marked
-- as an i18nfromunit alias of another unit (i.e. prefer the canonical
-- one BAR's own data points at), then the lowest unitDefID as a stable
-- tiebreak. Which physical ID wins doesn't change what the user sees --
-- every commander variant displays identically -- this is purely so the
-- choice doesn't flap between runs.
--
-- Round 11: the user saw what looked like "Beaver" listed twice under
-- Armada/T1/Vehicles -- one copy correctly named "Beaver", the other
-- showing as "Assist Vehicle". These are two different real UnitDefs,
-- not one unit with a flaky name: armbeaver is the real amphibious
-- construction vehicle, while armassistdrone_land is a separate,
-- modoption-gated helper unit (confirmed via its own data -- it's
-- spawned by luarules/gadgets/game_assistdronespawn.lua, its
-- metalcost/energycost are both 1, and its workertime is computed from
-- Spring.GetModOptions().assistdronesbuildpowermultiplier -- none of
-- which describes a real, player-built roster unit) that simply reuses
-- Beaver's own buildpic (buildpic = "ARMBEAVER.DDS") and animation
-- script (script = "Units/ARMBEAVER.cob"), which is exactly why it
-- looked like a second Beaver instead of an unrelated unit. Every
-- faction has the same pair (armassistdrone/armassistdrone_land,
-- corassistdrone/corassistdrone_land, legassistdrone/legassistdrone_land
-- -- a flying one and a ground one), all excluded the same way the
-- effigy/respawn pad already are: by name, since "assistdrone" never
-- appears in a real unit's defName otherwise.
-- Round 16: commander cosmetic hats/decorations (Viking Helmet, the Fight
-- Night boxing-glove costumes nicknamed "#1 Grunt"/"#1 Goblin", the Spooky
-- Pumpkin, PtaQ's Hat, Hornet's Tricorn, the Nation Wars shoulder pads,
-- etc) are real UnitDefs in BAR's own data -- confirmed directly against
-- the live game archive's units/other/hats/commander_cosmetics.lua -- not
-- props with a zero/negative health that the existing checks would catch.
-- They pass every filter above: arm/cor/leg-prefixed name (they reuse a
-- faction's prefix purely for their reused texture, e.g. "cor_hat_viking"),
-- health = 5,600,000 (so it never dies and never blocks a capture), no
-- "lvl%d", not hidden, no dot, not an effigy, not a commander, no raw
-- localization key, not an assistdrone. That's exactly why they were
-- slipping through to show up as flashcards with a nonsense name and the
-- generic "no real buildpic" placeholder (the "R.I.P. tombstone" look the
-- user reported for all three).
--
-- BAR's own data tags every one of these with customParams.decoration (a
-- real flag the engine itself uses to keep them out of the normal build
-- menu) and customParams.subfolder = "other/hats" -- both checked here as
-- belt-and-suspenders, same "two independent real flags" precedent as the
-- effigy exclusion above.
local function IsCosmeticDecoration(ud)
    local cp = ud.customParams
    if not cp then return false end
    if cp.decoration then return true end
    local sf = cp.subfolder
    if sf and sf:lower():find("hats", 1, true) then return true end
    return false
end

local function BuildAllUnitsCache()
    local labMap = BuildLabTypeMap()
    local list = {}
    local bestCommander = {}        -- [faction] = chosen entry so far
    local bestCommanderIsAlias = {} -- [faction] = is that entry an i18nfromunit alias?
    for unitDefID, ud in pairs(UnitDefs) do
        local name = ud.name
        local prefix = name and name:sub(1, 3)
        local isCommander = (ud.customParams and ud.customParams.iscommander) and true or false
        -- Round 16 follow-up: "decoy commander is hard to differentiate
        -- with the original just basing on the icon" -- a prior fix in
        -- this same round gave these a corrected "<Faction> Decoy
        -- Commander" label instead of the bare, ambiguous "Commander"
        -- their real translatedHumanName carries, but the user's actual
        -- preference (once they saw it in-game) is simpler: since the
        -- decoy's whole purpose is to be visually indistinguishable from
        -- the real commander on its build picture, a text label doesn't
        -- really fix the flashcard experience -- so these are now
        -- omitted from the roster entirely, same treatment as the
        -- commander cosmetic hats above.
        local isDecoyCommander = (ud.customParams and ud.customParams.isdecoycommander) and true or false
        if name and (prefix == "arm" or prefix == "cor" or prefix == "leg")
            and (ud.health or 0) > 0
            and not name:match("lvl%d")
            and not (ud.customParams and ud.customParams.hidden)
            and not name:find(".", 1, true)
            and not name:find("effigy")
            and not (ud.customParams and ud.customParams.iseffigy)
            and name ~= "armrespawn" and name ~= "correspawn"
            and not (ud.translatedHumanName and ud.translatedHumanName:find("units.names.", 1, true))
            and not name:find("assistdrone", 1, true)
            and not IsCosmeticDecoration(ud)
            and not isDecoyCommander
        then
            if isCommander then
                local isAlias = (ud.customParams and ud.customParams.i18nfromunit) and true or false
                local current = bestCommander[prefix]
                local shouldReplace = not current
                if current then
                    local currentIsAlias = bestCommanderIsAlias[prefix]
                    if currentIsAlias and not isAlias then
                        shouldReplace = true
                    elseif currentIsAlias == isAlias and unitDefID < current.id then
                        shouldReplace = true
                    end
                end
                if shouldReplace then
                    bestCommander[prefix] = {
                        id          = unitDefID,
                        name        = name,
                        faction     = prefix,
                        tier        = UnitTechLevel(ud),
                        unitType    = ClassifyUnitType(ud, labMap),
                        isCommander = true,
                        ud          = ud,
                    }
                    bestCommanderIsAlias[prefix] = isAlias
                end
            else
                list[#list + 1] = {
                    id          = unitDefID,
                    name        = name,
                    faction     = prefix,
                    tier        = UnitTechLevel(ud),
                    unitType    = ClassifyUnitType(ud, labMap),
                    isCommander = false,
                    ud          = ud,
                }
            end
        end
    end
    for _, entry in pairs(bestCommander) do
        list[#list + 1] = entry
    end
    return list, labMap
end

local function AnyTypeSelected()
    for _, t in ipairs(TYPES) do
        if typeSelection[t] then return true end
    end
    return false
end

local function RebuildDeckPool()
    if not allUnitsCache then
        allUnitsCache, labTypeByID = BuildAllUnitsCache()
    end
    deckPool = {}
    local typeActive = AnyTypeSelected()
    for _, entry in ipairs(allUnitsCache) do
        if selection[entry.faction] and selection[entry.faction][entry.tier] then
            if (not typeActive) or typeSelection[entry.unitType] then
                deckPool[#deckPool + 1] = entry
            end
        end
    end
end

local function AnySelected()
    for _, f in ipairs(FACTIONS) do
        for _, t in ipairs(TIERS) do
            if selection[f][t] then return true end
        end
    end
    return false
end

local function AllCellsOn()
    for _, f in ipairs(FACTIONS) do
        for _, t in ipairs(TIERS) do
            if not selection[f][t] then return false end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- CELEBRATION MESSAGE (round 15: "put in pop up... large fonts along with
-- confetti and fireworks" -- a big banner line to go with the burst,
-- picked to match whatever faction/tier/type combination was actually
-- being quizzed. Lives here, after AllCellsOn/AnySelected/AnyTypeSelected,
-- because it needs all three; MaybeTriggerConfetti/StopConfetti (which
-- set/clear it) moved down here with it so everything about the
-- celebration's CONTENT is in one place -- the confetti/fireworks
-- PARTICLE mechanics above don't need any of this and stay put.
--------------------------------------------------------------------------------

local function PickRandom(pool)
    return pool[math.random(#pool)]
end

-- The exact line from the user's own request -- kept as a single-entry
-- "pool" (rather than a plain string) so it draws through PickRandom the
-- same way every other message tier does, in case more get added later.
local ALL_RANDOM_MESSAGES = {
    "Oh my God, you the BEST BAR Nerd in the Universe!",
}

-- T3: "say something like 'Wow you're pretty high level BAR gamer.'"
local T3_MESSAGES = {
    "Wow, you're pretty high level BAR gamer.",
    "T3 mastery, confirmed -- nobody's sneaking an experimental past you.",
    "That's some serious lategame unit knowledge right there.",
    "Look at you, casually naming endgame tech like it's nothing.",
    "You've clearly reclaimed a few wrecks learning these.",
}

-- A single faction + single tier + no type filter (or every type filter
-- individually on, same effective thing) -- the WHOLE lineup for that
-- faction/tier, not just one category of it. %s = faction label, %d = tier.
local FULL_ROSTER_MESSAGES = {
    "You know your whole %s T%d lineup, top to bottom.",
    "%s T%d roster? Memorized. Nicely done.",
    "Every %s T%d unit, no sweat.",
    "%s T%d, front to back -- not a single miss.",
}

-- A single faction + single tier + 2-4 (but not all 5) types selected.
local MIXED_TYPE_MESSAGES = {
    "Solid mixed bag of %s T%d know-how.",
    "%s T%d, several categories deep -- impressive.",
    "Bots, vehicles, whatever -- your %s T%d game is tight.",
}

-- All three factions but only one tier. %d = tier.
local ALL_FACTIONS_ONE_TIER_MESSAGES = {
    "All three factions' T%d units, nailed. Faction-blind and proud of it.",
}

-- One faction across all three tiers. %s = faction label.
local ONE_FACTION_ALL_TIERS_MESSAGES = {
    "%s, start to finish -- T1 through T3, all correct.",
}

-- Any other broad mix of factions/tiers that isn't literally "All
-- Factions Random" -- the "put other things... make up other stuff"
-- catch-all between the clean single-combo lines above and the ultimate
-- all-random line.
local BROAD_MESSAGES = {
    "That covers a lot of ground -- nicely done.",
    "Multiple factions, zero mistakes. Respect.",
    "You're not just a specialist, you're a BAR generalist.",
    "Factions, tiers, whatever we threw at you -- nailed it.",
}

-- Which factions/tiers currently have at least one cell on. facCount == 1
-- and tierCount == 1 TOGETHER mean exactly one (faction, tier) cell is
-- selected -- the one active faction can only pair with the one active
-- tier, so there's nothing else it could be.
local function ActiveFactionsAndTiers()
    local facSet, tierSet = {}, {}
    local facCount, tierCount = 0, 0
    for _, f in ipairs(FACTIONS) do
        local any = false
        for _, t in ipairs(TIERS) do
            if selection[f][t] then any = true end
        end
        if any then
            facSet[f] = true
            facCount = facCount + 1
        end
    end
    for _, t in ipairs(TIERS) do
        local any = false
        for _, f in ipairs(FACTIONS) do
            if selection[f][t] then any = true end
        end
        if any then
            tierSet[t] = true
            tierCount = tierCount + 1
        end
    end
    return facSet, facCount, tierSet, tierCount
end

-- Picks the banner line for whatever selection was just quizzed. Called
-- once, from MaybeTriggerConfetti, at the same moment the confetti and
-- fireworks are built -- so it reads the selection state exactly as it
-- stood for the round that just finished.
local function BuildCelebrationMessage()
    if AllCellsOn() then
        return PickRandom(ALL_RANDOM_MESSAGES)
    end

    local facSet, facCount, tierSet, tierCount = ActiveFactionsAndTiers()

    if facCount == 1 and tierCount == 3 then
        return string.format(PickRandom(ONE_FACTION_ALL_TIERS_MESSAGES), FACTION_LABEL[next(facSet)])
    end
    if facCount == 3 and tierCount == 1 then
        return string.format(PickRandom(ALL_FACTIONS_ONE_TIER_MESSAGES), next(tierSet))
    end
    if facCount ~= 1 or tierCount ~= 1 then
        return PickRandom(BROAD_MESSAGES)
    end

    -- Exactly one (faction, tier) cell selected.
    local facLabel = FACTION_LABEL[next(facSet)]
    local tier = next(tierSet)

    if tier == 3 then
        return PickRandom(T3_MESSAGES)
    end

    local typeCount = 0
    local activeType = nil
    for _, t in ipairs(TYPES) do
        if typeSelection[t] then
            typeCount = typeCount + 1
            activeType = t
        end
    end

    if typeCount == 1 then
        return "You know your " .. facLabel .. " " .. TYPE_LABEL[activeType] .. "!"
    elseif typeCount == 0 or typeCount == 5 then
        return string.format(PickRandom(FULL_ROSTER_MESSAGES), facLabel, tier)
    else
        return string.format(PickRandom(MIXED_TYPE_MESSAGES), facLabel, tier)
    end
end

-- Triggered right where DrawNextCard ends a quiz round (quizFinished set
-- true) -- that transition only happens once per completed round (see
-- DrawNextCard's own comment), so this never needs its own re-trigger
-- guard. Does nothing on anything less than a perfect score.
-- Round 15 fix: "if i don't pick a choice it will flip the card and go on
-- to the next... so if i only chose 1 ... and currently have 1/1, then i
-- don't choose anything but keep clicking the cards until the whole quiz
-- is done i get a 1/1 ... but i didnt really take the quiz i just
-- answered 1 time." quizScore.total only counts cards actually ANSWERED
-- via PickQuizChoice -- flipping/skipping past a card with ActivateCard
-- never touches it. So "correct == total" alone was true for a 1-card
-- quiz where every OTHER card in a 10-card round was just clicked through
-- unanswered: 1/1 looks identical to a real 1-card round. Perfect now
-- also requires every card the round actually dealt (#quizDeck) to have
-- been answered, not just whichever ones the user bothered to pick.
local function MaybeTriggerConfetti()
    if quizScore.total > 0 and quizScore.correct == quizScore.total and quizScore.total == #quizDeck then
        confettiActive = true
        confettiStartTime = spGetTimer()
        confettiParticles = BuildConfettiParticles()
        fireworkBursts = BuildFireworkBursts()
        celebrationMessage = BuildCelebrationMessage()
    end
end

-- Stops (or prevents) a confetti burst from a PREVIOUS quiz round bleeding
-- into a new one. Called from BuildQuizDeck (every quiz-round restart --
-- toggling quiz on, or the selection changing mid-quiz, per that
-- function's own comment) and from turning quiz mode off entirely.
local function StopConfetti()
    confettiActive = false
    fireworkBursts = {}
    celebrationMessage = nil
end

--------------------------------------------------------------------------------
-- SHUFFLE / DRAW
--------------------------------------------------------------------------------

local function ShuffleCopy(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    for i = #copy, 2, -1 do
        local j = math.random(i)
        copy[i], copy[j] = copy[j], copy[i]
    end
    return copy
end

--------------------------------------------------------------------------------
-- QUIZ MODE (round 5)
--------------------------------------------------------------------------------
-- Decoys are deliberately NOT limited to the current faction/tier/type
-- selection grid -- per the user's own example ("if it's a Tick, don't
-- include a commander or a lab... add random all T1 from 3 factions
-- include T2 and T3, but the obvious like Gantry or T2 Bot Lab should be
-- omitted"), a decoy just has to be the SAME unitType bucket as the real
-- card (bot/vehicle/air/sea/structure, already computed by
-- ClassifyUnitType/BuildAllUnitsCache), pulled from the full roster
-- across every faction and tier. Commanders are excluded from the decoy
-- pool entirely (not just when they'd be the correct answer) since
-- there's only one per faction -- they're "obviously" not confusable with
-- a rank-and-file unit, so including one would be a free giveaway rather
-- than a real test.
local function BuildQuizChoices(entry)
    if not entry or not allUnitsCache then return {} end
    local correctName = ResolveDisplayName(entry)
    local seen = {[correctName] = true}
    local decoyNames = {}
    for _, cand in ipairs(allUnitsCache) do
        if cand.unitType == entry.unitType and not cand.isCommander and cand.id ~= entry.id then
            local dn = ResolveDisplayName(cand)
            if not seen[dn] then
                seen[dn] = true
                decoyNames[#decoyNames + 1] = dn
            end
        end
    end
    decoyNames = ShuffleCopy(decoyNames)

    local choices = {{name = correctName, correct = true}}
    local maxDecoys = QUIZ_CHOICE_TOTAL - 1
    for i = 1, math.min(maxDecoys, #decoyNames) do
        choices[#choices + 1] = {name = decoyNames[i], correct = false}
    end
    -- Round 13: choices are sorted alphabetically rather than shuffled into
    -- a random on-screen order. If you already know the answer, scanning a
    -- shuffled list for it is slower than it needs to be -- alphabetical
    -- means the correct name is always wherever the alphabet puts it, so
    -- you can jump straight to it instead of reading every row. WHICH
    -- decoys get picked is still randomized (ShuffleCopy(decoyNames)
    -- above); only their on-screen order changes here.
    table.sort(choices, function(a, b) return a.name:lower() < b.name:lower() end)
    return choices
end

-- Rebuilds quizChoices for a (possibly nil) card and resets this card's
-- answered/picked state. Called on every new card draw and whenever quiz
-- mode is toggled on, so quizChoices is always either empty (quiz off, or
-- no card) or exactly matches whatever card is currently showing.
local function RefreshQuizChoices(entry)
    quizChoices = (quizMode and entry) and BuildQuizChoices(entry) or {}
    quizAnswered = false
    quizPickedIndex = nil
    quizSkipAttempted = false
end

-- Round 6: shuffles deckPool exactly once into quizDeck -- the finite,
-- no-repeat sequence a quiz round deals from, front-to-back. Called
-- whenever a quiz round (re)starts: toggling quiz mode on, or the
-- faction/tier/type selection changing while a quiz is already running
-- (a changed selection is a different pool, so it starts a fresh round
-- rather than silently mixing old and new cards into the same pass).
local function BuildQuizDeck()
    quizDeck = ShuffleCopy(deckPool)
    quizDeckCursor = 0
    quizFinished = false
    StopConfetti() -- a new round starting clears any leftover burst from the last one
end

-- Draws the next card. Round 6: in quiz mode this deals from the finite
-- quizDeck built by BuildQuizDeck -- once every selected card has been
-- shown, the quiz ends (quizFinished = true, currentCard = nil) instead
-- of reshuffling and continuing forever, so "go through all of the
-- selected" has a real finish line.
--
-- Round 8: free-play (quiz off) now follows the exact same "shuffle once,
-- loop the SAME order forever" rule as quiz mode's deck, instead of
-- reshuffling into a brand-new random order every time it ran out. The
-- old behavior reshuffled on every pass, which meant each pass's last
-- card and the next pass's first card were two independently-random
-- draws from the same pool -- occasionally landing on the exact same
-- card twice in a row (the user's own report: the Armada Commander
-- showing up twice consecutively), with only a same-card check at that
-- one boundary. Reshuffling only once and then replaying that fixed
-- order can never produce a back-to-back repeat at all (every card
-- appears exactly once per lap, so the card right after position N is
-- always a different card from position N), without needing any
-- per-boundary guard. A changed faction/tier/type selection still forces
-- a brand-new shuffle (OnSelectionChanged clears shuffledDeck), since a
-- different pool deserves its own fresh random order.
local function DrawNextCard()
    if quizMode then
        quizDeckCursor = quizDeckCursor + 1
        if quizDeckCursor > #quizDeck then
            currentCard = nil
            flipped = false
            quizFinished = true
            RefreshQuizChoices(nil)
            MaybeTriggerConfetti()
            return
        end
        currentCard = quizDeck[quizDeckCursor]
        flipped = false
        RefreshQuizChoices(currentCard)
        return
    end

    if #deckPool == 0 then
        currentCard = nil
        flipped = false
        RefreshQuizChoices(nil)
        return
    end
    if #deckPool == 1 then
        currentCard = deckPool[1]
        flipped = false
        RefreshQuizChoices(currentCard)
        return
    end
    if #shuffledDeck == 0 then
        -- First deal for this pool (either the very first draw ever, or
        -- the pool just changed and OnSelectionChanged cleared us out):
        -- shuffle once, and guard against the new order's first card
        -- happening to match whatever was already showing.
        shuffledDeck = ShuffleCopy(deckPool)
        if currentCard and shuffledDeck[1] and shuffledDeck[1].id == currentCard.id then
            shuffledDeck[1], shuffledDeck[2] = shuffledDeck[2], shuffledDeck[1]
        end
        deckCursor = 0
    elseif deckCursor >= #shuffledDeck then
        -- Lap complete -- loop back to the start of the SAME shuffled
        -- order rather than reshuffling. No repeat-guard needed here:
        -- the card after this wraparound (shuffledDeck[1]) is never the
        -- same card as the one before it (shuffledDeck[#shuffledDeck]),
        -- since each card appears exactly once per lap.
        deckCursor = 0
    end
    deckCursor = deckCursor + 1
    currentCard = shuffledDeck[deckCursor]
    flipped = false
    RefreshQuizChoices(currentCard)
end

local function OnSelectionChanged()
    RebuildDeckPool()
    shuffledDeck = {}
    deckCursor = 0
    if quizMode then
        quizScore.correct, quizScore.total = 0, 0
        BuildQuizDeck()
    end
    DrawNextCard()
end

--------------------------------------------------------------------------------
-- STATS TEXT (for the flipped/answer face)
--------------------------------------------------------------------------------

-- Returns an ordered list of {label, value} stat lines: metal/energy cost,
-- build time, health always; weapon damage+range only for units that
-- actually carry a weapon (left out entirely for pure economy/eco
-- buildings, per the user's "metal, energy and so on" ask plus the
-- combat-stats option explicitly scoped to "units that have weapons").
local function BuildStatLines(ud)
    local lines = {}
    lines[#lines + 1] = {"Metal",  string.format("%d", ud.metalCost or 0)}
    lines[#lines + 1] = {"Energy", string.format("%d", ud.energyCost or 0)}
    lines[#lines + 1] = {"Build Time", string.format("%d", ud.buildTime or 0)}
    lines[#lines + 1] = {"Health", string.format("%d", ud.health or 0)}

    if ud.weapons and #ud.weapons > 0 then
        local w = ud.weapons[1]
        local wd = w and w.weaponDef and WeaponDefs[w.weaponDef]
        if wd then
            local dmg = wd.damages and (wd.damages[0] or 0) or 0
            lines[#lines + 1] = {"Damage", string.format("%d", dmg)}
            lines[#lines + 1] = {"Range", string.format("%d", wd.range or 0)}
        end
    end

    return lines
end

--------------------------------------------------------------------------------
-- TOGGLE ICON (MetalEnergyToggleMenu-style -- round 3: now drawn exactly
-- like that widget's own DrawButton, not just sized/positioned like it)
--------------------------------------------------------------------------------

local function ClampIconPos()
    local vsx, vsy = Spring.GetViewGeometry()
    iconPos.x = math.max(0, math.min(iconPos.x, vsx - ICON.W))
    iconPos.y = math.max(0, math.min(iconPos.y, vsy - ICON.H))
end

local function UpdateIconRect()
    iconRect.x1 = iconPos.x
    iconRect.y1 = iconPos.y
    iconRect.x2 = iconPos.x + ICON.W
    iconRect.y2 = iconPos.y + ICON.H
end

local function DrawIcon()
    UpdateIconRect()
    local x1, y1, x2, y2 = iconRect.x1, iconRect.y1, iconRect.x2, iconRect.y2
    local cx, cy = (x1 + x2) * 0.5, (y1 + y2) * 0.5

    gl.Color(ICON.bgColor[1], ICON.bgColor[2], ICON.bgColor[3], ICON.bgColor[4])
    gl.Rect(x1, y1, x2, y2)

    gl.Color(ICON.borderColor[1], ICON.borderColor[2], ICON.borderColor[3], ICON.borderColor[4])
    gl.Rect(x1, y1, x2, y1 + 1)
    gl.Rect(x1, y2 - 1, x2, y2)

    gl.Color(1, 1, 1, 1)
    gl.Text("Unit", cx, cy + 22, 20, "oc")
    gl.Text("Flashcards", cx, cy + 2, 20, "oc")

    if panelVisible then
        gl.Color(0, 1, 0, 1)
        gl.Text("ON", cx, cy - 26, 26, "oc")
    else
        gl.Color(1, 0, 0, 1)
        gl.Text("OFF", cx, cy - 26, 26, "oc")
    end
    gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- NATIVE BAR PANEL CHROME (round 3 -- "make widget UI same as top bar")
--------------------------------------------------------------------------------

-- The top bar and most of BAR's own native UI draw their panels through
-- WG.FlowUI.Draw.Element/RectRound -- a shared rounded/gradient chrome
-- API other widgets can call into (confirmed call signature -- x1,y1,x2,
-- y2, then 4 corner-rounding flags tl,tr,br,bl, then 8 more args left nil
-- to use FlowUI's own theme colors -- by this project's OWN existing
-- uses of it in gui_silo_command.lua and gui_team_base_tracker.lua,
-- always called the exact same way). Guarded + falls back to a flat rect
-- if FlowUI isn't loaded, same fail-safe convention this project already
-- uses for the same call.
local function DrawPanelChrome(r)
    if WG.FlowUI and WG.FlowUI.Draw and WG.FlowUI.Draw.Element then
        gl.Color(1, 1, 1, 1)
        WG.FlowUI.Draw.Element(r.x1, r.y1, r.x2, r.y2, 1, 1, 1, 1, nil, nil, nil, nil, nil, nil, nil, nil)
    else
        gl.Color(0, 0, 0, 0.72)
        gl.Rect(r.x1, r.y1, r.x2, r.y2)
        gl.Color(1, 1, 1, 0.3)
        gl.LineWidth(1.5)
        gl.PolygonMode(GL.FRONT_AND_BACK, GL.LINE)
        gl.Rect(r.x1, r.y1, r.x2, r.y2)
        gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
        gl.LineWidth(1)
    end
    gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- CASINO-CARD DRAWING
--------------------------------------------------------------------------------

-- Round 16 perf fix: every rounded-rect/gradient/gloss helper below used
-- to pass gl.BeginEnd a brand-new `function() ... end` closure (and, for
-- the corner fans, a freshly-built 4-entry "corners" table) on EVERY
-- call -- and these run every DrawScreen frame for the card frame plus
-- every visible button/cell (up to ~37 of them with Quiz on), for as
-- long as the panel stays open. A function literal written inside a
-- hot call path allocates a new closure object each time it runs, even
-- though the bytecode is shared -- real, continuous Lua GC pressure for
-- a widget meant to sit open for a whole match. Fixed by hoisting each
-- of these closures to a single persistent local created ONCE at
-- widget load, reading its per-call parameters from a small set of
-- shared scratch locals set immediately before each gl.BeginEnd call --
-- same draw calls in the same order, zero closures created after
-- Initialize. The "corners" tables are gone too, replaced with 4
-- explicit calls per rounded rect.
local _rrCx, _rrCy, _rrA0, _rrA1, _rrR = 0, 0, 0, 0, 0
local function _cornerFanVerts()
    gl.Vertex(_rrCx, _rrCy)
    for i = 0, CARD_RADIUS_STEPS do
        local a = math.rad(_rrA0 + (_rrA1 - _rrA0) * (i / CARD_RADIUS_STEPS))
        gl.Vertex(_rrCx + math.cos(a) * _rrR, _rrCy + math.sin(a) * _rrR)
    end
end
local function _drawCornerFan(cx, cy, a0, a1, r)
    _rrCx, _rrCy, _rrA0, _rrA1, _rrR = cx, cy, a0, a1, r
    gl.BeginEnd(GL.TRIANGLE_FAN, _cornerFanVerts)
end

-- A fake-rounded rect: a filled center cross plus a quarter-fan at each
-- corner. Cheap, GL1-safe (no shaders/stencil needed), good enough for a
-- card silhouette at this size.
local function RoundedRect(x1, y1, x2, y2, r, cr, cg, cb, ca)
    gl.Color(cr, cg, cb, ca)
    gl.Rect(x1 + r, y1, x2 - r, y2)
    gl.Rect(x1, y1 + r, x2, y2 - r)
    _drawCornerFan(x1 + r, y1 + r, 180, 270, r)
    _drawCornerFan(x2 - r, y1 + r, 270, 360, r)
    _drawCornerFan(x2 - r, y2 - r, 0,   90,  r)
    _drawCornerFan(x1 + r, y2 - r, 90,  180, r)
end

-- Round 16: "make the UI shinier, make the cards look 3d with maybe a
-- reflection on the card" -- Lighten/Darken nudge a flat color toward
-- white/black by a fixed amount per channel, clamped to [0,1]; the basis
-- for every gradient/gloss helper below.
local function Lighten(cr, cg, cb, amt)
    return math.min(1, cr + amt), math.min(1, cg + amt), math.min(1, cb + amt)
end

local function Darken(cr, cg, cb, amt)
    return math.max(0, cr - amt), math.max(0, cg - amt), math.max(0, cb - amt)
end

-- Round 16 perf fix (see the longer note above _drawCornerFan): a single
-- persistent closure for the "top color at the top edge, bottom color
-- at the bottom edge, full span" gradient quad shape every straight
-- gradient fill below needs -- GradientRoundedRect's two straight-edge
-- strips AND DrawGlossyRect's single flat-rect fill are all exactly
-- this same shape, just with different edges/colors passed in.
local _gqL, _gqR, _gqT, _gqB = 0, 0, 0, 0
local _gqTr, _gqTg, _gqTb, _gqBr, _gqBg, _gqBb, _gqCa = 0, 0, 0, 0, 0, 0, 1
local function _gradQuadVerts()
    gl.Color(_gqTr, _gqTg, _gqTb, _gqCa); gl.Vertex(_gqL, _gqT)
    gl.Color(_gqTr, _gqTg, _gqTb, _gqCa); gl.Vertex(_gqR, _gqT)
    gl.Color(_gqBr, _gqBg, _gqBb, _gqCa); gl.Vertex(_gqR, _gqB)
    gl.Color(_gqBr, _gqBg, _gqBb, _gqCa); gl.Vertex(_gqL, _gqB)
end
local function _drawGradQuad(l, r, t, b, tr, tg, tb, br, bg, bb, ca)
    _gqL, _gqR, _gqT, _gqB = l, r, t, b
    _gqTr, _gqTg, _gqTb, _gqBr, _gqBg, _gqBb, _gqCa = tr, tg, tb, br, bg, bb, ca
    gl.BeginEnd(GL.QUADS, _gradQuadVerts)
end

-- Same shape as RoundedRect, but the fill is a true top-to-bottom gradient
-- (lighter at the top edge, darker at the bottom) instead of one flat
-- color -- reads as a glossy, slightly domed 3D surface rather than a flat
-- painted rectangle. The two straight-edge strips get a real per-vertex
-- gradient (gl.BeginEnd(GL.QUADS) with a different gl.Color before each
-- vertex pair -- standard immediate-mode OpenGL vertex-color
-- interpolation); the 4 corner fans use a single flat color each (whichever
-- of the top/bottom colors that corner is closest to) rather than a true
-- per-vertex gradient on a fan, which would need more context than a
-- reusable helper has -- close enough at the corner radii this panel
-- actually uses (12-16px) to not read as a seam.
local function GradientRoundedRect(x1, y1, x2, y2, r, cr, cg, cb, ca, lightenAmt, darkenAmt)
    lightenAmt = lightenAmt or 0.18
    darkenAmt  = darkenAmt or 0.12
    local tr, tg, tb = Lighten(cr, cg, cb, lightenAmt)
    local br, bg, bb = Darken(cr, cg, cb, darkenAmt)

    _drawGradQuad(x1 + r, x2 - r, y2, y1, tr, tg, tb, br, bg, bb, ca)
    _drawGradQuad(x1, x2, y2 - r, y1 + r, tr, tg, tb, br, bg, bb, ca)

    gl.Color(br, bg, bb, ca); _drawCornerFan(x1 + r, y1 + r, 180, 270, r) -- bottom-left
    gl.Color(br, bg, bb, ca); _drawCornerFan(x2 - r, y1 + r, 270, 360, r) -- bottom-right
    gl.Color(tr, tg, tb, ca); _drawCornerFan(x2 - r, y2 - r, 0,   90,  r) -- top-right
    gl.Color(tr, tg, tb, ca); _drawCornerFan(x1 + r, y2 - r, 90,  180, r) -- top-left
    gl.Color(1, 1, 1, 1)
end

-- Cheap "shinier" retrofit for the panel's flat axis-aligned buttons/cells
-- (faction/tier cells, type cells, All Factions Random, Clear, Quiz
-- toggle, quiz choice buttons) -- same top-lighter/bottom-darker gradient
-- idea as GradientRoundedRect but for a plain (unrounded) rect, plus a
-- thin bright sheen line right at the top edge for a glassier highlight.
-- Reuses _drawGradQuad (same persistent closure GradientRoundedRect's
-- two straight-edge strips use above) rather than its own -- it's the
-- exact same "top color at the top edge, bottom color at the bottom
-- edge, full width" quad shape.
local function DrawGlossyRect(x1, y1, x2, y2, cr, cg, cb, ca)
    local tr, tg, tb = Lighten(cr, cg, cb, 0.16)
    local br, bg, bb = Darken(cr, cg, cb, 0.10)
    _drawGradQuad(x1, x2, y2, y1, tr, tg, tb, br, bg, bb, ca)
    local sheenH = math.min(3, (y2 - y1) * 0.18)
    gl.Color(1, 1, 1, math.min(1, ca * 0.4))
    gl.Rect(x1, y2 - sheenH, x2, y2)
    gl.Color(1, 1, 1, 1)
end

-- Round 16 perf fix: the reflection band's SHAPE (its width, its 5
-- feathered alpha steps, and the half-diagonal it spans) only ever
-- depended on CARD_W/CARD_H/CARD_BORDER, which are fixed constants --
-- never on the card's on-screen position, which gl.Translate below
-- already handles. So none of it needs recomputing per call either;
-- precomputed once here alongside a persistent closure, same technique
-- as the corner-fan/gradient-quad helpers above.
local _reflFaceW = CARD_W - 2 * CARD_BORDER
local _reflFaceH = CARD_H - 2 * CARD_BORDER
local _reflDiag = math.sqrt(_reflFaceW ^ 2 + _reflFaceH ^ 2)
local _reflBandW = _reflFaceW * 0.16
local _reflBandSteps = {
    {off = -_reflBandW * 1.4, a = 0.0},
    {off = -_reflBandW * 0.5, a = 0.16},
    {off = 0,                 a = 0.22},
    {off = _reflBandW * 0.5,  a = 0.16},
    {off = _reflBandW * 1.4,  a = 0.0},
}
local function _reflectionBandVerts()
    for i = 1, #_reflBandSteps - 1 do
        local s0, s1 = _reflBandSteps[i], _reflBandSteps[i + 1]
        gl.Color(1, 1, 1, s0.a); gl.Vertex(s0.off, -_reflDiag)
        gl.Color(1, 1, 1, s1.a); gl.Vertex(s1.off, -_reflDiag)
        gl.Color(1, 1, 1, s1.a); gl.Vertex(s1.off,  _reflDiag)
        gl.Color(1, 1, 1, s0.a); gl.Vertex(s0.off,  _reflDiag)
    end
end

local function DrawCardFrame(x1, y1, x2, y2)
    -- Round 16: a soft drop shadow, offset down-right of the card, drawn
    -- BEFORE everything else so the card appears to sit lifted above the
    -- panel -- a cheap but effective "3D" cue with no shader needed.
    local shadowOffset = 6
    RoundedRect(x1 + shadowOffset, y1 - shadowOffset, x2 + shadowOffset, y2 - shadowOffset, 16, 0, 0, 0, 0.35)

    -- outer gold/red casino border, inner cream face (now a top-lit
    -- gradient instead of one flat cream -- "make the cards look 3d")
    RoundedRect(x1, y1, x2, y2, 16, 0.55, 0.08, 0.08, 1)
    GradientRoundedRect(x1 + CARD_BORDER, y1 + CARD_BORDER, x2 - CARD_BORDER, y2 - CARD_BORDER, 12,
        0.96, 0.94, 0.87, 1, 0.035, 0.12)
        -- ^ barely lightened at the top (the cream is already near-white,
        -- so there's little headroom) but noticeably darkened toward the
        -- bottom -- keeps the face readable while still domed-looking.

    gl.Color(0.85, 0.68, 0.25, 1)
    gl.LineWidth(2)
    gl.PolygonMode(GL.FRONT_AND_BACK, GL.LINE)
    gl.Rect(x1 + CARD_BORDER, y1 + CARD_BORDER, x2 - CARD_BORDER, y2 - CARD_BORDER)
    gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
    gl.LineWidth(1)
    gl.Color(1, 1, 1, 1)

    -- "maybe a reflection on the card" -- a diagonal translucent streak
    -- across the upper-left portion of the face, like light glinting off
    -- glass. Three feathered quads (transparent -> translucent ->
    -- transparent) rotated 35 degrees, drawn with the default additive-ish
    -- white so it only ever brightens, never darkens, whatever's under it.
    local faceX1, faceY1 = x1 + CARD_BORDER, y1 + CARD_BORDER
    local faceX2, faceY2 = x2 - CARD_BORDER, y2 - CARD_BORDER
    local faceCx, faceCy = (faceX1 + faceX2) / 2, (faceY1 + faceY2) / 2
    -- gl.Scissor clips the rotated streak to the card's own (axis-aligned)
    -- face rect -- without it the quads below, which deliberately span the
    -- full diagonal so a 35-degree streak still covers corner to corner,
    -- would bleed out past the card's rounded edges onto whatever sits
    -- behind/around it. Same gl.Scissor(true)/(x,y,w,h)/(false) shape this
    -- project's own gui_eco_graph.lua and gui_dgun_energy_meter.lua already
    -- use for clipped fills.
    gl.Scissor(true)
    gl.Scissor(faceX1, faceY1, faceX2 - faceX1, faceY2 - faceY1)
    gl.PushMatrix()
    gl.Translate(faceCx, faceCy, 0)
    gl.Rotate(35, 0, 0, 1)
    gl.BeginEnd(GL.QUADS, _reflectionBandVerts)
    gl.PopMatrix()
    gl.Scissor(false)
    gl.Color(1, 1, 1, 1)
end

local function DrawCornerPip(x, y, label, color, flip)
    gl.Color(color[1], color[2], color[3], color[4])
    gl.Text(label, x, y, 16, flip and "ro" or "o")
    gl.Color(1, 1, 1, 1)
end

-- Round 16 follow-up: "make the faction names better maybe all caps and
-- larger fonts with shadow, make it look nicer" -- a real drop shadow
-- (not just the existing "o" outline flag, which only thins the font's
-- own edge) drawn as a second, dark, offset copy of the same text
-- underneath the real one -- the standard cheap drop-shadow technique for
-- bitmap/vector text with no per-pixel shader available. Kept general
-- (any text, any color) rather than faction-specific, in case another
-- header wants the same treatment later.
local function DrawTextWithShadow(text, x, y, size, flags, cr, cg, cb, ca, shadowAlpha)
    gl.Color(0, 0, 0, shadowAlpha or 0.55)
    gl.Text(text, x + 2, y - 2, size, flags)
    gl.Color(cr, cg, cb, ca)
    gl.Text(text, x, y, size, flags)
    gl.Color(1, 1, 1, 1)
end

-- gl.GetTextWidth(text) returns a per-font-size-1 width multiplier (same
-- technique already used by gui_armada_labs_gallery.lua / gui_battle_tracker.lua
-- for centering/wrapping) -- used here to shrink the big reveal-name font
-- just enough for long names ("Advanced Fusion Reactor") to still fit the
-- card instead of overflowing it.
local function FitFontSize(text, baseSize, maxWidth, minSize)
    local tw = gl.GetTextWidth(text) * baseSize
    if tw <= maxWidth or tw <= 0 then return baseSize end
    return math.max(minSize, math.floor(baseSize * (maxWidth / tw)))
end

-- Round 15: "put in pop up... large fonts along with confetti and
-- fireworks" -- the big celebratory banner line (content picked by
-- BuildCelebrationMessage, way up near AllCellsOn). Drawn separately from
-- DrawConfetti/the particle burst itself because it needs FitFontSize,
-- which lives down here with the rest of the panel's drawing helpers,
-- well after the confetti/fireworks mechanics in file order. Shares the
-- same elapsed-time/fade-OUT curve as the particle burst (same
-- confettiActive/confettiStartTime/CONFETTI_DURATION/CONFETTI_FADE), with
-- its own quick fade-IN layered on top -- the particles start at full
-- strength immediately, but a full-size wall of text popping in instantly
-- read as jarring, so the text eases in over its first 0.3s instead.
local function DrawCelebrationBanner()
    if not confettiActive or not celebrationMessage then return end
    local elapsed = spDiffTimers(spGetTimer(), confettiStartTime)
    if elapsed >= CONFETTI_DURATION then return end

    local fadeOut = 1
    local fadeStart = CONFETTI_DURATION - CONFETTI_FADE
    if elapsed > fadeStart then
        fadeOut = math.max(0, 1 - (elapsed - fadeStart) / CONFETTI_FADE)
    end
    local fadeIn = math.min(1, elapsed / 0.3)
    local alpha = math.min(fadeIn, fadeOut)

    -- Centered on the whole view (not the panel) so it's never at risk of
    -- clipping off-screen no matter where the panel itself is sitting --
    -- see this round's notes for the alternative (panel-relative) that
    -- was considered instead.
    local vsx, vsy = Spring.GetViewGeometry()
    local fontSize = FitFontSize(celebrationMessage, 48, vsx * 0.85, 22)
    gl.Color(1, 0.95, 0.75, alpha)
    gl.Text(celebrationMessage, vsx / 2, vsy / 2 - fontSize * 0.35, fontSize, "oc")
    gl.Color(1, 1, 1, 1)
end

local function DrawCard(x1, y1, x2, y2, entry)
    DrawCardFrame(x1, y1, x2, y2)

    if not entry then
        -- Round 6: quizFinished only means "finished" when a quiz with a
        -- real (non-empty) pool actually ran to completion -- an empty
        -- selection should still say "No units selected", not announce a
        -- false "Quiz Complete! 0/0".
        gl.Color(0.4, 0.4, 0.4, 1)
        local msg = (quizFinished and #deckPool > 0)
            and ("Quiz Complete!  Score " .. quizScore.correct .. "/" .. quizScore.total)
            or "No units selected"
        gl.Text(msg, (x1 + x2) / 2, (y1 + y2) / 2, 14, "oc")
        gl.Color(1, 1, 1, 1)
        return
    end

    local color = FACTION_COLOR[entry.faction] or {1, 1, 1, 1}
    local pipText = FACTION_LABEL[entry.faction]:sub(1, 1) .. " " .. TIER_LABEL[entry.tier]
    DrawCornerPip(x1 + CARD_BORDER + 8, y2 - CARD_BORDER - 18, pipText, color, false)
    DrawCornerPip(x2 - CARD_BORDER - 8, y1 + CARD_BORDER + 8, pipText, color, true)

    if not flipped then
        -- QUESTION FACE: just the build picture, large, centered, and
        -- kept at 1:1 (round 3 fix -- build pictures are square and
        -- stretching them to fill a non-square available area visibly
        -- skewed them; now a square sub-rect sized to the SMALLER of
        -- the available width/height is centered in the space instead).
        local pad = CARD_BORDER + 28
        local availX1, availY1 = x1 + pad, y1 + pad + 30
        local availX2, availY2 = x2 - pad, y2 - pad - 10
        local side = math.min(availX2 - availX1, availY2 - availY1)
        local acx, acy = (availX1 + availX2) / 2, (availY1 + availY2) / 2
        local ix1, iy1 = acx - side / 2, acy - side / 2
        local ix2, iy2 = acx + side / 2, acy + side / 2

        gl.Color(1, 1, 1, 1)
        gl.Texture("#" .. entry.id)
        gl.TexRect(ix1, iy1, ix2, iy2)
        gl.Texture(false)

        gl.Color(0.35, 0.33, 0.28, 1)
        gl.Text(TIER_LABEL[entry.tier], (x1 + x2) / 2, y1 + CARD_BORDER + 14, 13, "oc")
        gl.Color(1, 1, 1, 1)
    else
        -- ANSWER FACE: small "Armada T1" category line on top, then the
        -- unit/structure's actual resolved name, then the stat block.
        -- Round 5 fix: the name now sits vertically CENTERED in the gap
        -- between the category line and the first stat line, instead of
        -- a fixed distance below the category line -- it was crowding
        -- the top of the card. Stat layout (lines/startY) is computed
        -- first so the name's midpoint can be measured against it.
        local lines = BuildStatLines(entry.ud)
        local lineH = 24
        local startY = (y1 + y2) / 2 + (#lines * lineH) / 2 - lineH

        local categoryY = y2 - CARD_BORDER - 24
        gl.Color(0.45, 0.42, 0.35, 1)
        gl.Text(FACTION_LABEL[entry.faction] .. " " .. TIER_LABEL[entry.tier],
            (x1 + x2) / 2, categoryY, 13, "oc")

        local displayName = ResolveDisplayName(entry)
        local maxNameWidth = CARD_W - 2 * CARD_BORDER - 16
        local nameFontSize = FitFontSize(displayName, 34, maxNameWidth, 16)
        local nameY = (categoryY + startY) / 2

        gl.Color(0.1, 0.1, 0.1, 1)
        gl.Text(displayName, (x1 + x2) / 2, nameY, nameFontSize, "oc")
        gl.Color(1, 1, 1, 1)

        gl.Color(0.2, 0.2, 0.2, 1)
        for i, stat in ipairs(lines) do
            gl.Text(stat[1] .. ":", x1 + CARD_BORDER + 24, startY - (i - 1) * lineH, 14, "o")
            gl.Text(stat[2], x2 - CARD_BORDER - 24, startY - (i - 1) * lineH, 14, "ro")
        end
        gl.Color(1, 1, 1, 1)
    end
end

--------------------------------------------------------------------------------
-- PANEL (faction/tier picker, type picker, all-random toggle, card)
--------------------------------------------------------------------------------

local PANEL_PAD   = 18
local CELL_W, CELL_H = 54, 28
local CELL_GAP    = 4
local COL_GAP     = 14
local TYPE_CELL_H = 24
local TYPE_GAP    = 6
local SECTION_GAP = 10
local DRAG_HEADER_H = 34 -- round 16: was 28; enlarged to comfortably fit the
-- title at font size 20 (matching the icon's own "Unit"/"Flashcards" font
-- size) -- the old 14px title left plenty of headroom in a 28px strip, but
-- 20px needs more. Keeps the same (headerH - fontSize) / 2 = 7px top/bottom
-- margin the old 28/14 pairing had (28-14=14, 34-20=14 -- same split), so
-- the title y-offset below didn't need to change, only the header height.
local COL_LABEL_H = 22 -- round 16 follow-up: was 18; grown 4px so the
-- enlarged, all-caps, shadowed faction labels (ARMADA/CORTEX/LEGION, font
-- 13 -> 16) have room above the tier grid without poking into the drag
-- header strip above them.
local ALLRANDOM_H = 30
local HINT_H      = 20
local CLOSE_BTN_W = 28
local CLEAR_BTN_W = 70

-- Quiz mode layout (round 5): a toggle bar below "All Factions Random",
-- and two columns of QUIZ_PER_SIDE choice rows flanking the card. The
-- columns only exist (and only widen the panel) while quizMode is on.
-- Round 6: widened from 150 to 180 and the choice font raised (see
-- FitFontSize call in DrawPanel) -- 20 choices in a narrow column meant
-- FitFontSize was shrinking long names down near its own floor, and this
-- engine's bitmap font looks pixelated/blurry at very small point sizes.
local QUIZ_BAR_H   = 30
local QUIZ_COL_W   = 180
local QUIZ_COL_GAP = 10
local QUIZ_ROW_H   = 38
local QUIZ_ROW_GAP = 4

-- Round 4 fix: ClampPanelPos() used to clamp against a placeholder
-- 200x200 floor while the panel's REAL rendered size is ~574x616 (card
-- alone is 300x420). That let panelPos.y sit high enough that the drag
-- header -- a 28px strip at the panel's TOP, its only drag handle -- was
-- pushed above the visible viewport and became unreachable by the mouse:
-- "the window is partly off the screen and i can't drag it down." Fixed
-- by computing the real size (ComputePanelSize) and clamping and laying
-- out against that shared value instead of a guessed floor. Round 5:
-- panel size now also depends on quizMode (the choice columns need extra
-- width), so this is no longer cached at load time -- it's recomputed on
-- every call, which is cheap (pure arithmetic, no loops over game data).
local function ComputePanelSize()
    local gridW = (#FACTIONS * #TIERS * CELL_W) + (#FACTIONS * #TIERS - 1) * CELL_GAP
        + (#FACTIONS - 1) * (COL_GAP - CELL_GAP)
    local cardAreaW = CARD_W
    if quizMode then
        cardAreaW = CARD_W + 2 * (QUIZ_COL_W + QUIZ_COL_GAP)
    end
    -- Round 13: the type row (Bots/Vehicles/Air/Sea/Structures) always
    -- stretches to fill the panel's full width -- same edges as "All
    -- Factions Random"/"Quiz" below it -- so it's no longer a candidate
    -- driver of panelW here (it just follows whatever panelW ends up
    -- being; see LayoutPanel).
    local panelW = math.max(gridW + PANEL_PAD * 2, cardAreaW + PANEL_PAD * 2)

    local panelH = DRAG_HEADER_H + COL_LABEL_H + CELL_H + SECTION_GAP
        + TYPE_CELL_H + SECTION_GAP
        + ALLRANDOM_H + SECTION_GAP
        + QUIZ_BAR_H + SECTION_GAP
        + CARD_H + PANEL_PAD + HINT_H

    return panelW, panelH
end

local function ClampPanelPos()
    local vsx, vsy = Spring.GetViewGeometry()
    local panelW, panelH = ComputePanelSize()
    panelPos.x = math.max(0, math.min(panelPos.x, math.max(0, vsx - panelW)))
    panelPos.y = math.max(0, math.min(panelPos.y, math.max(0, vsy - panelH)))
end

local function LayoutPanel()
    panelRects = {factionCells = {}, typeCells = {}, quizChoices = {}, allRandom = nil, clearBtn = nil, quizToggle = nil, card = nil, dragHeader = nil, closeBtn = nil}

    local gridW = (#FACTIONS * #TIERS * CELL_W) + (#FACTIONS * #TIERS - 1) * CELL_GAP
        + (#FACTIONS - 1) * (COL_GAP - CELL_GAP)
    local panelW, panelH = ComputePanelSize()
    -- Round 13: the type row now always stretches edge-to-edge to match
    -- "All Factions Random"/"Quiz" below it ("increase horizontal length
    -- of all buttons ... to match length of all factions random and Quiz
    -- buttons"), instead of a fixed per-cell width centered in whatever
    -- space was left over. Its width is derived FROM panelW (already
    -- settled by ComputePanelSize above) rather than being an input to
    -- it, so it can never itself grow the panel.
    local typeRowW = panelW - PANEL_PAD * 2
    local typeCellW = (typeRowW - (#TYPES - 1) * TYPE_GAP) / #TYPES

    local x1, y1 = panelPos.x, panelPos.y
    local x2, y2 = x1 + panelW, y1 + panelH
    panelRects.bounds = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}

    panelRects.dragHeader = {x1 = x1, y1 = y2 - DRAG_HEADER_H, x2 = x2, y2 = y2}
    panelRects.closeBtn = {
        x1 = x2 - CLOSE_BTN_W, y1 = y2 - DRAG_HEADER_H,
        x2 = x2, y2 = y2,
    }

    -- faction/tier grid, columns left-to-right Armada/Cortex/Legion
    local gridTop = y2 - DRAG_HEADER_H - COL_LABEL_H
    local gx = x1 + (panelW - gridW) / 2
    for fi, f in ipairs(FACTIONS) do
        for ti, t in ipairs(TIERS) do
            local cx1 = gx + ((fi - 1) * #TIERS + (ti - 1)) * (CELL_W + CELL_GAP)
                + (fi - 1) * (COL_GAP - CELL_GAP)
            local cy1 = gridTop - CELL_H
            panelRects.factionCells[#panelRects.factionCells + 1] = {
                x1 = cx1, y1 = cy1, x2 = cx1 + CELL_W, y2 = cy1 + CELL_H,
                faction = f, tier = t,
            }
        end
    end

    -- type toggle row (Bots/Vehicles/Air/Sea/Structures) -- stretched to
    -- fill the same left/right edges as the full-width bars below it.
    local typeRowY2 = gridTop - CELL_H - SECTION_GAP
    local tx = x1 + PANEL_PAD
    for ti, t in ipairs(TYPES) do
        local cx1 = tx + (ti - 1) * (typeCellW + TYPE_GAP)
        local cy1 = typeRowY2 - TYPE_CELL_H
        panelRects.typeCells[#panelRects.typeCells + 1] = {
            x1 = cx1, y1 = cy1, x2 = cx1 + typeCellW, y2 = cy1 + TYPE_CELL_H,
            unitType = t,
        }
    end

    -- All Factions Random toggle, sharing its row with a "Clear" button
    -- (round 13: "add a [Clear] so all selections are deselected") --
    -- Clear gets a fixed-width slot on the right, All Factions Random
    -- fills the rest, same left edge and height as before.
    local allRandomY2 = typeRowY2 - TYPE_CELL_H - SECTION_GAP
    panelRects.clearBtn = {
        x1 = x2 - PANEL_PAD - CLEAR_BTN_W, y1 = allRandomY2 - ALLRANDOM_H,
        x2 = x2 - PANEL_PAD, y2 = allRandomY2,
    }
    panelRects.allRandom = {
        x1 = x1 + PANEL_PAD, y1 = allRandomY2 - ALLRANDOM_H,
        x2 = panelRects.clearBtn.x1 - TYPE_GAP, y2 = allRandomY2,
    }

    -- Quiz toggle bar (round 5), directly below All Factions Random
    local quizBarY2 = allRandomY2 - ALLRANDOM_H - SECTION_GAP
    panelRects.quizToggle = {
        x1 = x1 + PANEL_PAD, y1 = quizBarY2 - QUIZ_BAR_H,
        x2 = x2 - PANEL_PAD, y2 = quizBarY2,
    }

    -- card, bottom-anchored (leaves room for the hint line under it)
    local cardX1 = x1 + (panelW - CARD_W) / 2
    local cardY1 = y1 + PANEL_PAD + HINT_H
    panelRects.card = {x1 = cardX1, y1 = cardY1, x2 = cardX1 + CARD_W, y2 = cardY1 + CARD_H}

    -- Quiz choice columns (round 5), flanking the card -- QUIZ_PER_SIDE
    -- rows each, top-aligned with the card's own top edge. These are
    -- purely geometric slots; DrawPanel zips them against quizChoices by
    -- index, so a shorter choice list (fewer decoys available than
    -- QUIZ_CHOICE_TOTAL-1) just leaves the extra slots undrawn.
    if quizMode then
        for side = 1, 2 do
            local colX1, colX2
            if side == 1 then
                colX1, colX2 = x1 + PANEL_PAD, cardX1 - QUIZ_COL_GAP
            else
                colX1, colX2 = cardX1 + CARD_W + QUIZ_COL_GAP, x2 - PANEL_PAD
            end
            for row = 1, QUIZ_PER_SIDE do
                local ry2 = (cardY1 + CARD_H) - (row - 1) * (QUIZ_ROW_H + QUIZ_ROW_GAP)
                local ry1 = ry2 - QUIZ_ROW_H
                panelRects.quizChoices[#panelRects.quizChoices + 1] = {
                    x1 = colX1, y1 = ry1, x2 = colX2, y2 = ry2,
                }
            end
        end
    end

    return panelW, panelH
end

-- Round 16 perf fix: LayoutPanel() above rebuilds roughly 40 small rect
-- tables from scratch every time it runs (bounds, dragHeader, closeBtn,
-- every faction/tier cell, every type cell, allRandom, clearBtn,
-- quizToggle, card, and up to 20 quiz-choice rects). DrawPanel used to
-- call it unconditionally on EVERY DrawScreen frame while the panel was
-- open -- continuous table allocation (and Lua GC pressure) every
-- single frame for as long as the panel stayed open, even though
-- nothing that actually affects the geometry was changing most of
-- those frames. Given a fixed panelPos and quizMode, LayoutPanel's
-- output never changes (it's pure math from those two plus static
-- constants) -- so this only re-runs it when either has actually moved
-- since the last frame (an active drag, a quiz toggle, or the very
-- first frame), and simply reuses the existing panelRects the rest of
-- the time. LayoutPanel itself is untouched and still always
-- recomputes unconditionally when called directly -- the test suite's
-- captured.LayoutPanel() calls rely on exactly that to set up geometry
-- for its own assertions.
local lastLayoutX, lastLayoutY, lastLayoutQuizMode = nil, nil, nil
local function RelayoutPanelIfNeeded()
    if panelRects.bounds == nil
        or lastLayoutX ~= panelPos.x
        or lastLayoutY ~= panelPos.y
        or lastLayoutQuizMode ~= quizMode
    then
        LayoutPanel()
        lastLayoutX, lastLayoutY, lastLayoutQuizMode = panelPos.x, panelPos.y, quizMode
    end
end

local function DrawPanel()
    RelayoutPanelIfNeeded()
    local b = panelRects.bounds

    DrawPanelChrome(b)

    -- Round 16: "fix title Unit Flashcards put it on center and larger
    -- font same as the icon font size" -- was left-aligned at font 14;
    -- now centered across the full panel width (true panel center, not
    -- just the space left of the close button -- at the panel's real
    -- minimum width the title's text at font 20 comes nowhere near the
    -- close button's 28px strip at the far right edge) and raised to font
    -- 20, matching DrawIcon's own "Unit"/"Flashcards" label size exactly.
    gl.Text("Unit Flashcards", (b.x1 + b.x2) / 2, panelRects.dragHeader.y1 + 7, 20, "oc")

    -- close (X) button
    local cb = panelRects.closeBtn
    gl.Color(1, 0.6, 0.6, 1)
    gl.Text("X", (cb.x1 + cb.x2) / 2, (cb.y1 + cb.y2) / 2 - 5, 14, "oc")
    gl.Color(1, 1, 1, 1)

    -- faction column headers, centered over each faction's 3 tier cells.
    -- Round 16 follow-up: all caps, bigger (13 -> 16), and a real drop
    -- shadow instead of just the thin outline -- FACTION_LABEL itself
    -- stays title-case ("Armada") since it's also used in sentence
    -- context (celebration messages, etc); :upper() only at this one
    -- draw site.
    for fi, f in ipairs(FACTIONS) do
        local first = panelRects.factionCells[(fi - 1) * #TIERS + 1]
        local last  = panelRects.factionCells[(fi - 1) * #TIERS + #TIERS]
        local cx = (first.x1 + last.x2) / 2
        local c = FACTION_COLOR[f]
        DrawTextWithShadow(FACTION_LABEL[f]:upper(), cx, first.y2 + 4, 16, "oc", c[1], c[2], c[3], 1)
    end
    gl.Color(1, 1, 1, 1)

    -- Round 16: "make the UI shinier" -- every flat gl.Color+gl.Rect
    -- button/cell fill below was replaced with DrawGlossyRect (same color
    -- it used to pass to gl.Color, now a top-lit gradient + sheen line
    -- instead of one flat shade), without touching the on/off colors or
    -- the text drawn on top of them.
    for _, cell in ipairs(panelRects.factionCells) do
        local on = selection[cell.faction][cell.tier]
        local c = FACTION_COLOR[cell.faction]
        if on then
            DrawGlossyRect(cell.x1, cell.y1, cell.x2, cell.y2, c[1], c[2], c[3], 0.85)
        else
            DrawGlossyRect(cell.x1, cell.y1, cell.x2, cell.y2, 0.25, 0.25, 0.25, 0.8)
        end
        gl.Color(1, 1, 1, on and 1 or 0.6)
        gl.Text(TIER_LABEL[cell.tier], (cell.x1 + cell.x2) / 2, (cell.y1 + cell.y2) / 2 - 5, 13, "oc")
    end
    gl.Color(1, 1, 1, 1)

    -- type toggle row
    for _, cell in ipairs(panelRects.typeCells) do
        local on = typeSelection[cell.unitType]
        if on then
            DrawGlossyRect(cell.x1, cell.y1, cell.x2, cell.y2, 0.85, 0.68, 0.25, 0.8)
        else
            DrawGlossyRect(cell.x1, cell.y1, cell.x2, cell.y2, 0.25, 0.25, 0.25, 0.8)
        end
        gl.Color(1, 1, 1, on and 1 or 0.6)
        gl.Text(TYPE_LABEL[cell.unitType], (cell.x1 + cell.x2) / 2, (cell.y1 + cell.y2) / 2 - 4, 10, "oc")
    end
    gl.Color(1, 1, 1, 1)

    -- All Factions Random -- a real toggle (round 3): highlighted when
    -- every faction/tier cell is currently on, clicking flips between
    -- all-on and all-off rather than being a one-shot "select all" with
    -- no way back.
    local ar = panelRects.allRandom
    local allOn = AllCellsOn()
    DrawGlossyRect(ar.x1, ar.y1, ar.x2, ar.y2, 0.85, 0.68, 0.25, allOn and 0.9 or 0.35)
    gl.Color(1, 1, 1, 1)
    gl.Text("All Factions Random", (ar.x1 + ar.x2) / 2, (ar.y1 + ar.y2) / 2 - 5, 13, "oc")

    -- "Clear" (round 13) -- not a toggle like the pills around it; it's a
    -- one-shot action with no "on" state of its own, so it always draws
    -- the same dim, neutral style.
    local cb2 = panelRects.clearBtn
    DrawGlossyRect(cb2.x1, cb2.y1, cb2.x2, cb2.y2, 0.25, 0.25, 0.25, 0.8)
    gl.Color(1, 1, 1, 0.9)
    gl.Text("Clear", (cb2.x1 + cb2.x2) / 2, (cb2.y1 + cb2.y2) / 2 - 5, 13, "oc")

    -- Quiz toggle bar (round 5) -- same pill language as All Factions
    -- Random, gold when on, showing the running score once a quiz is in
    -- progress ("keep a score so on a quiz" per the user's own ask).
    local qb = panelRects.quizToggle
    DrawGlossyRect(qb.x1, qb.y1, qb.x2, qb.y2, 0.85, 0.68, 0.25, quizMode and 0.9 or 0.35)
    gl.Color(1, 1, 1, 1)
    local quizLabel = quizMode
        and ("Quiz: ON   Score " .. quizScore.correct .. "/" .. quizScore.total)
        or "Quiz: OFF"
    gl.Text(quizLabel, (qb.x1 + qb.x2) / 2, (qb.y1 + qb.y2) / 2 - 5, 13, "oc")

    local cr = panelRects.card
    DrawCard(cr.x1, cr.y1, cr.x2, cr.y2, currentCard)

    -- Quiz choice buttons (round 5), flanking the card. Once this card
    -- is answered, the correct choice always lights up green (so you
    -- learn the right answer even if you missed it) and your own wrong
    -- pick, if any, lights up red; nothing hints toward the answer
    -- beforehand.
    if quizMode then
        for i, rect in ipairs(panelRects.quizChoices) do
            local choice = quizChoices[i]
            if choice then
                local bg = {0.25, 0.25, 0.25, 0.8}
                if quizAnswered then
                    if choice.correct then
                        bg = {0.25, 0.75, 0.3, 0.85}
                    elseif i == quizPickedIndex then
                        bg = {0.8, 0.25, 0.25, 0.85}
                    end
                end
                DrawGlossyRect(rect.x1, rect.y1, rect.x2, rect.y2, bg[1], bg[2], bg[3], bg[4])

                local fontSize = FitFontSize(choice.name, 15, (rect.x2 - rect.x1) - 10, 11)
                gl.Color(1, 1, 1, 1)
                gl.Text(choice.name, (rect.x1 + rect.x2) / 2, (rect.y1 + rect.y2) / 2 - fontSize * 0.35, fontSize, "oc")
            end
        end
        gl.Color(1, 1, 1, 1)
    end

    gl.Color(0.7, 0.7, 0.7, 1)
    local hint
    if quizFinished and #deckPool > 0 then
        hint = "Quiz complete -- toggle Quiz to play again"
    elseif not currentCard then
        hint = "Pick a faction/tier above"
    elseif quizSkipAttempted then
        hint = "Pick a choice to answer -- or turn off Quiz to stop"
    elseif flipped then
        hint = "Hover + Space/Click: next card"
    elseif quizMode and not quizAnswered then
        -- Round 16 follow-up: "don't allow me to click on the flash card
        -- before picking... that would be cheating" -- clicking/peeking
        -- no longer flips an unanswered quiz card at all (see
        -- ActivateCard), so this can't invite that anymore.
        hint = "Pick a name to answer"
    else
        hint = "Hover + Space/Click: flip"
    end
    gl.Text(hint, (b.x1 + b.x2) / 2, cr.y1 - 14, 11, "oc")
    gl.Color(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- INPUT HELPERS
--------------------------------------------------------------------------------

local function PointInRect(mx, my, r)
    if not r then return false end
    return mx >= r.x1 and mx <= r.x2 and my >= r.y1 and my <= r.y2
end

local function ToggleCell(cell)
    selection[cell.faction][cell.tier] = not selection[cell.faction][cell.tier]
    OnSelectionChanged()
end

local function ToggleTypeCell(cell)
    typeSelection[cell.unitType] = not typeSelection[cell.unitType]
    OnSelectionChanged()
end

local function SelectAllRandom()
    for _, f in ipairs(FACTIONS) do
        for _, t in ipairs(TIERS) do
            selection[f][t] = true
        end
    end
    OnSelectionChanged()
end

-- Factored out of DeselectAllFactions (round 13) so ClearAllFilters below
-- can reuse the exact same faction/tier-clearing loop without triggering
-- OnSelectionChanged() twice.
local function ClearFactionSelection()
    for _, f in ipairs(FACTIONS) do
        for _, t in ipairs(TIERS) do
            selection[f][t] = false
        end
    end
end

local function DeselectAllFactions()
    ClearFactionSelection()
    OnSelectionChanged()
end

-- The "All Factions Random" click handler (round 3: now a toggle). Turns
-- everything on if not everything is already on; turns everything off
-- if it is -- so the button is reversible instead of one-shot.
local function ToggleAllRandom()
    if AllCellsOn() then
        DeselectAllFactions()
    else
        SelectAllRandom()
    end
end

-- The "[Clear]" button (round 13: "add a [Clear] so all selections are
-- deselected"). Deliberately broader than DeselectAllFactions/All Factions
-- Random, which only ever touch the faction/tier grid: Clear also resets
-- the type filter row (Bots/Vehicles/Air/Sea/Structures) back to "no type
-- filter active" (AnyTypeSelected() false == every type shown), so one
-- click genuinely deselects everything the user picked, not just half of
-- it.
local function ClearAllFilters()
    ClearFactionSelection()
    for _, t in ipairs(TYPES) do
        typeSelection[t] = false
    end
    OnSelectionChanged()
end

-- Flip if face-down, otherwise draw a new card -- the single shared
-- gesture (space or click, while hovering the card) the user asked for
-- covers both flip AND advance. Kept as a shortcut even in quiz mode (it
-- doesn't touch quizScore) so hovering + space/click can still be used to
-- just peek at a card instead of picking a choice.
local function ActivateCard()
    if not currentCard then return end
    if quizMode and not quizAnswered then
        -- Round 16 follow-up: "don't allow me to click on the flash card
        -- before picking... or that would be cheating" -- the FIRST click
        -- used to flip the card straight to its answer face (the unit's
        -- name) before a choice was ever picked, which is a trivial way
        -- to cheat a multiple-choice quiz. Checked BEFORE the "not
        -- flipped" branch below, so in quiz mode an unanswered card can
        -- never flip at all, on the first click or any later one -- it
        -- only ever nags them to pick a choice instead (round 15's
        -- existing reminder, now covering the first click too, not just
        -- a repeat one after an old-style peek). PickQuizChoice is the
        -- only thing that sets flipped = true while a quiz is running.
        quizSkipAttempted = true
    elseif not flipped then
        flipped = true
    else
        DrawNextCard()
    end
end

-- Quiz mode toggle (round 5; exhaustive deal added round 6). Turning it
-- ON resets the running score, shuffles deckPool ONCE into a finite
-- quizDeck (BuildQuizDeck), and deals the first card from it -- "go
-- through all of the selected" with no repeats, ending in quizFinished
-- once the deck is exhausted. Turning it OFF just clears the choice list
-- and any finished-state flag (the card itself is untouched either way).
-- The panel widens to fit the choice columns while quiz mode is on (see
-- ComputePanelSize), so this re-clamps the panel position afterward --
-- otherwise a panel already sitting near the screen's right/top edge
-- could grow part of itself off-screen, the same class of bug round 4
-- fixed for the plain 574x616 size.
local function ToggleQuizMode()
    quizMode = not quizMode
    if quizMode then
        quizScore.correct, quizScore.total = 0, 0
        BuildQuizDeck()
        DrawNextCard() -- deals the first card (or finishes instantly if deckPool is empty)
    else
        quizFinished = false
        RefreshQuizChoices(nil)
        StopConfetti()
    end
    ClampPanelPos()
end

-- Picking a quiz choice (round 5): scores it against the real card,
-- flips the card to confirm/reveal, and locks this card's answer so a
-- second click doesn't double-count the score. Ignored if quiz mode is
-- off, there's no card, or this card was already answered.
local function PickQuizChoice(index)
    if not quizMode or not currentCard or quizAnswered then return end
    local choice = quizChoices[index]
    if not choice then return end
    quizAnswered = true
    quizSkipAttempted = false
    quizPickedIndex = index
    quizScore.total = quizScore.total + 1
    if choice.correct then
        quizScore.correct = quizScore.correct + 1
    end
    flipped = true
end

--------------------------------------------------------------------------------
-- WIDGET CALLINS
--------------------------------------------------------------------------------

function widget:Initialize()
    math.randomseed(os.time())

    iconPos.x = spGetConfigInt("UnitFlashcards_IconX", 40)
    iconPos.y = spGetConfigInt("UnitFlashcards_IconY", 40)
    ClampIconPos()
    UpdateIconRect()

    -- Panel is detached from the icon (round 3) -- its own saved
    -- position, defaulting to just right of the icon's own default so
    -- the two don't land on top of each other the first time.
    panelPos.x = spGetConfigInt("UnitFlashcards_PanelX", iconPos.x + ICON.W + 20)
    panelPos.y = spGetConfigInt("UnitFlashcards_PanelY", iconPos.y)
    ClampPanelPos()

    allUnitsCache, labTypeByID = BuildAllUnitsCache()
    if #allUnitsCache == 0 then
        spEcho("[Unit Flashcards] no arm/cor/leg unit defs found -- this game/mod isn't BAR-compatible")
    end
end

function widget:ViewResize()
    ClampIconPos()
    UpdateIconRect()
    ClampPanelPos()
end

function widget:DrawScreen()
    DrawIcon()

    if panelVisible then
        DrawPanel()
        DrawConfetti() -- round 13: perfect-quiz-score celebration, see MaybeTriggerConfetti
        DrawCelebrationBanner() -- round 15: the big popup line that goes with it

        -- track hover for the space-bar gesture (MouseMove only fires on
        -- movement; checking every frame here is cheap and avoids ever
        -- missing a hover state change).
        local mx, my = spGetMouseState()
        cardHover = PointInRect(mx, my, panelRects.card)
    else
        cardHover = false
    end
end

local function StartPanelDrag(mx, my)
    panelDrag.active = true
    panelDrag.startX, panelDrag.startY = mx, my
    panelDrag.offsetX = mx - panelPos.x
    panelDrag.offsetY = my - panelPos.y
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end

    if PointInRect(mx, my, iconRect) then
        iconDrag.active = true
        iconDrag.startX, iconDrag.startY = mx, my
        iconDrag.offsetX = mx - iconPos.x
        iconDrag.offsetY = my - iconPos.y
        iconDrag.moved = false
        return true
    end

    if panelVisible then
        if PointInRect(mx, my, panelRects.closeBtn) then
            panelVisible = false
            return true
        end
        if PointInRect(mx, my, panelRects.dragHeader) then
            StartPanelDrag(mx, my)
            return true
        end
        if PointInRect(mx, my, panelRects.card) then
            ActivateCard()
            return true
        end
        if PointInRect(mx, my, panelRects.allRandom) then
            ToggleAllRandom()
            return true
        end
        if PointInRect(mx, my, panelRects.clearBtn) then
            ClearAllFilters()
            return true
        end
        if PointInRect(mx, my, panelRects.quizToggle) then
            ToggleQuizMode()
            return true
        end
        for _, cell in ipairs(panelRects.factionCells) do
            if PointInRect(mx, my, cell) then
                ToggleCell(cell)
                return true
            end
        end
        for _, cell in ipairs(panelRects.typeCells) do
            if PointInRect(mx, my, cell) then
                ToggleTypeCell(cell)
                return true
            end
        end
        if quizMode then
            for i, rect in ipairs(panelRects.quizChoices) do
                if PointInRect(mx, my, rect) then
                    PickQuizChoice(i)
                    return true
                end
            end
        end
        if PointInRect(mx, my, panelRects.bounds) then
            -- Round 16: "make everything draggable except for buttons" --
            -- every actual interactive rect (close button, drag header,
            -- card, All Factions Random, Clear, Quiz toggle, faction/tier
            -- cells, type cells, and quiz choice buttons while Quiz is on)
            -- is checked above and already returns before reaching here,
            -- so anything that falls through to this point is empty panel
            -- background -- now a drag-start instead of just swallowing
            -- the click, same mechanics the header strip already used.
            StartPanelDrag(mx, my)
            return true
        end
    end

    return false
end

function widget:MouseMove(mx, my, dx, dy, button)
    if iconDrag.active then
        if math.abs(mx - iconDrag.startX) > 3 or math.abs(my - iconDrag.startY) > 3 then
            iconDrag.moved = true
        end
        iconPos.x = mx - iconDrag.offsetX
        iconPos.y = my - iconDrag.offsetY
        ClampIconPos()
        UpdateIconRect()
        return true
    end
    if panelDrag.active then
        panelPos.x = mx - panelDrag.offsetX
        panelPos.y = my - panelDrag.offsetY
        ClampPanelPos()
        return true
    end
    return false
end

function widget:MouseRelease(mx, my, button)
    if iconDrag.active then
        iconDrag.active = false
        spSetConfigInt("UnitFlashcards_IconX", math.floor(iconPos.x))
        spSetConfigInt("UnitFlashcards_IconY", math.floor(iconPos.y))
        if not iconDrag.moved then
            panelVisible = not panelVisible
            if panelVisible and #deckPool == 0 and AnySelected() then
                RebuildDeckPool()
            end
        end
        return true
    end
    if panelDrag.active then
        panelDrag.active = false
        spSetConfigInt("UnitFlashcards_PanelX", math.floor(panelPos.x))
        spSetConfigInt("UnitFlashcards_PanelY", math.floor(panelPos.y))
        return true
    end
    return false
end

function widget:KeyPress(key, mods, isRepeat)
    if isRepeat then return false end
    if key == 32 and cardHover then -- space bar
        ActivateCard()
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- TEST-ONLY EXPORTS
--------------------------------------------------------------------------------
-- Not reachable in the real game (Spring never sets a global
-- UNIT_FLASHCARDS_TEST_EXPORTS), purely so the extraction-based test
-- harness can call into the pure logic functions above without having to
-- re-splice around every one of them individually.
if UNIT_FLASHCARDS_TEST_EXPORTS then
    UNIT_FLASHCARDS_TEST_EXPORTS({
        UnitTechLevel       = UnitTechLevel,
        IsCosmeticDecoration = IsCosmeticDecoration,
        Lighten             = Lighten,
        Darken              = Darken,
        RoundedRect         = RoundedRect,
        GradientRoundedRect = GradientRoundedRect,
        DrawGlossyRect      = DrawGlossyRect,
        DrawCardFrame       = DrawCardFrame,
        DrawTextWithShadow  = DrawTextWithShadow,
        SubfolderBucket     = SubfolderBucket,
        ClassifyUnitType    = ClassifyUnitType,
        BuildLabTypeMap     = BuildLabTypeMap,
        ResolveDisplayName  = ResolveDisplayName,
        BuildAllUnitsCache  = BuildAllUnitsCache,
        RebuildDeckPool     = RebuildDeckPool,
        AnySelected         = AnySelected,
        AnyTypeSelected     = AnyTypeSelected,
        AllCellsOn          = AllCellsOn,
        ShuffleCopy         = ShuffleCopy,
        DrawNextCard        = DrawNextCard,
        OnSelectionChanged  = OnSelectionChanged,
        BuildStatLines      = BuildStatLines,
        ToggleCell          = ToggleCell,
        ToggleTypeCell      = ToggleTypeCell,
        SelectAllRandom     = SelectAllRandom,
        DeselectAllFactions = DeselectAllFactions,
        ToggleAllRandom     = ToggleAllRandom,
        ClearAllFilters     = ClearAllFilters,
        ActivateCard        = ActivateCard,
        PointInRect         = PointInRect,
        getSelection        = function() return selection end,
        getTypeSelection    = function() return typeSelection end,
        getDeckPool         = function() return deckPool end,
        setDeckPool         = function(v) deckPool = v end,
        getShuffledDeck     = function() return shuffledDeck end,
        setShuffledDeck     = function(v) shuffledDeck = v end,
        getDeckCursor       = function() return deckCursor end,
        setDeckCursor       = function(v) deckCursor = v end,
        getCurrentCard      = function() return currentCard end,
        getFlipped          = function() return flipped end,
        setFlipped          = function(v) flipped = v end,
        setCurrentCard      = function(v) currentCard = v end,
        getPanelVisible     = function() return panelVisible end,
        setPanelVisible     = function(v) panelVisible = v end,
        ComputePanelSize    = ComputePanelSize,
        ClampPanelPos       = ClampPanelPos,
        LayoutPanel         = LayoutPanel,
        RelayoutPanelIfNeeded = RelayoutPanelIfNeeded,
        getLastLayoutKey    = function() return lastLayoutX, lastLayoutY, lastLayoutQuizMode end,
        getPanelRects       = function() return panelRects end,
        getPanelPos         = function() return panelPos end,
        setPanelPos         = function(x, y) panelPos.x, panelPos.y = x, y end,
        getPanelDragActive  = function() return panelDrag.active end,
        setPanelDragActive  = function(v) panelDrag.active = v end,
        BuildQuizChoices    = BuildQuizChoices,
        RefreshQuizChoices  = RefreshQuizChoices,
        BuildQuizDeck       = BuildQuizDeck,
        ToggleQuizMode      = ToggleQuizMode,
        PickQuizChoice      = PickQuizChoice,
        getQuizMode         = function() return quizMode end,
        setQuizMode         = function(v) quizMode = v end, -- test-only: flips the raw flag
                                                              -- without ToggleQuizMode's dealing/
                                                              -- scoring/confetti side effects

        getQuizChoices      = function() return quizChoices end,
        getQuizAnswered     = function() return quizAnswered end,
        getQuizSkipAttempted = function() return quizSkipAttempted end,
        getQuizPickedIndex  = function() return quizPickedIndex end,
        getQuizScore        = function() return quizScore end,
        getQuizDeck         = function() return quizDeck end,
        getQuizDeckCursor   = function() return quizDeckCursor end,
        getQuizFinished     = function() return quizFinished end,
        MaybeTriggerConfetti = MaybeTriggerConfetti,
        StopConfetti        = StopConfetti,
        DrawConfetti        = DrawConfetti,
        getConfettiActive   = function() return confettiActive end,
        getConfettiParticles = function() return confettiParticles end,
        getConfettiStartTime = function() return confettiStartTime end,
        getFireworkBursts   = function() return fireworkBursts end,
        BuildConfettiParticles = BuildConfettiParticles,
        BuildFireworkBursts = BuildFireworkBursts,
        ConfettiSpawnArea   = ConfettiSpawnArea,
        setQuizScore        = function(correct, total) quizScore.correct, quizScore.total = correct, total end,
        BuildCelebrationMessage = BuildCelebrationMessage,
        ActiveFactionsAndTiers  = ActiveFactionsAndTiers,
        DrawCelebrationBanner   = DrawCelebrationBanner,
        getCelebrationMessage   = function() return celebrationMessage end,
    })
end
