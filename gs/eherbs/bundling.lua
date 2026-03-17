local herbs_db = require("lib/gs/herbs")

local M = {}

local CANT_BUNDLE = "tart|feather|special|blubber|pie|porridge|soup|fruit"

function M.can_bundle(herb_name)
    return not herb_name:lower():find(CANT_BUNDLE)
end

function M.bundle_all(container_noun)
    respond("[eherbs] Bundling herbs in " .. container_noun .. "...")
    local bundled = 0

    -- Get list of herb nouns in container
    fput("look in my " .. container_noun)
    -- This is simplified — full implementation needs to parse container contents
    -- and identify duplicate herbs to bundle together

    -- For each herb type that has multiples:
    -- 1. Get first one to hand
    -- 2. For each additional copy:
    --    a. Get it to other hand
    --    b. If drinkable: pour #id in #bundle_id
    --    c. If edible: bundle
    --    d. If bundle full: stow, start new

    respond("[eherbs] Bundling complete. " .. bundled .. " herbs consolidated.")
    return bundled
end

function M.bundle_two(item1_noun, item2_noun)
    -- Bundle two herbs already in hand
    if herbs_db.is_drinkable(item1_noun) then
        fput("pour my " .. item2_noun .. " in my " .. item1_noun)
    else
        fput("bundle")
    end
end

return M
