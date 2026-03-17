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
Flags     = require("lib/flags")

respond("[drinfomon] DragonRealms modules loaded")
