function widget:GetInfo()
  return {
    name      = "Base Tracker",
    desc      = "Per-team base overview: labs, commander, base-center jump/follow, faction icons.",
    author    = "Armis71 + Claude AI",
    date      = "2026",
    license   = "GPL",
    layer     = 0,
    enabled   = true,
  }
end

------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

local defaultX, defaultY = 300, 500
local chartX, chartY     = defaultX, defaultY

local iconSize           = 64
local rowH               = iconSize + 10
local nameColW           = iconSize * 2.5   -- widened for truncation original is 3.8
local padding            = 6
local doubleClickThreshold = 0.25
local dividerRowH = 36
local pinDividerRowH = 14
local nameFontSize       = 16
local badgeFontSizeBySize = { [96] = 21.6, [88] = 19.8, [80] = 18.0, [72] = 16.2, [64] = 14.4, [56] = 12.6, [48] = 10.8, [40] = 9.0 }
local backgroundOpacity  = 0.8    -- panel background opacity: 0 = fully transparent, 1 = fully opaque

------------------------------------------------------------
-- HUMAN‑READABLE LAB NAMES
------------------------------------------------------------

local labDisplayNames = {
  armlab      = "T1 Bot Lab",
  armvp       = "T1 Vehicle Lab",
  armap       = "T1 Air Lab",
  armfhp      = "T1 Naval Hovercraft Platform",
  armhp       = "T1 Hovercraft Platform",
  armamsub    = "T1 Amphibious Complex",
  armplat     = "T1 Seaplane Platform",
  armsy       = "T1 Shipyard",
  armalab     = "T2 Advanced Bot Lab",
  armavp      = "T2 Advanced Vehicle Plant",
  armaap      = "T2 Advanced Aircraft Plant",
  armasy      = "T2 Advanced Shipyard",
  armshltx    = "Experimental Gantry",
  armshltxuw  = "Experimental Gantry UW",

  corlab      = "T1 Bot Lab",
  corvp       = "T1 Vehicle Lab",
  corap       = "T1 Air Lab",
  corfhp      = "T1 Naval Hovercraft Platform",
  corhp       = "T1 Hovercraft Platform",
  coramsub    = "T1 Amphibious Complex",
  corplat     = "T1 Seaplane Platform",
  corsy       = "T1 Shipyard",
  coralab     = "T2 Advanced Bot Lab",
  coravp      = "T2 Advanced Vehicle Plant",
  coraap      = "T2 Advanced Aircraft Plant",
  corasy      = "T2 Advanced Shipyard",
  corgant     = "Experimental Gantry",
  corgantuw   = "Experimental Gantry UW",

  leglab      = "T1 Bot Lab",
  legvp       = "T1 Vehicle Lab",
  legap       = "T1 Air Lab",
  legfhp      = "T1 Naval Hovercraft Platform",
  leghp       = "T1 Hovercraft Platform",
  legamphlab  = "T1 Amphibious Complex",
  legsplab    = "T1 Seaplane Platform",
  legsy       = "T1 Shipyard",
  legalab     = "T2 Advanced Bot Lab",
  legavp      = "T2 Advanced Vehicle Plant",
  legaap      = "T2 Advanced Aircraft Plant",
  legadvshipyard = "T2 Advanced Shipyard",
  leggant     = "Experimental Gantry",
  leggantuw   = "Experimental Gantry UW",

  -- Fusion Reactors (T2 energy)
  armfus      = "Fusion Reactor",
  corfus      = "Fusion Reactor",
  legfus      = "Fusion Reactor",

  -- Advanced Fusion Reactors (AFUS)
  armafus     = "Advanced Fusion Reactor",
  corafus     = "Advanced Fusion Reactor",
  legafus     = "Advanced Fusion Reactor",
  armafust3   = "Epic AFUS",
  corafust3   = "Epic AFUS",
  legafust3   = "Epic AFUS",

  -- LRPC (Long Range Plasma Cannon) -- Armada's equivalent
  -- (armvulc/Ragnarok) is tracked under Super Weapon instead, since
  -- it doubles as Armada's superweapon rather than a separate unit.
  armbrtha    = "LRPC",
  corint      = "LRPC",
  leglrpc     = "LRPC",

  -- Nuke Silos
  armsilo     = "Nuke Silo",
  corsilo     = "Nuke Silo",
  legsilo     = "Nuke Silo",

  -- Anti-Nukes
  armamd        = "Anti-Nuke",
  corfmd        = "Anti-Nuke",
  legabm        = "Anti-Nuke",

  -- Super Weapons (Ragnarok, Calamity, Starfall)
  armvulc      = "Super Weapon",
  corbuzz      = "Super Weapon",
  legstarfall  = "Super Weapon",

  -- Plasma Pulsar and equivalents (T3 area-denial defense towers).
  -- Note: Legion's Bastion has no epic variant yet (confirmed via
  -- BAR issue tracker), unlike Armada's Pulsar and Cortex's Bulwark.
  armanni      = "Pulsar",
  cordoom      = "Pulsar",
  legbastion   = "Pulsar",
  armannit3    = "Epic Pulsar",
  cordoomt3    = "Epic Pulsar",

  -- Pinpointers
  armtarg      = "Pinpointer",
  cortarg      = "Pinpointer",
  legtarg      = "Pinpointer",

  -- Junos
  armjuno      = "Juno",
  corjuno      = "Juno",
  legjuno      = "Juno",

  -- Experimental Aircraft Plant/Gantry (T3/T4 aircraft-specific
  -- factory, distinct from the general Experimental Gantry above)
  armapt3      = "Experimental Aircraft Plant",
  corapt3      = "Experimental Aircraft Plant",
  legapt3      = "Experimental Aircraft Plant",

  -- Pawn Launcher (Armada only -- no confirmed Cortex/Legion equivalent)
  armbotrail   = "Pawn Launcher",

  -- Intrusion Countermeasure System
  armsd        = "Intrusion CM",
  corsd        = "Intrusion CM",
  legsd        = "Intrusion CM",

  -- Long Range Napalm Launcher (Legion only -- no confirmed
  -- Cortex/Armada equivalent)
  legperdition = "Napalm Launcher",

  -- Geothermal Powerplants
  armgeo   = "Geothermal Powerplant",
  corgeo   = "Geothermal Powerplant",
  leggeo   = "Geothermal Powerplant",

  armuwgeo = "Offshore Geothermal Powerplant",
  coruwgeo = "Offshore Geothermal Powerplant",
  leguwgeo = "Offshore Geothermal Powerplant",

  armageo  = "Advanced Geothermal Powerplant",
  corageo  = "Advanced Geothermal Powerplant",
  legageo  = "Advanced Geothermal Powerplant",

  armuwageo      = "Advanced Offshore Geothermal Powerplant",
  coruwageo      = "Advanced Offshore Geothermal Powerplant",
  leganavaladvgeo = "Advanced Offshore Geothermal Powerplant",

  -- "Prude" -- Armada only, no confirmed Cortex/Legion equivalent
  armgmm   = "Safe Geothermal Powerplant",

  -- Basic economy
  armmex   = "Metal Extractor",
  cormex   = "Metal Extractor",
  legmex   = "Metal Extractor",

  armmoho  = "Advanced Metal Extractor",
  cormoho  = "Advanced Metal Extractor",
  legmoho  = "Advanced Metal Extractor",

  armsolar = "Solar Collector",
  corsolar = "Solar Collector",
  legsolar = "Solar Collector",

  armadvsol = "Advanced Solar Collector",
  coradvsol = "Advanced Solar Collector",
  legadvsol = "Advanced Solar Collector",

  armwin   = "Wind Turbine",
  corwin   = "Wind Turbine",
  legwin   = "Wind Turbine",

  armwint2 = "Advanced Wind Turbine",
  corwint2 = "Advanced Wind Turbine",
  legwint2 = "Advanced Wind Turbine",

  armtide  = "Tidal Generator",
  cortide  = "Tidal Generator",
  legtide  = "Tidal Generator",

  armmstor = "Metal Storage",
  cormstor = "Metal Storage",
  legmstor = "Metal Storage",

  armestor = "Energy Storage",
  corestor = "Energy Storage",
  legestor = "Energy Storage",

  armmakr  = "Energy Converter",
  cormakr  = "Energy Converter",
  legeconv = "Energy Converter",

  armmmkr  = "Advanced Energy Converter",
  cormmkr  = "Advanced Energy Converter",
  legadveconv = "Advanced Energy Converter",

  armmmkrt3   = "Epic Energy Converter",
  cormmkrt3   = "Epic Energy Converter",
  legadveconvt3 = "Epic Energy Converter",

  -- Detection & support
  armrad   = "Radar Tower",
  corrad   = "Radar Tower",
  legrad   = "Radar Tower",

  armarad  = "Advanced Radar Tower",
  corarad  = "Advanced Radar Tower",
  legarad  = "Advanced Radar Tower",

  armsonar = "Sonar Station",
  corsonar = "Sonar Station",

  armason  = "Advanced Sonar Station",
  corason  = "Advanced Sonar Station",

  armnanotc = "Construction Turret",
  cornanotc = "Construction Turret",
  legnanotc = "Construction Turret",

  armnanotct2 = "Advanced Construction Turret",
  cornanotct2 = "Advanced Construction Turret",
  legnanotct2 = "Advanced Construction Turret",

  -- Naval detection
  armfrad  = "Naval Radar / Sonar Tower",
  corfrad  = "Naval Radar / Sonar Tower",
  legfrad  = "Naval Radar / Sonar Tower",

  -- Auscultor -- Legion only, no confirmed Armada/Cortex equivalent
  leganavalsonarstation = "Auscultor",

  -- Basic Defense Turret (T1)
  armllt = "Basic Defense Turret",
  corllt = "Basic Defense Turret",
  leglht = "Basic Defense Turret",

  -- Anti-Air Tower (T1)
  armflak = "Anti-Air Tower",
  corflak = "Anti-Air Tower",
  legrl   = "Anti-Air Tower",

  -- Naval Anti-Air Turret
  armfflak = "Naval Anti-Air Turret",
  corenaa  = "Naval Anti-Air Turret",
  legfrl   = "Naval Anti-Air Turret",

  -- Plasma Shield / Deflector -- no confirmed Cortex equivalent
  armgate     = "Plasma Shield",
  legdeflector = "Plasma Shield",

  -- Faction-unique defense structures
  armamb  = "Pop-up Plasma Artillery",     -- Armada only
  armguard = "Area Control Plasma Artillery", -- Armada only
  armemp  = "EMP Missile Launcher",         -- Armada only
  corerad = "AA Missile Battery",           -- Cortex only
  corhllt = "Anti-Swarm Double Guard",      -- Cortex only
  legrampart = "Rampart",                   -- Legion only, hybrid Anti-Nuke/Jammer/Radar/Drone
}

------------------------------------------------------------
-- TECH‑TIER SORT ORDER (optional, kept for future use)
------------------------------------------------------------

