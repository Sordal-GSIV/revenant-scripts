-- lib/gs/currency.lua
-- GemStone IV currency tracking via Infomon
--
-- Sources (from Lich5 infomon/parser.rb):
--   silver:                  "info" command → "Mana: X Silver: Y"
--   silver_container:        "wealth" command → "carrying X silver stored within"
--   redsteel_marks:          "Redsteel Marks: X" or "carrying X redsteel marks"
--   gigas_artifact_fragments: "carrying X gigas artifact fragments"
--   gemstone_dust:           "carrying X Dust in your reserves"
--   tickets:                 "tickets" command → "General - X tickets"
--   blackscrip:              "tickets" command → "Troubled Waters - X blackscrip"
--   bloodscrip:              "tickets" command → "Duskruin Arena - X bloodscrip"
--   ethereal_scrip:          "tickets" command → "Reim - X ethereal scrip"
--   soul_shards:             "tickets" command → "Ebon Gate - X soul shards"
--   raikhen:                 "tickets" command → "Rumor Woods - X raikhen"
--   gold:                    "tickets" command → "Gold - X gold"
--   elans:                   NOT PARSED (even in Lich5)

local M = {}

local CURRENCIES = {
    "silver", "silver_container",
    "redsteel_marks", "tickets", "blackscrip", "bloodscrip",
    "ethereal_scrip", "raikhen", "elans", "soul_shards",
    "gold", "gigas_artifact_fragments", "gemstone_dust",
}

local CURRENCY_SET = {}
for _, c in ipairs(CURRENCIES) do CURRENCY_SET[c] = true end

setmetatable(M, {
    __index = function(_, key)
        if CURRENCY_SET[key] then
            local val = Infomon.get("currency." .. key)
            return val and tonumber(val) or 0
        end
        return rawget(M, key)
    end,
})

function M.all()
    local result = {}
    for _, c in ipairs(CURRENCIES) do
        local val = Infomon.get("currency." .. c)
        result[c] = val and tonumber(val) or 0
    end
    return result
end

return M
