local M = {}
local ALIASES = {
    minorspiritual = "minor_spiritual", majorspiritual = "major_spiritual",
    minorelemental = "minor_elemental", majorelemental = "major_elemental",
    minormental = "minor_mental", majormental = "major_mental",
    wizard = "wizard", sorcerer = "sorcerer", ranger = "ranger",
    paladin = "paladin", empath = "empath", cleric = "cleric",
    bard = "bard", savant = "savant",
    minor_spiritual = "minor_spiritual", major_spiritual = "major_spiritual",
    minor_elemental = "minor_elemental", major_elemental = "major_elemental",
    minor_mental = "minor_mental", major_mental = "major_mental",
}
setmetatable(M, {
    __index = function(_, key)
        local normalized = ALIASES[key:lower():gsub("[%s%-_]", "")]
        if normalized then
            return Infomon.get_i("spell." .. normalized)
        end
        return nil
    end
})
return M
