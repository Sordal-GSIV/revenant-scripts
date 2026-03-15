local M = {}

-- Each entry: { name, type, short, drinkable, locations }
M.database = {
    -- Blood
    { name = "acantha leaf", type = "blood", short = "acantha", drinkable = false },
    { name = "red-heart potion", type = "blood", short = "red-heart", drinkable = true },

    -- Head wounds
    { name = "aloeas stem", type = "major head wound", short = "aloeas", drinkable = false },
    { name = "rose-marrow potion", type = "minor head wound", short = "rose-marrow", drinkable = true },

    -- Head scars
    { name = "haphip root", type = "major head scar", short = "haphip", drinkable = false },
    { name = "brostheras potion", type = "minor head scar", short = "brostheras", drinkable = true },

    -- Nerve wounds
    { name = "wolifrew lichen", type = "major nerve wound", short = "wolifrew", drinkable = false },
    { name = "bolmara potion", type = "minor nerve wound", short = "bolmara", drinkable = true },

    -- Nerve scars
    { name = "torban leaf", type = "major nerve scar", short = "torban", drinkable = false },
    { name = "woth flower", type = "minor nerve scar", short = "woth", drinkable = false },

    -- Organ wounds
    { name = "basal moss", type = "major organ wound", short = "basal", drinkable = false },
    { name = "pothinir grass", type = "minor organ wound", short = "pothinir", drinkable = false },

    -- Organ scars
    { name = "talneo potion", type = "major organ scar", short = "talneo", drinkable = true },
    { name = "wingstem potion", type = "minor organ scar", short = "wingstem", drinkable = true },

    -- Limb wounds
    { name = "ambrominas leaf", type = "major limb wound", short = "ambrominas", drinkable = false },
    { name = "ephlox moss", type = "minor limb wound", short = "ephlox", drinkable = false },

    -- Limb scars
    { name = "cactacae spine", type = "major limb scar", short = "cactacae", drinkable = false },
    { name = "calamia fruit", type = "minor limb scar", short = "calamia", drinkable = false },

    -- Severed limb
    { name = "sovyn clove", type = "severed limb", short = "sovyn", drinkable = false },

    -- Missing eye
    { name = "bur-clover potion", type = "missing eye", short = "bur-clover", drinkable = true },

    -- Poison
    { name = "ochre fungus", type = "poison", short = "ochre", drinkable = false },

    -- Disease
    { name = "sky-blue potion", type = "disease", short = "sky-blue", drinkable = true },
}

function M.find_by_type(wound_type, opts)
    opts = opts or {}
    for _, herb in ipairs(M.database) do
        if herb.type == wound_type then
            if opts.prefer_drinkable and herb.drinkable then return herb end
            if opts.prefer_edible and not herb.drinkable then return herb end
            if not opts.prefer_drinkable and not opts.prefer_edible then return herb end
        end
    end
    -- Fallback: any herb of the type
    for _, herb in ipairs(M.database) do
        if herb.type == wound_type then return herb end
    end
    return nil
end

function M.is_drinkable(noun)
    local n = noun:lower()
    return n:find("potion") or n:find("tincture") or n:find("elixir")
        or n:find("tea") or n:find("ale") or n:find("soup")
        or n:find("brew") or n:find("porter") or n:find("flagon")
end

function M.list_types()
    return {
        "blood", "poison", "disease",
        "major head wound", "minor head wound",
        "major head scar", "minor head scar",
        "major nerve wound", "minor nerve wound",
        "major nerve scar", "minor nerve scar",
        "major organ wound", "minor organ wound",
        "major organ scar", "minor organ scar",
        "major limb wound", "minor limb wound",
        "major limb scar", "minor limb scar",
        "severed limb", "missing eye",
    }
end

return M