local statColumns = {
  {key = "mps", label = "M/s"},
  {key = "eps", label = "E/s"},
  {key = "mp",  label = "MP"},
  {key = "ep",  label = "EP"},
  {key = "av",  label = "AV"},
  {key = "dv",  label = "DV"},
  {key = "up",  label = "UP"},
  {key = "dd",  label = "DD"},
  {key = "uk",  label = "UK"},
}
local statsRowH = 30
local viewModeColumns = {
  {key = "minimal", label = "Minimal"},
  {key = "eco",     label = "Eco"},
  {key = "defense", label = "Defense"},
  {key = "offense", label = "Offense"},
  {key = "all",     label = "All"},
}
local viewModeRowH = 26
local viewModeExtraCategories = {
  eco = {
    "Fusion Reactor", "Advanced Fusion Reactor", "Epic AFUS",
    "Geothermal Powerplant", "Offshore Geothermal Powerplant",
    "Advanced Geothermal Powerplant", "Advanced Offshore Geothermal Powerplant",
    "Safe Geothermal Powerplant",
    "Metal Extractor", "Advanced Metal Extractor",
    "Solar Collector", "Advanced Solar Collector",
    "Wind Turbine", "Advanced Wind Turbine",
    "Tidal Generator", "Metal Storage", "Energy Storage",
    "Energy Converter", "Advanced Energy Converter", "Epic Energy Converter",
    "Construction Turret", "Advanced Construction Turret",
  },
  defense = {
    "Pulsar", "Epic Pulsar", "Anti-Nuke", "Pinpointer",
    "Intrusion CM", "Juno",
    "Radar Tower", "Advanced Radar Tower",
    "Sonar Station", "Advanced Sonar Station",
    "Naval Radar / Sonar Tower", "Auscultor",
    "Basic Defense Turret", "Anti-Air Tower", "Naval Anti-Air Turret",
    "Plasma Shield", "Pop-up Plasma Artillery", "Area Control Plasma Artillery",
    "EMP Missile Launcher", "AA Missile Battery", "Anti-Swarm Double Guard",
    "Rampart",
  },
  offense = {
    "Nuke Silo", "Super Weapon", "LRPC", "Napalm Launcher",
    "Pawn Launcher",
  },
}
local statDescriptions = {
  mps = "M/s - metal income per sec",
  eps = "E/s - energy income per sec",
  mp  = "MP - total metal produced",
  ep  = "EP - total energy produced",
  av  = "AV - Army value in metal + Com",
  dv  = "DV - Defense value in metal",
  dd  = "DD - Damage dealt to enemies",
  up  = "UP - Units produced",
  uk  = "UK - Enemy units killed",
}

local viewModeDescriptions = {
  minimal = "Minimal - Labs and Commander only",
  eco     = "Eco - Fusion, Geothermal, Mex, Solar, Wind, Storage",
  defense = "Defense - Pulsar, Anti-Nuke, Radar/Sonar, Pinpointer, ICM, Juno",
  offense = "Offense - Nukes, Super Weapon, LRPC, Napalm/Pawn",
  all     = "All - every tracked structure, no filter",
}

local techTierOrder = {
  ["Commander"]                       = 0,

  ["T1 Bot Lab"]                     = 1,
  ["T1 Vehicle Lab"]                 = 1,
  ["T1 Air Lab"]                     = 1,
  ["T1 Hovercraft Platform"]         = 1,
  ["T1 Naval Hovercraft Platform"]   = 1,
  ["T1 Shipyard"]                    = 1,
  ["T1 Amphibious Complex"]          = 1,
  ["T1 Seaplane Platform"]           = 1,

  ["T2 Advanced Bot Lab"]            = 2,
  ["T2 Advanced Vehicle Plant"]      = 2,
  ["T2 Advanced Aircraft Plant"]     = 2,
  ["T2 Advanced Shipyard"]           = 2,

  ["Experimental Gantry"]            = 3,
  ["Experimental Gantry UW"]         = 4,

  ["Fusion Reactor"]                 = 5,
  ["Advanced Fusion Reactor"]        = 6,
  ["LRPC"]                           = 7,
  ["Nuke Silo"]                      = 8,
  ["Anti-Nuke"]                      = 9,
  ["Super Weapon"]                   = 10,
  ["Pulsar"]                         = 11,
  ["Pinpointer"]                     = 12,
  ["Juno"]                           = 13,
  ["Experimental Aircraft Plant"]    = 14,
  ["Epic AFUS"]                       = 15,
  ["Epic Pulsar"]                     = 16,
  ["Pawn Launcher"]                   = 17,
  ["Intrusion CM"]                    = 18,
  ["Napalm Launcher"]                 = 19,
  ["Geothermal Powerplant"]                    = 20,
  ["Offshore Geothermal Powerplant"]           = 21,
  ["Advanced Geothermal Powerplant"]           = 22,
  ["Advanced Offshore Geothermal Powerplant"]  = 23,
  ["Safe Geothermal Powerplant"]               = 24,

  ["Metal Extractor"]                   = 25,
  ["Advanced Metal Extractor"]          = 26,
  ["Solar Collector"]                   = 27,
  ["Advanced Solar Collector"]          = 28,
  ["Wind Turbine"]                      = 29,
  ["Advanced Wind Turbine"]             = 30,
  ["Tidal Generator"]                   = 31,
  ["Metal Storage"]                     = 32,
  ["Energy Storage"]                    = 33,
  ["Energy Converter"]                  = 34,
  ["Advanced Energy Converter"]         = 35,
  ["Epic Energy Converter"]             = 36,
  ["Radar Tower"]                       = 37,
  ["Advanced Radar Tower"]              = 38,
  ["Sonar Station"]                     = 39,
  ["Advanced Sonar Station"]            = 40,
  ["Construction Turret"]               = 41,
  ["Advanced Construction Turret"]      = 42,
  ["Naval Radar / Sonar Tower"]          = 43,
  ["Auscultor"]                          = 44,

  ["Basic Defense Turret"]              = 45,
  ["Anti-Air Tower"]                    = 46,
  ["Naval Anti-Air Turret"]             = 47,
  ["Plasma Shield"]                     = 48,
  ["Pop-up Plasma Artillery"]           = 49,
  ["Area Control Plasma Artillery"]     = 50,
  ["EMP Missile Launcher"]              = 51,
  ["AA Missile Battery"]                = 52,
  ["Anti-Swarm Double Guard"]           = 53,
  ["Rampart"]                           = 54,
}

-- Commander + core Labs (tiers 0-4) are always shown regardless of
-- view mode; Eco/Defense/Offense each add their own extra categories
-- on top of that core set. "All" removes the filter entirely.
local function isCategoryVisibleInView(category, viewMode)
  if viewMode == "all" then return true end
  local tier = techTierOrder[category]
  if tier and tier <= 4 then return true end
  if category == "Experimental Aircraft Plant" then return true end
  if viewMode == "minimal" then return false end
  local extras = viewModeExtraCategories[viewMode]
  if extras then
    for _, c in ipairs(extras) do
      if c == category then return true end
    end
  end
  return false
end

------------------------------------------------------------
-- ICON MAP (keys now match labDisplayNames values)
------------------------------------------------------------

------------------------------------------------------------
-- COMMANDER DETECTION
-- Any unit with customParams.iscommander is a commander,
-- regardless of faction or which commander skin/model was
-- picked, so we detect it generically instead of hardcoding
-- unit names like "armcom".
------------------------------------------------------------

local isCommanderDef = {}
for unitDefID, ud in pairs(UnitDefs) do
  if ud.customParams and ud.customParams.iscommander then
    isCommanderDef[unitDefID] = true
  end
end

local factionFullNames = {
  arm = "Armada",
  cor = "Cortex",
  leg = "Legion",
}

