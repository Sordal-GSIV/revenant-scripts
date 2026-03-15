-- Society membership/rank parser
-- Populates Society.membership and Society.rank from SOCIETY verb output

Society.membership = nil
Society.rank = nil

hook.add("downstream", "society_parser", function(text)
    -- Voln: "You are a Master in the Order of Voln."
    local voln_rank = text:match("You are an? (.+) in the Order of Voln")
    if voln_rank then
        Society.membership = "Voln"
        Society.rank = voln_rank
        return text
    end

    -- CoL: "You are a member of the Council of Light. Your rank is 26."
    local col_rank = text:match("Council of Light.-Your rank is (%d+)")
    if col_rank then
        Society.membership = "Council of Light"
        Society.rank = tonumber(col_rank)
        return text
    end

    -- Sunfist: "You are a Master in the Guardians of Sunfist."
    local sf_rank = text:match("You are an? (.+) in the Guardians of Sunfist")
    if sf_rank then
        Society.membership = "Sunfist"
        Society.rank = sf_rank
        return text
    end

    return text
end)
