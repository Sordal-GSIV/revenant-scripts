--- @revenant-module
--- name: dr/init
--- description: DR module loader — loaded conditionally when game is DragonRealms

local parser  = require("lib/dr/parser")
local banking = require("lib/dr/banking")

-- Register the main parser hook
DownstreamHook.add("drinfomon", function(line)
    parser.process(line)
    return line
end)

-- Load persisted banking data
banking.load()

-- Export DR modules as globals for script access
DRSkill   = require("lib/dr/skills")
DRStats   = require("lib/dr/stats")
DRSpells  = require("lib/dr/spells")
DRBanking = require("lib/dr/banking")
DRRoom    = require("lib/dr/room")
DRExpMon  = require("lib/dr/expmonitor")

-- DR Common utility modules (ported from Lich5 dr-scripts commons)
DRC    = require("lib/dr/common")            -- Base utilities (bput, retreat, etc.)
DRCT   = require("lib/dr/common_travel")     -- Travel / navigation
DRCM   = require("lib/dr/common_money")      -- Currency / banking helpers
DRCI   = require("lib/dr/common_items")      -- Item manipulation
DRCH   = require("lib/dr/common_healing")    -- Health / wound management
DRCC   = require("lib/dr/common_crafting")   -- Crafting utilities
DRCA   = require("lib/dr/common_arcana")     -- Magic / spell casting
DRCMM  = require("lib/dr/common_moonmage")  -- Moon Mage specifics
DRCTH  = require("lib/dr/common_theurgy")   -- Theurgy / cleric rituals
DRCS   = require("lib/dr/common_summoning") -- Summoned weapons
DRCEV  = require("lib/dr/common_validation") -- Input / character validation
DREMgr = require("lib/dr/equip_manager")    -- Equipment set management

respond("[drinfomon] DragonRealms modules loaded")
