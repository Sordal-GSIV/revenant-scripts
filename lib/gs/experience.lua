local M = {}
setmetatable(M, {
    __index = function(_, key)
        local map = {
            fame = "experience.fame",
            field_exp = "experience.field_experience",
            max_field_exp = "experience.max_field_experience",
            total = "experience.total_experience",
            deeds = "experience.deeds",
            deaths_sting = "experience.deaths_sting",
            long_term = "experience.long_term_experience",
            ascension = "experience.ascension_experience",
        }
        if map[key] then
            if key == "deaths_sting" then
                return Infomon.get(map[key]) or "None"
            end
            return Infomon.get_i(map[key])
        end
        return rawget(M, key)
    end
})
return M