local iconMap = {
  arm = {
    ["T1 Bot Lab"]                     = "armlab",
    ["T1 Vehicle Lab"]                 = "armvp",
    ["T1 Air Lab"]                     = "armap",
    ["T1 Hovercraft Platform"]         = "armhp",
    ["T1 Naval Hovercraft Platform"]   = "armfhp",
    ["T1 Shipyard"]                    = "armsy",
    ["T1 Amphibious Complex"]          = "armamsub",
    ["T1 Seaplane Platform"]           = "armplat",
    ["T2 Advanced Bot Lab"]            = "armalab",
    ["T2 Advanced Vehicle Plant"]      = "armavp",
    ["T2 Advanced Aircraft Plant"]     = "armaap",
    ["T2 Advanced Shipyard"]           = "armasy",
    ["Experimental Gantry"]            = "armshltx",
    ["Experimental Gantry UW"]         = "armshltxuw",
    ["Fusion Reactor"]                 = "armfus",
    ["Advanced Fusion Reactor"]        = "armafus",
    ["LRPC"]                           = "armbrtha",
    ["Nuke Silo"]                      = "armsilo",
    ["Anti-Nuke"]                      = "armamd",
    ["Super Weapon"]                   = "armvulc",
    ["Pulsar"]                          = "armanni",
    ["Pinpointer"]                      = "armtarg",
    ["Juno"]                            = "armjuno",
    ["Experimental Aircraft Plant"]     = "armapt3",
    ["Epic AFUS"]                       = "armafust3",
    ["Epic Pulsar"]                     = "armannit3",
    ["Pawn Launcher"]                   = "armbotrail",
    ["Intrusion CM"]                    = "armsd",
    ["Geothermal Powerplant"]                   = "armgeo",
    ["Offshore Geothermal Powerplant"]          = "armuwgeo",
    ["Advanced Geothermal Powerplant"]          = "armageo",
    ["Advanced Offshore Geothermal Powerplant"] = "armuwageo",
    ["Safe Geothermal Powerplant"]              = "armgmm",
    ["Metal Extractor"]                   = "armmex",
    ["Advanced Metal Extractor"]          = "armmoho",
    ["Solar Collector"]                   = "armsolar",
    ["Advanced Solar Collector"]          = "armadvsol",
    ["Wind Turbine"]                      = "armwin",
    ["Advanced Wind Turbine"]             = "armwint2",
    ["Tidal Generator"]                   = "armtide",
    ["Metal Storage"]                     = "armmstor",
    ["Energy Storage"]                    = "armestor",
    ["Energy Converter"]                  = "armmakr",
    ["Advanced Energy Converter"]         = "armmmkr",
    ["Epic Energy Converter"]             = "armmmkrt3",
    ["Radar Tower"]                       = "armrad",
    ["Advanced Radar Tower"]              = "armarad",
    ["Sonar Station"]                     = "armsonar",
    ["Advanced Sonar Station"]            = "armason",
    ["Construction Turret"]               = "armnanotc",
    ["Advanced Construction Turret"]      = "armnanotct2",
    ["Naval Radar / Sonar Tower"]          = "armfrad",
    ["Basic Defense Turret"]              = "armllt",
    ["Anti-Air Tower"]                    = "armflak",
    ["Naval Anti-Air Turret"]             = "armfflak",
    ["Plasma Shield"]                     = "armgate",
    ["Pop-up Plasma Artillery"]           = "armamb",
    ["Area Control Plasma Artillery"]     = "armguard",
    ["EMP Missile Launcher"]              = "armemp",
  },
  cor = {
    ["T1 Bot Lab"]                     = "corlab",
    ["T1 Vehicle Lab"]                 = "corvp",
    ["T1 Air Lab"]                     = "corap",
    ["T1 Hovercraft Platform"]         = "corhp",
    ["T1 Naval Hovercraft Platform"]   = "corfhp",
    ["T1 Shipyard"]                    = "corsy",
    ["T1 Amphibious Complex"]          = "coramsub",
    ["T1 Seaplane Platform"]           = "corplat",
    ["T2 Advanced Bot Lab"]            = "coralab",
    ["T2 Advanced Vehicle Plant"]      = "coravp",
    ["T2 Advanced Aircraft Plant"]     = "coraap",
    ["T2 Advanced Shipyard"]           = "corasy",
    ["Experimental Gantry"]            = "corgant",
    ["Experimental Gantry UW"]         = "corgantuw",
    ["Fusion Reactor"]                 = "corfus",
    ["Advanced Fusion Reactor"]        = "corafus",
    ["LRPC"]                           = "corint",
    ["Nuke Silo"]                      = "corsilo",
    ["Anti-Nuke"]                      = "corfmd",
    ["Super Weapon"]                   = "corbuzz",
    ["Pulsar"]                          = "cordoom",
    ["Pinpointer"]                      = "cortarg",
    ["Juno"]                            = "corjuno",
    ["Experimental Aircraft Plant"]     = "corapt3",
    ["Epic AFUS"]                       = "corafust3",
    ["Epic Pulsar"]                     = "cordoomt3",
    ["Intrusion CM"]                    = "corsd",
    ["Geothermal Powerplant"]                   = "corgeo",
    ["Offshore Geothermal Powerplant"]          = "coruwgeo",
    ["Advanced Geothermal Powerplant"]          = "corageo",
    ["Advanced Offshore Geothermal Powerplant"] = "coruwageo",
    ["Metal Extractor"]                   = "cormex",
    ["Advanced Metal Extractor"]          = "cormoho",
    ["Solar Collector"]                   = "corsolar",
    ["Advanced Solar Collector"]          = "coradvsol",
    ["Wind Turbine"]                      = "corwin",
    ["Advanced Wind Turbine"]             = "corwint2",
    ["Tidal Generator"]                   = "cortide",
    ["Metal Storage"]                     = "cormstor",
    ["Energy Storage"]                    = "corestor",
    ["Energy Converter"]                  = "cormakr",
    ["Advanced Energy Converter"]         = "cormmkr",
    ["Epic Energy Converter"]             = "cormmkrt3",
    ["Radar Tower"]                       = "corrad",
    ["Advanced Radar Tower"]              = "corarad",
    ["Sonar Station"]                     = "corsonar",
    ["Advanced Sonar Station"]            = "corason",
    ["Construction Turret"]               = "cornanotc",
    ["Advanced Construction Turret"]      = "cornanotct2",
    ["Naval Radar / Sonar Tower"]          = "corfrad",
    ["Basic Defense Turret"]              = "corllt",
    ["Anti-Air Tower"]                    = "corflak",
    ["Naval Anti-Air Turret"]             = "corenaa",
    ["AA Missile Battery"]                = "corerad",
    ["Anti-Swarm Double Guard"]           = "corhllt",
  },
  leg = {
    ["T1 Bot Lab"]                     = "leglab",
    ["T1 Vehicle Lab"]                 = "legvp",
    ["T1 Air Lab"]                     = "legap",
    ["T1 Hovercraft Platform"]         = "leghp",
    ["T1 Naval Hovercraft Platform"]   = "legfhp",
    ["T1 Shipyard"]                    = "legsy",
    ["T1 Amphibious Complex"]          = "legamphlab",
    ["T1 Seaplane Platform"]           = "legsplab",
    ["T2 Advanced Bot Lab"]            = "legalab",
    ["T2 Advanced Vehicle Plant"]      = "legavp",
    ["T2 Advanced Aircraft Plant"]     = "legaap",
    ["T2 Advanced Shipyard"]           = "legadvshipyard",
    ["Experimental Gantry"]            = "leggant",
    ["Experimental Gantry UW"]         = "leggantuw",
    ["Fusion Reactor"]                 = "legfus",
    ["Advanced Fusion Reactor"]        = "legafus",
    ["LRPC"]                           = "leglrpc",
    ["Nuke Silo"]                      = "legsilo",
    ["Anti-Nuke"]                      = "legabm",
    ["Super Weapon"]                   = "legstarfall",
    ["Pulsar"]                          = "legbastion",
    ["Pinpointer"]                      = "legtarg",
    ["Juno"]                            = "legjuno",
    ["Experimental Aircraft Plant"]     = "legapt3",
    ["Epic AFUS"]                       = "legafust3",
    ["Intrusion CM"]                    = "legsd",
    ["Napalm Launcher"]                 = "legperdition",
    ["Geothermal Powerplant"]                   = "leggeo",
    ["Offshore Geothermal Powerplant"]          = "leguwgeo",
    ["Advanced Geothermal Powerplant"]          = "legageo",
    ["Advanced Offshore Geothermal Powerplant"] = "leganavaladvgeo",
    ["Metal Extractor"]                   = "legmex",
    ["Advanced Metal Extractor"]          = "legmoho",
    ["Solar Collector"]                   = "legsolar",
    ["Advanced Solar Collector"]          = "legadvsol",
    ["Wind Turbine"]                      = "legwin",
    ["Advanced Wind Turbine"]             = "legwint2",
    ["Tidal Generator"]                   = "legtide",
    ["Metal Storage"]                     = "legmstor",
    ["Energy Storage"]                    = "legestor",
    ["Energy Converter"]                  = "legeconv",
    ["Advanced Energy Converter"]         = "legadveconv",
    ["Epic Energy Converter"]             = "legadveconvt3",
    ["Radar Tower"]                       = "legrad",
    ["Advanced Radar Tower"]              = "legarad",
    ["Construction Turret"]               = "legnanotc",
    ["Advanced Construction Turret"]      = "legnanotct2",
    ["Naval Radar / Sonar Tower"]          = "legfrad",
    ["Auscultor"]                          = "leganavalsonarstation",
    ["Basic Defense Turret"]              = "leglht",
    ["Anti-Air Tower"]                    = "legrl",
    ["Naval Anti-Air Turret"]             = "legfrl",
    ["Plasma Shield"]                     = "legdeflector",
    ["Rampart"]                           = "legrampart",
  },
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local teamLabs = {}
local teamFaction = {}
local teamLabPositions = {}
local rowRects = {}
local iconRects = {}
local hoverState = { icon = nil, statKey = nil, viewModeKey = nil, teamID = nil }
local followState = { unitID = nil, camPos = nil }
local dragState = { active = false, startX = 0, startY = 0, offsetX = 0, offsetY = 0 }
local uiRects = {
  header = {x1=0,y1=0,x2=0,y2=0},
  minPill = {x1=0,y1=0,x2=0,y2=0},
  iconToggle = {x1=0,y1=0,x2=0,y2=0},
  expandToggle = {x1=0,y1=0,x2=0,y2=0},
  swapToggle = {x1=0,y1=0,x2=0,y2=0},
}
local cachedLayout = { items = {}, maxIcons = 0, totalWidth = 0, headerFontSize = 0, statLeaders = {} }
local selectedTeamID = nil
local pinnedTeamIDs = {}
local MAX_PINNED = 3
local lastRightClickTeamID = nil
local lastRightClickTime = 0
local cachedTopTeamID = nil
local lastClickTime = 0
local lastClickTeamID = nil
local lastIconClickTime = 0
local lastIconClickKey = nil
local iconCycleIndex = {}
local mouseX, mouseY = 0, 0
local flashMarker = nil


local minimized = false
local leaderboardState = {
  mode = false,
  rect = {x1=0,y1=0,x2=0,y2=0},
  panelRect = {x1=0,y1=0,x2=0,y2=0},
  scrollOffset = 0,
  scrollActive = false,
  scrollMaxOffset = 0,
}
local sizeMenu = {
  open = false,
  toggleRect = {x1=0,y1=0,x2=0,y2=0},
  optionRects = {},
  options = {96, 88, 80, 72, 64, 56, 48, 40},
}
local sectionsExpanded = false
local sectionsSwapped = false
local pressWasOnMinimizedIcon = false
local teamArmyValue = {}
local teamDefenseValue = {}
local teamStats = {}
local statSortKey = nil
local statHeaderRects = {
  mps = {x1=0,y1=0,x2=0,y2=0},
  eps = {x1=0,y1=0,x2=0,y2=0},
  mp  = {x1=0,y1=0,x2=0,y2=0},
  ep  = {x1=0,y1=0,x2=0,y2=0},
  av  = {x1=0,y1=0,x2=0,y2=0},
  dv  = {x1=0,y1=0,x2=0,y2=0},
  dd  = {x1=0,y1=0,x2=0,y2=0},
  up  = {x1=0,y1=0,x2=0,y2=0},
  uk  = {x1=0,y1=0,x2=0,y2=0},
}
local activeViewMode = "all"
local viewModeRects = {
  minimal = {x1=0,y1=0,x2=0,y2=0},
  eco     = {x1=0,y1=0,x2=0,y2=0},
  defense = {x1=0,y1=0,x2=0,y2=0},
  offense = {x1=0,y1=0,x2=0,y2=0},
  all     = {x1=0,y1=0,x2=0,y2=0},
}

-- Cached, ready-to-draw layout. Rebuilt only when the underlying data
-- actually changes (once/sec via recountLabs, or instantly on an
-- Expand/Swap click) instead of every single render frame.
local rebuildLayout -- forward declaration; defined after its helper functions below


------------------------------------------------------------
-- RECOUNTING LOGIC (only count FINISHED labs)
------------------------------------------------------------

local function getLatestTeamStat(teamID, fieldName)
  local historyMax = Spring.GetTeamStatsHistory(teamID)
  if not historyMax or historyMax < 1 then return 0 end
  local statsHistory = Spring.GetTeamStatsHistory(teamID, historyMax)
  if statsHistory and statsHistory[1] then
    return statsHistory[1][fieldName] or 0
  end
  return 0
end

local function recountLabs()
  teamLabs = {}
  teamFaction = {}
  teamLabPositions = {}
  teamArmyValue = {}
  teamDefenseValue = {}

  for _, unitID in ipairs(Spring.GetAllUnits()) do
    local unitDefID = Spring.GetUnitDefID(unitID)
    local teamID    = Spring.GetUnitTeam(unitID)
    local ud        = UnitDefs[unitDefID]

    if ud then
      -- Army value: armed mobile units (matches how BAR's own
      -- Spectator HUD widget defines "army"), plus the commander
      -- explicitly included even though that widget excludes it.
      local hasWeapon = ud.weapons and #ud.weapons > 0
      if (hasWeapon and ud.canMove) or isCommanderDef[unitDefID] then
        teamArmyValue[teamID] = (teamArmyValue[teamID] or 0) + (ud.metalCost or 0)
      end
      if hasWeapon and not ud.canMove then
        teamDefenseValue[teamID] = (teamDefenseValue[teamID] or 0) + (ud.metalCost or 0)
      end

      local name = ud.name
      local category = labDisplayNames[name]

      if category then
        -- check if lab is FINISHED
        local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
        if buildProgress == 1 then

          -- detect faction from unit name prefix
          local prefix = name:sub(1,3)
          local faction = "arm"
          if prefix == "cor" then faction = "cor" end
          if prefix == "leg" then faction = "leg" end

          teamFaction[teamID] = faction

          teamLabs[teamID] = teamLabs[teamID] or {}
          teamLabs[teamID][category] = (teamLabs[teamID][category] or 0) + 1

          local px, py, pz = Spring.GetUnitPosition(unitID)
          if px then
            teamLabPositions[teamID] = teamLabPositions[teamID] or {}
            teamLabPositions[teamID][category] = teamLabPositions[teamID][category] or {}
            table.insert(teamLabPositions[teamID][category], { x = px, y = py, z = pz })
          end
        end
      elseif isCommanderDef[unitDefID] then
        -- detect faction from unit name prefix (same convention as labs)
        local prefix = name:sub(1,3)
        local faction = "arm"
        if prefix == "cor" then faction = "cor" end
        if prefix == "leg" then faction = "leg" end

        teamFaction[teamID] = faction

        teamLabs[teamID] = teamLabs[teamID] or {}
        teamLabs[teamID]["Commander"] = (teamLabs[teamID]["Commander"] or 0) + 1

        local px, py, pz = Spring.GetUnitPosition(unitID)
        if px then
          teamLabPositions[teamID] = teamLabPositions[teamID] or {}
          teamLabPositions[teamID]["Commander"] = teamLabPositions[teamID]["Commander"] or {}
          -- Commander skins vary per player, so store the exact
          -- defName here (unlike labs, which resolve it via iconMap)
          table.insert(teamLabPositions[teamID]["Commander"], { x = px, y = py, z = pz, defName = name, unitID = unitID })
        end
      end
    end
  end

  teamStats = {}
  for _, teamID in ipairs(Spring.GetTeamList()) do
    if teamID ~= Spring.GetGaiaTeamID() then
      local _, _, _, mIncome = Spring.GetTeamResources(teamID, "metal")
      local _, _, _, eIncome = Spring.GetTeamResources(teamID, "energy")
      local _, mProduced = Spring.GetTeamResourceStats(teamID, "m")
      local _, eProduced = Spring.GetTeamResourceStats(teamID, "e")
      teamStats[teamID] = {
        mps = mIncome or 0,
        eps = eIncome or 0,
        mp  = mProduced or 0,
        ep  = eProduced or 0,
        av  = teamArmyValue[teamID] or 0,
        dv  = teamDefenseValue[teamID] or 0,
        dd  = getLatestTeamStat(teamID, "damageDealt"),
        up  = getLatestTeamStat(teamID, "unitsProduced"),
        uk  = getLatestTeamStat(teamID, "unitsKilled"),
      }
    end
  end

  rebuildLayout()
end


------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function hitHeader(mx,my)
  local r = uiRects.header
  return mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2
end

local function truncateName(name, extraReserved)
  local maxWidth = nameColW - padding * 2 - (extraReserved or 0)
  local test = name
  while gl.GetTextWidth(test) * nameFontSize > maxWidth do
    test = test:sub(1, #test - 1)
    if #test <= 3 then break end
  end
  if test ~= name then
    test = test .. "…"
  end
  return test
end

local function getFaction(teamID)
  -- if we've already inferred faction for this team, trust that
  if teamFaction[teamID] then
    return teamFaction[teamID]
  end

  -- Try team side first (works for some humans and all AIs)
  local _, _, _, _, side = Spring.GetTeamInfo(teamID, false)
  if side and side ~= "" then
    side = string.lower(side)
    if side:find("arm") then return "arm" end
    if side:find("cor") then return "cor" end
    if side:find("leg") then return "leg" end
  end

  -- Final fallback if we know nothing yet
  return "arm"
end

local function getTeamName(teamID)
  -- Prefer an actual human player bound to this team
  local players = Spring.GetPlayerList(teamID)
  if players and #players > 0 then
    for _, playerID in ipairs(players) do
      local name, active, spectator = Spring.GetPlayerInfo(playerID, false)
      if name and name ~= "" and not spectator then
        if active then
          return name
        else
          return name .. " (disconnected)"
        end
      end
    end
  end

  -- AI team: BAR stores the AI's assigned nickname (e.g. "PsychoPewPew")
  -- as a game rules param, keyed by teamID. This is the same source
  -- BAR's own player list / chat widgets use.
  local _, _, _, isAI = Spring.GetTeamInfo(teamID, false)
  if isAI then
    local niceName = Spring.GetGameRulesParam("ainame_" .. teamID)
    if niceName and niceName ~= "" then
      return niceName .. " (AI)"
    end
    return "AI Player"
  end

  -- Not AI and no bound player found at all -- a human team whose
  -- player slot dropped out entirely, rather than an actual bot.
  return "Disconnected", true
end



-- Finds the team's most metal-concentrated cluster of buildings (their
-- main base), by binning stationary structures into a coarse grid and
-- picking the cell with the highest total metal cost. Computed on
-- demand (double-click), not every recount, since it scans every unit.
-- Classifies a building into a functional category, so base-diversity
-- checks can tell "an actual base" (factory + metal + energy mixed)
-- apart from a monoculture farm, even if that farm has several
-- different unit defs (e.g. multiple turbine tiers/skins) that are
-- still functionally all the same thing.
local function classifyBuildingCategory(ud)
  if labDisplayNames[ud.name] then
    return "factory"
  end
  if ud.extractsMetal and ud.extractsMetal > 0 then
    return "metal"
  end
  if (ud.energyMake and ud.energyMake > 0)
     or (ud.windGenerator and ud.windGenerator > 0)
     or (ud.tidalGenerator and ud.tidalGenerator > 0) then
    return "energy"
  end
  if ud.weapons and #ud.weapons > 0 then
    return "defense"
  end
  return "other"
end

local function findTeamBaseLocation(teamID)
  local units = Spring.GetTeamUnits(teamID)
  if not units or #units == 0 then return nil end

  local cellSize = 300
  local cells = {}

  for _, unitID in ipairs(units) do
    local unitDefID = Spring.GetUnitDefID(unitID)
    local ud = UnitDefs[unitDefID]
    if ud and not ud.canMove then
      local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
      if buildProgress == 1 then
        local x, y, z = Spring.GetUnitPosition(unitID)
        if x then
          local key = math.floor(x / cellSize) .. "," .. math.floor(z / cellSize)
          local cell = cells[key]
          if not cell then
            cell = { totalMetal = 0, sumX = 0, sumZ = 0, count = 0, categories = {}, categoryCount = 0 }
            cells[key] = cell
          end
          cell.totalMetal = cell.totalMetal + (ud.metalCost or 0)
          cell.sumX = cell.sumX + x
          cell.sumZ = cell.sumZ + z
          cell.count = cell.count + 1
          local category = classifyBuildingCategory(ud)
          if not cell.categories[category] then
            cell.categories[category] = true
            cell.categoryCount = cell.categoryCount + 1
          end
        end
      end
    end
  end

  local minCategoryCount = 3

  local bestCell = nil
  local bestScore = -1
  for _, cell in pairs(cells) do
    -- Require real functional variety (factory + metal + energy, etc.),
    -- not just weight for it: a monoculture farm (all tidal generators,
    -- all wind turbines, etc.) can pack in far more buildings per cell
    -- than a genuine base ever does, and can even span a couple of
    -- different unit defs (tiers/skins) while still being functionally
    -- one category -- so a diversity *multiplier* alone can still lose
    -- to sheer volume. Disqualifying low-diversity cells outright is
    -- more decisive.
    if cell.categoryCount >= minCategoryCount then
      local score = cell.totalMetal * cell.count
      if score > bestScore then
        bestScore = score
        bestCell = cell
      end
    end
  end

  -- Fallback for an early-game base that doesn't have 3 distinct
  -- categories yet -- rank everything so we still return something.
  if not bestCell then
    for _, cell in pairs(cells) do
      local score = cell.totalMetal * cell.count * cell.categoryCount
      if score > bestScore then
        bestScore = score
        bestCell = cell
      end
    end
  end

  if not bestCell then return nil end

  local bx = bestCell.sumX / bestCell.count
  local bz = bestCell.sumZ / bestCell.count
  local by = Spring.GetGroundHeight(bx, bz) or 0
  return bx, by, bz
end

local function getSortedTeams()
  local myAllyTeam = Spring.GetMyAllyTeamID()
  local teams = {}
  for _, teamID in ipairs(Spring.GetTeamList()) do
    if teamID ~= Spring.GetGaiaTeamID() then
      local name, isEmptyDisconnected = getTeamName(teamID)
      if not isEmptyDisconnected then
        local _, _, _, _, _, allyTeam = Spring.GetTeamInfo(teamID, false)
        teams[#teams+1] = {
          teamID  = teamID,
          allyTeam= allyTeam,
          name    = name,
          labs    = teamLabs[teamID] or {},
        }
      end
    end
  end
  table.sort(teams, function(a,b)
    if leaderboardState.mode then
      if statSortKey then
        local as = (teamStats[a.teamID] and teamStats[a.teamID][statSortKey]) or 0
        local bs = (teamStats[b.teamID] and teamStats[b.teamID][statSortKey]) or 0
        if as ~= bs then
          return as > bs
        end
      end
      return a.name < b.name
    end

    local aMine = (a.allyTeam == myAllyTeam)
    local bMine = (b.allyTeam == myAllyTeam)
    if sectionsSwapped then
      aMine, bMine = not aMine, not bMine
    end
    if aMine ~= bMine then
      return aMine
    end
    if a.allyTeam == b.allyTeam then
      if statSortKey then
        local as = (teamStats[a.teamID] and teamStats[a.teamID][statSortKey]) or 0
        local bs = (teamStats[b.teamID] and teamStats[b.teamID][statSortKey]) or 0
        if as ~= bs then
          return as > bs
        end
      end
      return a.name < b.name
    end
    return a.allyTeam < b.allyTeam
  end)
  return teams
end

function rebuildLayout()
  local teams = getSortedTeams()

  do
    local rankKey = statSortKey or "av"
    local bestTeamID, bestVal = nil, nil
    for _, t in ipairs(teams) do
      local v = (teamStats[t.teamID] and teamStats[t.teamID][rankKey]) or 0
      if bestVal == nil or v > bestVal then
        bestVal = v
        bestTeamID = t.teamID
      end
    end
    cachedTopTeamID = (bestVal and bestVal > 0) and bestTeamID or nil
  end

  do
    -- Group by actual allyteam (not "mine vs other"), tracking each
    -- group's real representative color. This scales to any number of
    -- ally-teams (FFA included) with no special-casing: whichever
    -- group leads a stat, its own real color is used for the stripe.
    local allyGroups = {}
    for _, t in ipairs(teams) do
      local ally = t.allyTeam
      if not allyGroups[ally] then
        local r, g, b = Spring.GetTeamColor(t.teamID)
        local sums = {}
        for _, col in ipairs(statColumns) do
          sums[col.key] = 0
        end
        allyGroups[ally] = { sums = sums, color = { r or 1, g or 1, b or 1 } }
      end
      local ts = teamStats[t.teamID]
      if ts then
        local sums = allyGroups[ally].sums
        for _, col in ipairs(statColumns) do
          sums[col.key] = sums[col.key] + (ts[col.key] or 0)
        end
      end
    end

    cachedLayout.statLeaders = {}
    for _, col in ipairs(statColumns) do
      local bestVal = nil
      for _, grp in pairs(allyGroups) do
        local v = grp.sums[col.key]
        if bestVal == nil or v > bestVal then
          bestVal = v
        end
      end
      if bestVal ~= nil then
        local leaders = {}
        for ally, grp in pairs(allyGroups) do
          if grp.sums[col.key] == bestVal then
            leaders[#leaders+1] = ally
          end
        end
        if #leaders == 1 then
          cachedLayout.statLeaders[col.key] = allyGroups[leaders[1]].color
        end
      end
    end
  end

  local rawItems = {}
  for _, t in ipairs(teams) do
    local faction = getFaction(t.teamID)
    local r, g, b = Spring.GetTeamColor(t.teamID)

    local ownedLabs = {}
    for labName, _ in pairs(t.labs) do
      if type(labName) == "string" then
        ownedLabs[#ownedLabs+1] = labName
      end
    end
    table.sort(ownedLabs, function(a, b2)
      local ta, tb = techTierOrder[a] or 99, techTierOrder[b2] or 99
      if ta == tb then return a < b2 end
      return ta < tb
    end)

    local icons = {}
    for _, labName in ipairs(ownedLabs) do
      if isCategoryVisibleInView(labName, activeViewMode) then
      local defName
      local overlayDefNames = nil
      if labName == "Commander" then
        local comList = teamLabPositions[t.teamID] and teamLabPositions[t.teamID]["Commander"]
        defName = comList and comList[1] and comList[1].defName

        -- If there's more than one commander (resurrected/given from
        -- another faction, or a duplicate), the team's HOME faction
        -- commander (if still alive) stays the main full-size icon --
        -- everything else becomes a small overlay icon stacked from
        -- the top-left corner. If the home-faction commander has died,
        -- whichever one is first in the list simply becomes the new
        -- main icon (matching "if the original dies, the resurrected
        -- one becomes the new full icon").
        if comList and #comList > 1 then
          local primaryIdx = nil
          for i, com in ipairs(comList) do
            local prefix = com.defName and com.defName:sub(1,3)
            if prefix == faction then
              primaryIdx = i
              break
            end
          end
          if not primaryIdx then primaryIdx = 1 end

          defName = comList[primaryIdx].defName

          local extras = {}
          for i, com in ipairs(comList) do
            if i ~= primaryIdx then
              extras[#extras+1] = com.defName
            end
          end
          if #extras > 0 then
            overlayDefNames = extras
          end
        end
      else
        local factionMap = iconMap[faction]
        defName = factionMap and factionMap[labName]
      end
      if defName and UnitDefNames[defName] then
        local tier = techTierOrder[labName]
        local tierLabel = (tier == 0 and "COM")
                        or (tier == 1 and "T1")
                        or (tier == 2 and "T2")
                        or ((tier == 3 or tier == 4) and "EXP")
                        or (tier == 5 and "FUS")
                        or (tier == 6 and "AFUS")
                        or (tier == 7 and "LRPC")
                        or (tier == 8 and "NUKE")
                        or (tier == 9 and "ANTI")
                        or (tier == 10 and "SW")
                        or (tier == 11 and "PLSR")
                        or (tier == 12 and "PIN")
                        or (tier == 13 and "JUNO")
                        or (tier == 14 and "XAIR")
                        or (tier == 15 and "EAFUS")
                        or (tier == 16 and "EPLSR")
                        or (tier == 17 and "PWN")
                        or (tier == 18 and "ICM")
                        or (tier == 19 and "NAPLM")
                        or (tier == 20 and "GEO")
                        or (tier == 21 and "OGEO")
                        or (tier == 22 and "AGEO")
                        or (tier == 23 and "AOGEO")
                        or (tier == 24 and "SGEO")
                        or (tier == 25 and "MEX")
                        or (tier == 26 and "AMEX")
                        or (tier == 27 and "SOL")
                        or (tier == 28 and "ASOL")
                        or (tier == 29 and "WIND")
                        or (tier == 30 and "AWIND")
                        or (tier == 31 and "TIDE")
                        or (tier == 32 and "MSTOR")
                        or (tier == 33 and "ESTOR")
                        or (tier == 34 and "CONV")
                        or (tier == 35 and "ACONV")
                        or (tier == 36 and "ECONV")
                        or (tier == 37 and "RAD")
                        or (tier == 38 and "ARAD")
                        or (tier == 39 and "SONAR")
                        or (tier == 40 and "ASONAR")
                        or (tier == 41 and "NANO")
                        or (tier == 42 and "ANANO")
                        or (tier == 43 and "NRAD")
                        or (tier == 44 and "AUSC")
                        or (tier == 45 and "T1LT")
                        or (tier == 46 and "AA")
                        or (tier == 47 and "NAVAA")
                        or (tier == 48 and "SHIELD")
                        or (tier == 49 and "POPUP")
                        or (tier == 50 and "ARTY")
                        or (tier == 51 and "EMP")
                        or (tier == 52 and "AAMSL")
                        or (tier == 53 and "TWIN")
                        or (tier == 54 and "RAMPT")
                        or nil

        -- Cortex's Pulsar-tier unit is actually called "Bulwark", so
        -- give it its own badge text instead of the generic PLSR/EPLSR
        -- used by Armada's Pulsar and Legion's Bastion.
        if faction == "cor" then
          if tier == 11 then tierLabel = "BULW" end
          if tier == 16 then tierLabel = "EBULW" end
        end
        if faction == "leg" then
          if tier == 11 then tierLabel = "BAST" end
          if tier == 16 then tierLabel = "EBAST" end
          if tier == 45 then tierLabel = "T1HT" end
        end
        icons[#icons+1] = {
          defName = defName,
          overlayDefNames = overlayDefNames,
          labName = labName,
          count = t.labs[labName] or 1,
          tierLabel = tierLabel,
        }
      end
      end
    end

    local badgeReserve = 0
    if t.teamID == cachedTopTeamID then badgeReserve = badgeReserve + 22 end
    for _, pid in ipairs(pinnedTeamIDs) do
      if pid == t.teamID then
        badgeReserve = badgeReserve + 22
        break
      end
    end

    rawItems[#rawItems+1] = {
      itype = "team",
      teamID = t.teamID,
      allyTeam = t.allyTeam,
      displayName = truncateName(t.name, badgeReserve),
      colorR = r or 1, colorG = g or 1, colorB = b or 1,
      icons = icons,
    }
  end

  local items = {}

  local pinnedItems = {}
  local remainingRawItems = {}
  do
    local rawByTeamID = {}
    for _, it in ipairs(rawItems) do
      rawByTeamID[it.teamID] = it
    end
    local pinnedSet = {}
    for _, pid in ipairs(pinnedTeamIDs) do
      if rawByTeamID[pid] then
        pinnedItems[#pinnedItems+1] = rawByTeamID[pid]
        pinnedSet[pid] = true
      end
    end
    for _, it in ipairs(rawItems) do
      if not pinnedSet[it.teamID] then
        remainingRawItems[#remainingRawItems+1] = it
      end
    end
  end

  if #pinnedItems > 0 then
    for _, it in ipairs(pinnedItems) do
      items[#items+1] = it
    end
    items[#items+1] = { itype = "pindivider" }
  end

  if leaderboardState.mode then
    for _, it in ipairs(remainingRawItems) do
      items[#items+1] = it
    end
  else
    local prevAllyTeam = nil
    local usedMainToggle = false
    for _, it in ipairs(remainingRawItems) do
      if prevAllyTeam ~= nil and it.allyTeam ~= prevAllyTeam then
        if not usedMainToggle then
          usedMainToggle = true
          items[#items+1] = { itype = "maintoggle" }
          if not sectionsExpanded then
            break
          end
        else
          items[#items+1] = { itype = "divider" }
        end
      end
      items[#items+1] = it
      prevAllyTeam = it.allyTeam
    end
  end

  cachedLayout.items = items

  local maxIcons = 0
  for _, item in ipairs(items) do
    if item.itype == "team" and #item.icons > maxIcons then
      maxIcons = #item.icons
    end
  end
  cachedLayout.maxIcons = maxIcons

  cachedLayout.headerFontSize = math.floor(iconSize * 0.55)
  local toggleFontSize = 14
  local togglePad = 6
  local toggleButtonWidth = gl.GetTextWidth("Icon") * toggleFontSize + togglePad * 2
  local lbButtonWidth = gl.GetTextWidth("Leaderboard") * 13 + 6 * 2 + 10
  local szButtonWidth = gl.GetTextWidth("Size") * 13 + 6 * 2 + 10
  local headerTextWidth = gl.GetTextWidth("Base Tracker") * cachedLayout.headerFontSize + padding * 2
                         + toggleButtonWidth + lbButtonWidth + szButtonWidth + padding * 2

  cachedLayout.totalWidth = nameColW + (cachedLayout.maxIcons * iconSize) + padding * 2
  cachedLayout.totalWidth = math.max(cachedLayout.totalWidth, headerTextWidth)
end

local function isPinned(teamID)
  for _, id in ipairs(pinnedTeamIDs) do
    if id == teamID then return true end
  end
  return false
end

local function togglePin(teamID)
  for i, id in ipairs(pinnedTeamIDs) do
    if id == teamID then
      table.remove(pinnedTeamIDs, i)
      return
    end
  end
  if #pinnedTeamIDs < MAX_PINNED then
    pinnedTeamIDs[#pinnedTeamIDs+1] = teamID
  end
end

local function hitTeamRow(mx,my)
  for teamID, r in pairs(rowRects) do
    if mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2 then
      return teamID
    end
  end
  return nil
end

local function hitIcon(mx,my)
  for _, rect in ipairs(iconRects) do
    if mx>=rect.x1 and mx<=rect.x2 and my>=rect.y1 and my<=rect.y2 then
      return rect
    end
  end
  return nil
end

local function hitStatHeader(mx,my)
  for _, col in ipairs(statColumns) do
    local r = statHeaderRects[col.key]
    if mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2 then
      return col.key
    end
  end
  return nil
end

local function hitViewModeButton(mx,my)
  for _, col in ipairs(viewModeColumns) do
    local r = viewModeRects[col.key]
    if mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2 then
      return col.key
    end
  end
  return nil
end

local function jumpCameraTo(x, y, z, height, transitionTime)
  local camState = Spring.GetCameraState()
  camState.px = x
  camState.py = y
  camState.pz = z
  if camState.height ~= nil then
    camState.height = height
  end
  if camState.dist ~= nil then
    camState.dist = height
  end
  Spring.SetCameraState(camState, transitionTime or 1.2)
end

-- Position-only update, used every frame while actively following a
-- moving commander. Doesn't touch height/dist so the player can still
-- freely scroll-zoom while tracking.
local function followCameraTo(x, y, z)
  local camState = Spring.GetCameraState()
  camState.px = x
  camState.py = y
  camState.pz = z
  Spring.SetCameraState(camState, 0)
end

-- Jumps to (and cycles through, on repeated calls) all instances of a
-- given icon's structure/commander type for a team. Shared by both the
-- double-click handler and the spacebar-while-hovering shortcut.
local function cycleAndJumpToIcon(teamID, labName)
  local clickKey = teamID .. "|" .. labName
  local list = teamLabPositions[teamID] and teamLabPositions[teamID][labName]
  if not list or #list == 0 then return end

  local idx = (iconCycleIndex[clickKey] or 0) % #list + 1
  iconCycleIndex[clickKey] = idx
  local pos = list[idx]

  jumpCameraTo(pos.x, pos.y, pos.z, 2000)
  flashMarker = {
    x = pos.x, y = pos.y, z = pos.z,
    startTime = os.clock(),
    unitID = (labName == "Commander") and pos.unitID or nil,
  }
  if labName == "Commander" and pos.unitID then
    followState.unitID = pos.unitID
    followState.camPos = nil
  end
  selectedTeamID = teamID
end

-- Jumps to (and flashes) a team's metal-weighted base center. Shared by
-- both the row double-click handler and the spacebar shortcut.
local function jumpToTeamBaseCenter(teamID)
  selectedTeamID = teamID
  local bx, by, bz = findTeamBaseLocation(teamID)
  if bx then
    jumpCameraTo(bx, by, bz, 2500)
    flashMarker = { x = bx, y = by, z = bz, startTime = os.clock(), unitID = nil }
  end
end

------------------------------------------------------------
-- ENGINE EVENTS (RECOUNT-BASED)
------------------------------------------------------------

function widget:Initialize()
  chartX = Spring.GetConfigInt("LabTracker_X", chartX or 300)
  chartY = Spring.GetConfigInt("LabTracker_Y", chartY or 300)
  minimized = Spring.GetConfigInt("LabTracker_Minimized", 0) == 1
  sectionsExpanded = Spring.GetConfigInt("LabTracker_Expanded", 0) == 1
  sectionsSwapped = Spring.GetConfigInt("LabTracker_Swapped", 0) == 1
  local viewModeKeys = {"minimal", "eco", "defense", "offense", "all"}
  activeViewMode = viewModeKeys[Spring.GetConfigInt("LabTracker_ViewMode", 5)] or "all"
  local savedStatSortIdx = Spring.GetConfigInt("LabTracker_StatSort", 0)
  statSortKey = (savedStatSortIdx > 0 and statColumns[savedStatSortIdx] and statColumns[savedStatSortIdx].key) or nil
  leaderboardState.mode = Spring.GetConfigInt("LabTracker_Leaderboard", 0) == 1
  local savedIconSize = Spring.GetConfigInt("LabTracker_IconSize", iconSize)
  local validSize = false
  for _, s in ipairs(sizeMenu.options) do
    if s == savedIconSize then validSize = true end
  end
  if validSize then
    iconSize = savedIconSize
    rowH = iconSize + 10
    nameColW = iconSize * 2.5
  end
  recountLabs()
end

function widget:GameFrame(frame)
  if frame % 150 == 0 then
    recountLabs()
  end
end

------------------------------------------------------------
-- MOUSE (position is polled each frame in DrawScreen instead
-- of relying on the widget:MouseMove callin, which was found
-- to never fire on this setup)
------------------------------------------------------------

function widget:MousePress(mx,my,button)
  if button ~= 1 and button ~= 3 then return false end

  if button == 3 then
    local teamID = hitTeamRow(mx, my)
    if not teamID then return false end

    local t = os.clock()
    if teamID == lastRightClickTeamID and (t - lastRightClickTime) <= doubleClickThreshold then
      togglePin(teamID)
      lastRightClickTeamID = nil
      rebuildLayout()
      return true
    end

    lastRightClickTeamID = teamID
    lastRightClickTime = t
    return true
  end

  -- Any click interrupts an active camera-follow; the Commander
  -- double-click branch below re-engages it if that's what happened.
  followState.unitID = nil

  if minimized then
    local r = uiRects.minPill
    if mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2 then
      dragState.active = true
      dragState.startX = mx
      dragState.startY = my
      dragState.offsetX = chartX
      dragState.offsetY = chartY
      pressWasOnMinimizedIcon = true
      return true
    end
    return false
  end

  if sizeMenu.open then
    for _, r in ipairs(sizeMenu.optionRects) do
      if mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2 then
        iconSize = r.size
        rowH = iconSize + 10
        nameColW = iconSize * 2.5
        Spring.SetConfigInt("LabTracker_IconSize", iconSize)
        sizeMenu.open = false
        rebuildLayout()
        return true
      end
    end
  end

  local sr = sizeMenu.toggleRect
  if mx>=sr.x1 and mx<=sr.x2 and my>=sr.y1 and my<=sr.y2 then
    sizeMenu.open = not sizeMenu.open
    return true
  end

  if sizeMenu.open then
    sizeMenu.open = false
  end

  local lr = leaderboardState.rect
  if mx>=lr.x1 and mx<=lr.x2 and my>=lr.y1 and my<=lr.y2 then
    leaderboardState.mode = not leaderboardState.mode
    Spring.SetConfigInt("LabTracker_Leaderboard", leaderboardState.mode and 1 or 0)
    rebuildLayout()
    return true
  end

  local tr = uiRects.iconToggle
  if mx>=tr.x1 and mx<=tr.x2 and my>=tr.y1 and my<=tr.y2 then
    minimized = true
    Spring.SetConfigInt("LabTracker_Minimized", 1)
    return true
  end

  local sr = uiRects.swapToggle
  if mx>=sr.x1 and mx<=sr.x2 and my>=sr.y1 and my<=sr.y2 then
    sectionsSwapped = not sectionsSwapped
    Spring.SetConfigInt("LabTracker_Swapped", sectionsSwapped and 1 or 0)
    rebuildLayout()
    return true
  end

  local er = uiRects.expandToggle
  if mx>=er.x1 and mx<=er.x2 and my>=er.y1 and my<=er.y2 then
    sectionsExpanded = not sectionsExpanded
    Spring.SetConfigInt("LabTracker_Expanded", sectionsExpanded and 1 or 0)
    rebuildLayout()
    return true
  end

  for _, col in ipairs(statColumns) do
    local hr = statHeaderRects[col.key]
    if mx>=hr.x1 and mx<=hr.x2 and my>=hr.y1 and my<=hr.y2 then
      if statSortKey == col.key then
        statSortKey = nil
      else
        statSortKey = col.key
      end
      local savedIdx = 0
      for i, c in ipairs(statColumns) do
        if c.key == statSortKey then
          savedIdx = i
          break
        end
      end
      Spring.SetConfigInt("LabTracker_StatSort", savedIdx)
      rebuildLayout()
      return true
    end
  end

  for _, col in ipairs(viewModeColumns) do
    local hr = viewModeRects[col.key]
    if mx>=hr.x1 and mx<=hr.x2 and my>=hr.y1 and my<=hr.y2 then
      activeViewMode = col.key
      for i, k in ipairs({"minimal", "eco", "defense", "offense", "all"}) do
        if k == activeViewMode then
          Spring.SetConfigInt("LabTracker_ViewMode", i)
          break
        end
      end
      rebuildLayout()
      return true
    end
  end

  if hitHeader(mx,my) then
    dragState.active = true
    dragState.startX = mx
    dragState.startY = my
    dragState.offsetX = chartX
    dragState.offsetY = chartY
    return true
  end

  local iconRect = hitIcon(mx,my)
  if iconRect then
    local t = os.clock()
    local clickKey = iconRect.teamID .. "|" .. iconRect.labName

    if clickKey == lastIconClickKey and (t - lastIconClickTime) <= doubleClickThreshold then
      cycleAndJumpToIcon(iconRect.teamID, iconRect.labName)
      lastIconClickKey = nil
      return true
    end

    selectedTeamID = iconRect.teamID
    lastIconClickKey = clickKey
    lastIconClickTime = t
    lastClickTeamID = nil
    return true
  end

  local teamID = hitTeamRow(mx,my)
  if not teamID then return false end

  local t = os.clock()
  if teamID == lastClickTeamID and (t - lastClickTime) <= doubleClickThreshold then
    local _, leaderPlayerID = Spring.GetTeamInfo(teamID, false)
    if leaderPlayerID and leaderPlayerID >= 0 then
      Spring.SendCommands("spectatorview " .. leaderPlayerID)
    end

    jumpToTeamBaseCenter(teamID)

    return true
  end

  selectedTeamID = teamID
  lastClickTeamID = teamID
  lastClickTime = t
  lastIconClickKey = nil
  return true
end

------------------------------------------------------------
-- SAVE WINDOW POSITION WHEN DRAGGING STOPS
------------------------------------------------------------

function widget:MouseRelease(mx, my, button)
  if button == 1 and dragState.active then
    dragState.active = false

    if pressWasOnMinimizedIcon then
      pressWasOnMinimizedIcon = false
      local movedDist = math.sqrt((mx-dragState.startX)^2 + (my-dragState.startY)^2)
      if movedDist < 5 then
        minimized = false
        Spring.SetConfigInt("LabTracker_Minimized", 0)
      end
    end

    Spring.SetConfigInt("LabTracker_X", chartX)
    Spring.SetConfigInt("LabTracker_Y", chartY)
    return true
  end
end

function widget:KeyPress(key, mods, isRepeat)
  if isRepeat then return false end
  if key == string.byte(" ") then
    if hoverState.icon then
      cycleAndJumpToIcon(hoverState.icon.teamID, hoverState.icon.labName)
      return true

    elseif hoverState.teamID then
      jumpToTeamBaseCenter(hoverState.teamID)
      return true

    elseif hoverState.sizeOption then
      iconSize = hoverState.sizeOption.size
      rowH = iconSize + 10
      nameColW = iconSize * 2.5
      Spring.SetConfigInt("LabTracker_IconSize", iconSize)
      sizeMenu.open = false
      rebuildLayout()
      return true

    elseif hoverState.sizeToggle then
      sizeMenu.open = not sizeMenu.open
      return true

    elseif hoverState.leaderboardToggle then
      leaderboardState.mode = not leaderboardState.mode
      Spring.SetConfigInt("LabTracker_Leaderboard", leaderboardState.mode and 1 or 0)
      rebuildLayout()
      return true

    elseif hoverState.iconToggle then
      minimized = true
      Spring.SetConfigInt("LabTracker_Minimized", 1)
      return true

    elseif hoverState.expandToggle then
      sectionsExpanded = not sectionsExpanded
      Spring.SetConfigInt("LabTracker_Expanded", sectionsExpanded and 1 or 0)
      rebuildLayout()
      return true

    elseif hoverState.swapToggle then
      sectionsSwapped = not sectionsSwapped
      Spring.SetConfigInt("LabTracker_Swapped", sectionsSwapped and 1 or 0)
      rebuildLayout()
      return true

    elseif hoverState.statKey then
      if statSortKey == hoverState.statKey then
        statSortKey = nil
      else
        statSortKey = hoverState.statKey
      end
      local savedIdx = 0
      for i, c in ipairs(statColumns) do
        if c.key == statSortKey then
          savedIdx = i
          break
        end
      end
      Spring.SetConfigInt("LabTracker_StatSort", savedIdx)
      rebuildLayout()
      return true

    elseif hoverState.viewModeKey then
      activeViewMode = hoverState.viewModeKey
      for i, k in ipairs({"minimal", "eco", "defense", "offense", "all"}) do
        if k == activeViewMode then
          Spring.SetConfigInt("LabTracker_ViewMode", i)
          break
        end
      end
      rebuildLayout()
      return true
    end
  end
  return false
end

function widget:MouseWheel(up, value)
  if not leaderboardState.scrollActive then return false end
  local mx, my = Spring.GetMouseState()
  if mx < leaderboardState.panelRect.x1 or mx > leaderboardState.panelRect.x2 or my < leaderboardState.panelRect.y1 or my > leaderboardState.panelRect.y2 then
    return false
  end

  local step = 40
  if up then
    leaderboardState.scrollOffset = math.max(0, leaderboardState.scrollOffset - step)
  else
    leaderboardState.scrollOffset = math.min(leaderboardState.scrollMaxOffset, leaderboardState.scrollOffset + step)
  end
  return true
end

------------------------------------------------------------
-- FLASH MARKER (world-space "found it" circle at a jump target)
------------------------------------------------------------

local flashDuration = 2.0
local flashRadius = 90
local flashSegments = 32
local flashBaseOpacity = 0.30

function widget:DrawWorld()
  if not flashMarker then return end

  local elapsed = os.clock() - flashMarker.startTime
  if elapsed > flashDuration then
    flashMarker = nil
    return
  end

  local fx, fy, fz = flashMarker.x, flashMarker.y, flashMarker.z
  if flashMarker.unitID then
    local ux, uy, uz = Spring.GetUnitPosition(flashMarker.unitID)
    if ux then
      fx, fy, fz = ux, uy, uz
    end
  end

  -- 7 pulses spread evenly across flashDuration seconds
  local alpha = flashBaseOpacity * math.abs(math.sin((7 * math.pi / flashDuration) * elapsed))
  if alpha < 0.01 then return end

  gl.DepthTest(true)
  gl.DepthMask(false)
  gl.Culling(false)
  gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

  gl.Color(0, 1, 0, alpha)
  gl.BeginEnd(GL.TRIANGLE_FAN, function()
    gl.Vertex(fx, fy + 20, fz)
    for i = 0, flashSegments do
      local theta = (i / flashSegments) * 2 * math.pi
      gl.Vertex(fx + flashRadius * math.cos(theta), fy + 20, fz + flashRadius * math.sin(theta))
    end
  end)

  gl.Color(1, 1, 1, 1)
  gl.DepthMask(true)
end

------------------------------------------------------------
-- DRAW
------------------------------------------------------------

function widget:DrawScreen()
  gl.Blending(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

  local mx, my = Spring.GetMouseState()
  mouseX, mouseY = mx, my

  if dragState.active then
    chartX = dragState.offsetX + (mx - dragState.startX)
    chartY = dragState.offsetY + (my - dragState.startY)
  else
    hoverState.teamID = hitTeamRow(mx, my)
    hoverState.icon   = hitIcon(mx, my)
    hoverState.statKey = hitStatHeader(mx, my)
    hoverState.viewModeKey = hitViewModeButton(mx, my)

    local function ptIn(r)
      return r and mx>=r.x1 and mx<=r.x2 and my>=r.y1 and my<=r.y2
    end
    hoverState.sizeToggle = ptIn(sizeMenu.toggleRect)
    hoverState.leaderboardToggle = ptIn(leaderboardState.rect)
    hoverState.iconToggle = ptIn(uiRects.iconToggle)
    hoverState.expandToggle = ptIn(uiRects.expandToggle)
    hoverState.swapToggle = ptIn(uiRects.swapToggle)
    hoverState.sizeOption = nil
    if sizeMenu.open then
      for _, r in ipairs(sizeMenu.optionRects) do
        if ptIn(r) then hoverState.sizeOption = r; break end
      end
    end
  end

  if followState.unitID and followState.camPos then
    local camState = Spring.GetCameraState()
    local dx = (camState.px or followState.camPos.px) - followState.camPos.px
    local dz = (camState.pz or followState.camPos.pz) - followState.camPos.pz
    if math.sqrt(dx*dx + dz*dz) > 5 then
      -- player panned/rotated the camera manually (edge-scroll, arrow
      -- keys, middle-mouse drag, etc.) -- hand control back to them
      followState.unitID = nil
    end
  end

  if followState.unitID then
    local fx, fy, fz = Spring.GetUnitPosition(followState.unitID)
    if fx then
      followCameraTo(fx, fy, fz)
      followState.camPos = { px = fx, pz = fz }
    else
      followState.unitID = nil
    end
  else
    followState.camPos = nil
  end

  if minimized then
    rowRects = {}
    iconRects = {}

    local buttonW = 160
    local buttonH = 100

    local px1, py1 = chartX, chartY - buttonH
    local px2, py2 = chartX + buttonW, chartY

    uiRects.minPill.x1, uiRects.minPill.y1, uiRects.minPill.x2, uiRects.minPill.y2 = px1, py1, px2, py2

    gl.Color(0, 0, 0, 0.55)
    gl.Rect(px1, py1, px2, py2)

    gl.Color(1, 1, 1, 0.35)
    gl.Rect(px1, py1, px2, py1 + 1)
    gl.Rect(px1, py2 - 1, px2, py2)

    local cx = (px1 + px2) * 0.5
    local cy = (py1 + py2) * 0.5

    gl.Color(1, 1, 1, 1)
    gl.Text("Base Tracker", cx, cy + 10, 20, "oc")

    gl.Color(0.3, 1, 0.3, 1)
    gl.Text("minimized", cx, cy - 20, 16, "oc")

    gl.Color(1, 1, 1, 1)
    return
  end

  rowRects = {}
  iconRects = {}

  local layoutItems = cachedLayout.items
  if #layoutItems == 0 then return end

  local maxIcons = cachedLayout.maxIcons
  local headerFontSize = cachedLayout.headerFontSize
  local totalWidth = cachedLayout.totalWidth

  local x = chartX
  local y = chartY

  local contentHeight = 0
  for _, item in ipairs(layoutItems) do
    local h = rowH
    if item.itype == "pindivider" then h = pinDividerRowH
    elseif item.itype ~= "team" then h = dividerRowH end
    contentHeight = contentHeight + h
  end
  local height = rowH + statsRowH + viewModeRowH + contentHeight + padding * 2

  local fixedHeaderHeight = rowH + statsRowH + viewModeRowH
  local viewportHeightUnclamped = contentHeight
  -- Same scroll mechanism as before, now triggered by overflow in
  -- ANY mode (Leaderboard or normal grouped/expanded), not just
  -- Leaderboard specifically -- the underlying field names still say
  -- "leaderboardState" from when this was first built, but the logic
  -- itself is generic.
  leaderboardState.scrollActive = (y - height) < 0

  local drawHeight = height
  local viewportHeight = viewportHeightUnclamped
  if leaderboardState.scrollActive then
    drawHeight = math.min(height, y)
    viewportHeight = drawHeight - fixedHeaderHeight - padding * 2
    leaderboardState.scrollMaxOffset = math.max(0, contentHeight - viewportHeight)
    leaderboardState.scrollOffset = math.max(0, math.min(leaderboardState.scrollOffset, leaderboardState.scrollMaxOffset))
  else
    leaderboardState.scrollOffset = 0
    leaderboardState.scrollMaxOffset = 0
  end

  gl.Color(0,0,0,backgroundOpacity)
  gl.Rect(x, y - drawHeight, x + totalWidth, y + padding)
  leaderboardState.panelRect.x1, leaderboardState.panelRect.y1, leaderboardState.panelRect.x2, leaderboardState.panelRect.y2 = x, y - drawHeight, x + totalWidth, y + padding

  local headerHeight = rowH
  uiRects.header.x1 = x
  uiRects.header.y1 = y - headerHeight
  uiRects.header.x2 = x + totalWidth
  uiRects.header.y2 = y

  gl.Color(0.1,0.1,0.1,0.8)
  gl.Rect(uiRects.header.x1, uiRects.header.y1, uiRects.header.x2, uiRects.header.y2)

  gl.Color(1,1,1,1)
  gl.Text("Base Tracker", x + padding, y - rowH*0.3 - 7, headerFontSize, "o")

  do
    local toggleLabel = "Icon"
    local toggleFontSize = 14
    local togglePad = 6
    local toggleTW = gl.GetTextWidth(toggleLabel) * toggleFontSize
    local togglePillW = toggleTW + togglePad * 2
    local togglePillH = toggleFontSize + togglePad * 2

    local tx2 = uiRects.header.x2 - togglePad
    local tx1 = tx2 - togglePillW
    local ty2 = uiRects.header.y2 - togglePad
    local ty1 = ty2 - togglePillH
    local tcy = (ty1 + ty2) / 2

    uiRects.iconToggle.x1, uiRects.iconToggle.y1, uiRects.iconToggle.x2, uiRects.iconToggle.y2 = tx1, ty1, tx2, ty2

    do
      local lbLabel = "Leaderboard"
      local lbFontSize = 13
      local lbPad = 6
      local lbTW = gl.GetTextWidth(lbLabel) * lbFontSize
      local lbPillW = lbTW + lbPad * 2
      local lbPillH = lbFontSize + lbPad * 2

      local lbGap = 10
      local lbx2 = tx1 - lbGap
      local lbx1 = lbx2 - lbPillW
      local lbcy = tcy
      local lby1 = lbcy - lbPillH / 2
      local lby2 = lbcy + lbPillH / 2

      leaderboardState.rect.x1, leaderboardState.rect.y1, leaderboardState.rect.x2, leaderboardState.rect.y2 = lbx1, lby1, lbx2, lby2

      if leaderboardState.mode then
        gl.Color(1, 0.85, 0.2, 0.9)
        gl.Rect(lbx1, lby1, lbx2, lby2)
        gl.Color(0, 0, 0, 1)
      else
        gl.Color(1, 1, 1, 0.15)
        gl.Rect(lbx1, lby1, lbx2, lby2)
        gl.Color(1, 1, 1, 0.9)
      end
      gl.Text(lbLabel, (lbx1 + lbx2) / 2, lbcy - lbFontSize * 0.3, lbFontSize, "oc")
      gl.Color(1, 1, 1, 1)

      do
        local szLabel = "Size"
        local szFontSize = 13
        local szPad = 6
        local szTW = gl.GetTextWidth(szLabel) * szFontSize
        local szPillW = szTW + szPad * 2
        local szPillH = lbPillH

        local szGap = 10
        local szx2 = lbx1 - szGap
        local szx1 = szx2 - szPillW
        local szcy = lbcy
        local szy1 = szcy - szPillH / 2
        local szy2 = szcy + szPillH / 2

        sizeMenu.toggleRect.x1, sizeMenu.toggleRect.y1, sizeMenu.toggleRect.x2, sizeMenu.toggleRect.y2 = szx1, szy1, szx2, szy2

        if sizeMenu.open then
          gl.Color(1, 0.85, 0.2, 0.9)
          gl.Rect(szx1, szy1, szx2, szy2)
          gl.Color(0, 0, 0, 1)
        else
          gl.Color(1, 1, 1, 0.15)
          gl.Rect(szx1, szy1, szx2, szy2)
          gl.Color(1, 1, 1, 0.9)
        end
        gl.Text(szLabel, (szx1 + szx2) / 2, szcy - szFontSize * 0.3, szFontSize, "oc")
        gl.Color(1, 1, 1, 1)
      end
    end

    gl.Color(1, 1, 1, 0.15)
    gl.Rect(tx1, ty1, tx2, ty2)

    gl.Color(1, 1, 1, 0.9)
    gl.Text(toggleLabel, tx1 + togglePad, tcy - toggleFontSize * 0.3, toggleFontSize, "o")
  end

  do
    local descText = (hoverState.statKey and statDescriptions[hoverState.statKey])
                   or (hoverState.viewModeKey and viewModeDescriptions[hoverState.viewModeKey])
    if descText then
      local maxDescWidth = totalWidth - padding * 4
      local descFontSize = 13
      local minDescFontSize = 8
      while descFontSize > minDescFontSize
            and gl.GetTextWidth(descText) * descFontSize > maxDescWidth do
        descFontSize = descFontSize - 0.5
      end
      gl.Color(0.75, 0.85, 1, 0.95)
      local descY = (uiRects.iconToggle.y1 + uiRects.header.y1) / 2
      descY = math.min(descY, uiRects.iconToggle.y1 - 7 - descFontSize * 0.6)
      descY = math.max(descY, uiRects.header.y1 + 4)
      gl.Text(descText, (x + x + totalWidth) / 2, descY, descFontSize, "oc")
    end
  end

  local headerY = y - rowH
  local rowY = headerY

  do
    local statsTop = rowY
    local statsBottom = rowY - statsRowH
    local colW = totalWidth / #statColumns
    local statFontSize = 13

    gl.Color(0.15, 0.15, 0.15, 0.75)
    gl.Rect(x, statsBottom, x + totalWidth, statsTop)

    local ccy = (statsTop + statsBottom) / 2
    for i, col in ipairs(statColumns) do
      local cx1 = x + (i - 1) * colW
      local cx2 = x + i * colW
      local ccx = (cx1 + cx2) / 2

      local hr = statHeaderRects[col.key]
      hr.x1, hr.y1, hr.x2, hr.y2 = cx1, statsBottom, cx2, statsTop

      if statSortKey == col.key then
        gl.Color(1, 0.85, 0.2, 0.9)
        gl.Rect(cx1, statsBottom, cx2, statsTop)
        gl.Color(0, 0, 0, 1)
      else
        gl.Color(1, 1, 1, 0.85)
      end
      gl.Text(col.label, ccx, ccy - statFontSize * 0.3, statFontSize, "oc")

      local leaderColor = cachedLayout.statLeaders[col.key]
      if leaderColor then
        local boost = 1.6
        local br = math.min(1, leaderColor[1] * boost)
        local bg = math.min(1, leaderColor[2] * boost)
        local bb = math.min(1, leaderColor[3] * boost)
        gl.Color(br, bg, bb, 1)
        gl.Rect(cx1, statsBottom, cx2 - 1, statsBottom + 6)
      end
    end

    gl.Color(1, 1, 1, 1)
    rowY = rowY - statsRowH
  end

  do
    local vmTop = rowY
    local vmBottom = rowY - viewModeRowH
    local vmColW = totalWidth / #viewModeColumns
    local vmFontSize = 12

    gl.Color(0.15, 0.15, 0.15, 0.75)
    gl.Rect(x, vmBottom, x + totalWidth, vmTop)

    local vmCy = (vmTop + vmBottom) / 2
    for i, col in ipairs(viewModeColumns) do
      local cx1 = x + (i - 1) * vmColW
      local cx2 = x + i * vmColW
      local ccx = (cx1 + cx2) / 2

      local hr = viewModeRects[col.key]
      hr.x1, hr.y1, hr.x2, hr.y2 = cx1, vmBottom, cx2, vmTop

      if activeViewMode == col.key then
        gl.Color(1, 0.85, 0.2, 0.9)
        gl.Rect(cx1, vmBottom, cx2, vmTop)
        gl.Color(0, 0, 0, 1)
      else
        gl.Color(1, 1, 1, 0.85)
      end
      gl.Text(col.label, ccx, vmCy - vmFontSize * 0.3, vmFontSize, "oc")
    end

    gl.Color(1, 1, 1, 1)
    rowY = rowY - viewModeRowH
  end

  uiRects.expandToggle.x1, uiRects.expandToggle.y1, uiRects.expandToggle.x2, uiRects.expandToggle.y2 = 0, 0, 0, 0
  uiRects.swapToggle.x1, uiRects.swapToggle.y1, uiRects.swapToggle.x2, uiRects.swapToggle.y2 = 0, 0, 0, 0

  if leaderboardState.scrollActive then
    rowY = rowY + leaderboardState.scrollOffset
    gl.Scissor(true)
    gl.Scissor(x, y - drawHeight + padding, totalWidth, viewportHeight)
  end

  for _, item in ipairs(layoutItems) do
    if item.itype == "pindivider" then
      local lineY = rowY - pinDividerRowH / 2
      gl.Color(1, 0.8, 0.2, 0.7)
      gl.Rect(x, lineY - 1, x + totalWidth, lineY + 1)
      rowY = rowY - pinDividerRowH

    elseif item.itype == "divider" then
      gl.Color(1,1,1,0.5)
      local lineY = rowY - dividerRowH / 2
      gl.Rect(x, lineY - 1, x + totalWidth, lineY + 1)
      rowY = rowY - dividerRowH

    elseif item.itype == "maintoggle" then
      local slotTop = rowY
      local slotBottom = rowY - dividerRowH
      local lineY1 = slotTop - dividerRowH * 0.22
      local lineY2 = slotBottom + dividerRowH * 0.22
      local midY = (slotTop + slotBottom) / 2

      gl.Color(1,1,1,0.5)
      gl.Rect(x, lineY1 - 1, x + totalWidth, lineY1 + 1)
      gl.Rect(x, lineY2 - 1, x + totalWidth, lineY2 + 1)

      local label = sectionsExpanded and "Collapse" or "Expand"
      local labelFontSize = 14
      local labelTW = gl.GetTextWidth(label) * labelFontSize
      local iconGap = 8
      local iconW = 14
      local iconTriW = 12
      local iconTriH = 7
      local iconTriGap = 3

      local centerX = (x + x + totalWidth) / 2
      local contentW = labelTW + iconGap + iconW
      local labelX1 = centerX - contentW / 2
      local iconCenterX = labelX1 + labelTW + iconGap + iconW / 2

      gl.Color(1,1,1,0.9)
      gl.Text(label, labelX1, midY - 5, labelFontSize, "o")

      -- swap icon: warm (red) triangle pointing up, cool (blue) triangle
      -- pointing down -- click to flip which section is on top
      local topBaseY = midY + iconTriGap / 2
      local topApexY = topBaseY + iconTriH
      gl.Color(1, 0.35, 0.35, 0.95)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(iconCenterX - iconTriW/2, topBaseY)
        gl.Vertex(iconCenterX + iconTriW/2, topBaseY)
        gl.Vertex(iconCenterX, topApexY)
      end)

      local botBaseY = midY - iconTriGap / 2
      local botApexY = botBaseY - iconTriH
      gl.Color(0.4, 0.65, 1, 0.95)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(iconCenterX - iconTriW/2, botBaseY)
        gl.Vertex(iconCenterX + iconTriW/2, botBaseY)
        gl.Vertex(iconCenterX, botApexY)
      end)

      local iconPad = 16
      uiRects.swapToggle.x1, uiRects.swapToggle.y1, uiRects.swapToggle.x2, uiRects.swapToggle.y2 =
        iconCenterX - iconTriW/2 - iconPad, botApexY - iconPad,
        iconCenterX + iconTriW/2 + iconPad, topApexY + iconPad

      uiRects.expandToggle.x1, uiRects.expandToggle.y1, uiRects.expandToggle.x2, uiRects.expandToggle.y2 =
        x, slotBottom, x + totalWidth, slotTop

      gl.Color(1,1,1,1)
      rowY = rowY - dividerRowH

    else
    local teamID = item.teamID
    local name   = item.displayName

    rowRects[teamID] = {
      x1 = x,
      y1 = rowY - rowH,
      x2 = x + totalWidth,
      y2 = rowY,
    }

    local isHover    = (teamID == hoverState.teamID)
    local isSelected = (teamID == selectedTeamID)

    if isSelected then
      gl.Color(0.3,0.6,1.0,0.25)
      gl.Rect(x, rowY-rowH, x+totalWidth, rowY)
    elseif isHover then
      gl.Color(1,1,1,0.15)
      gl.Rect(x, rowY-rowH, x+totalWidth, rowY)
    end

    gl.Color(item.colorR, item.colorG, item.colorB, 1)

    local nameY = rowY - (rowH * 0.5) + (nameFontSize * 0.25)
    gl.Text(name, x + padding, nameY, nameFontSize, "o")

    local subFontSize = 12
    gl.Color(0.8, 0.8, 0.8, 0.6)
    gl.Text("Base Center", x + padding, nameY - subFontSize * 1.6, subFontSize, "o")

    do
      local badgeFontSize = 14
      local badgeY = rowY - 16
      local badgeRightEdge = x + padding + nameColW - 4
      gl.Color(1, 0.85, 0.2, 1)

      if teamID == cachedTopTeamID then
        local label = "🏆"
        local w = gl.GetTextWidth(label) * badgeFontSize
        gl.Text(label, badgeRightEdge - w, badgeY, badgeFontSize, "o")
        badgeRightEdge = badgeRightEdge - w - 6
      end

      if isPinned(teamID) then
        local label = "📌"
        local w = gl.GetTextWidth(label) * badgeFontSize
        gl.Text(label, badgeRightEdge - w, badgeY, badgeFontSize, "o")
      end
    end

    local colIndex = 0
    for _, iconData in ipairs(item.icons) do
      local defName = iconData.defName
      local labName = iconData.labName
      local ud = UnitDefNames[defName]
      if ud then
        gl.Color(1,1,1,1)

        local ix = x + padding + nameColW + iconSize * colIndex
        local iy = rowY - (rowH - iconSize)/2 - iconSize

        gl.Texture("#"..ud.id)
        gl.TexRect(ix, iy, ix+iconSize, iy+iconSize)
        gl.Texture(false)

        if iconData.overlayDefNames then
          local miniSize = iconSize * 0.4
          local miniGap = 2
          for i, odn in ipairs(iconData.overlayDefNames) do
            local oud = UnitDefNames[odn]
            if oud then
              local mx1 = ix
              local mx2 = ix + miniSize
              local my2 = iy + iconSize - (i - 1) * (miniSize + miniGap)
              local my1 = my2 - miniSize

              gl.Color(0,0,0,0.9)
              gl.Rect(mx1 - 1, my1 - 1, mx2 + 1, my2 + 1)

              gl.Color(1,1,1,1)
              gl.Texture("#"..oud.id)
              gl.TexRect(mx1, my1, mx2, my2)
              gl.Texture(false)
            end
          end
        end

        local isFollowedCommander = false
        if labName == "Commander" and followState.unitID
           and teamLabPositions[teamID] and teamLabPositions[teamID]["Commander"] then
          for _, comEntry in ipairs(teamLabPositions[teamID]["Commander"]) do
            if comEntry.unitID == followState.unitID then
              isFollowedCommander = true
              break
            end
          end
        end
        if isFollowedCommander then
          gl.Color(0.3,1,0.3,0.9)
          local bw = 2
          gl.Rect(ix, iy, ix+iconSize, iy+bw)
          gl.Rect(ix, iy+iconSize-bw, ix+iconSize, iy+iconSize)
          gl.Rect(ix, iy, ix+bw, iy+iconSize)
          gl.Rect(ix+iconSize-bw, iy, ix+iconSize, iy+iconSize)
        end

        gl.Color(1,0.2,0.2,1)
        gl.Text(
          tostring(iconData.count),
          ix + iconSize - 2,
          iy + iconSize - 18,
          24,
          "ro"
        )

        local tierLabel = iconData.tierLabel
        if tierLabel then
          local tierSize = badgeFontSizeBySize[iconSize] or (iconSize * 0.225)
          local padX, padY = 3.6, 2.4
          local tw = gl.GetTextWidth(tierLabel) * tierSize
          local th = tierSize * 1.1

          local bx1, by1 = ix, iy
          local bx2, by2 = ix + tw + padX * 2, iy + th + padY * 2

          gl.Color(0,0,0,0.55)
          gl.Rect(bx1, by1, bx2, by2)

          gl.Color(1,1,1,1)
          gl.Text(
            tierLabel,
            bx1 + padX,
            by1 + padY,
            tierSize,
            ""
          )
        end

        iconRects[#iconRects+1] = {
          x1=ix, y1=iy, x2=ix+iconSize, y2=iy+iconSize,
          defName=defName,
          teamID=teamID,
          labName=labName,
        }

        colIndex = colIndex + 1
      end
    end

    rowY = rowY - rowH
    end
  end

  if leaderboardState.scrollActive then
    gl.Scissor(false)

    local glowAlpha = 1

    local arrowW = 32.2
    local arrowH = 18.4
    local arrowCx = x + totalWidth / 2
    local shadowOffset = 2

    if leaderboardState.scrollOffset > 0 then
      -- Not showing the true #1 -- more content above, scroll up to see it
      local topY = y - fixedHeaderHeight - 3

      gl.Color(0, 0, 0, glowAlpha * 0.6)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(arrowCx - arrowW/2 + shadowOffset, topY - arrowH - shadowOffset)
        gl.Vertex(arrowCx + arrowW/2 + shadowOffset, topY - arrowH - shadowOffset)
        gl.Vertex(arrowCx + shadowOffset, topY - shadowOffset)
      end)

      gl.Color(1, 1, 1, glowAlpha)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(arrowCx - arrowW/2, topY - arrowH)
        gl.Vertex(arrowCx + arrowW/2, topY - arrowH)
        gl.Vertex(arrowCx, topY)
      end)
    end

    if leaderboardState.scrollOffset < leaderboardState.scrollMaxOffset then
      -- More content below -- scroll down to see it
      local botY = y - drawHeight + padding + 3

      gl.Color(0, 0, 0, glowAlpha * 0.6)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(arrowCx - arrowW/2 + shadowOffset, botY + arrowH - shadowOffset)
        gl.Vertex(arrowCx + arrowW/2 + shadowOffset, botY + arrowH - shadowOffset)
        gl.Vertex(arrowCx + shadowOffset, botY - shadowOffset)
      end)

      gl.Color(1, 1, 1, glowAlpha)
      gl.BeginEnd(GL.TRIANGLES, function()
        gl.Vertex(arrowCx - arrowW/2, botY + arrowH)
        gl.Vertex(arrowCx + arrowW/2, botY + arrowH)
        gl.Vertex(arrowCx, botY)
      end)
    end
  end

  gl.Color(1,1,1,1)

  if hoverState.icon then
    local labName = hoverState.icon.labName
    local prefix  = hoverState.icon.defName:sub(1,3)
    local factionName = factionFullNames[prefix]

    if labName and factionName then
      local tooltipText = factionName .. " " .. labName
      local tooltipFontSize = 14
      local padX, padY = 6, 4
      local tw = gl.GetTextWidth(tooltipText) * tooltipFontSize
      local th = tooltipFontSize * 1.2

      local tx = mouseX + 16
      local ty = mouseY - (th + padY * 2) - 10

      gl.Color(0,0,0,0.85)
      gl.Rect(tx, ty, tx + tw + padX * 2, ty + th + padY * 2)

      gl.Color(1,1,1,1)
      gl.Text(tooltipText, tx + padX, ty + padY, tooltipFontSize, "")
    end
  end

  if sizeMenu.open then
    local szFontSize = 12
    local optW = 44
    local optH = 25
    local optGap = 6
    local totalMenuW = (optW + optGap) * #sizeMenu.options - optGap
    local menuCenterX = x + totalWidth / 2
    local menuX1 = menuCenterX - totalMenuW / 2
    local menuX2 = menuX1 + totalMenuW
    local menuY2 = sizeMenu.toggleRect.y1 - 4
    local menuY1 = menuY2 - optH

    sizeMenu.optionRects = {}
    for i, sizeVal in ipairs(sizeMenu.options) do
      local ox1 = menuX1 + (i - 1) * (optW + optGap)
      local ox2 = ox1 + optW
      sizeMenu.optionRects[i] = {x1 = ox1, y1 = menuY1, x2 = ox2, y2 = menuY2, size = sizeVal}

      if sizeVal == iconSize then
        gl.Color(1, 0.85, 0.2, 1)
        gl.Rect(ox1, menuY1, ox2, menuY2)
        gl.Color(0, 0, 0, 1)
      else
        gl.Color(0.32, 0.36, 0.42, 1)
        gl.Rect(ox1, menuY1, ox2, menuY2)
        gl.Color(1, 1, 1, 0.95)
      end

      gl.Color(0.7, 0.75, 0.85, 1)
      gl.LineWidth(1.5)
      gl.BeginEnd(GL.LINE_LOOP, function()
        gl.Vertex(ox1, menuY1); gl.Vertex(ox2, menuY1)
        gl.Vertex(ox2, menuY2); gl.Vertex(ox1, menuY2)
      end)
      gl.LineWidth(1)

      if sizeVal == iconSize then
        gl.Color(0, 0, 0, 1)
      else
        gl.Color(1, 1, 1, 0.95)
      end
      gl.Text(tostring(sizeVal), (ox1 + ox2) / 2, (menuY1 + menuY2) / 2 - szFontSize * 0.3, szFontSize, "oc")
    end
  end

  gl.Color(1,1,1,1)
end

-- end of widget
