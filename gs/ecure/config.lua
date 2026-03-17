local M = {}

M.BODY_PARTS = {
    "head", "neck", "abdomen", "back", "chest", "righteye", "lefteye",
    "rightleg", "leftleg", "rightarm", "leftarm", "righthand", "lefthand", "nerves",
}

M.MODES = { "heal", "hunt" }

M.DEFAULT_LEVEL = 0

-- Mana cost per body part for base CURE
M.BODY_PART_COSTS = {
    head = 4, nerves = 3, neck = 4,
    chest = 5, abdomen = 5, back = 5,
    rightarm = 2, leftarm = 2,
    rightleg = 2, leftleg = 2,
    righthand = 2, lefthand = 2,
    righteye = 5, lefteye = 5,
}

-- Maps ecure body part names to Wounds/Scars table keys
M.WOUND_KEY_MAP = {
    head = "head", nerves = "nsys", neck = "neck",
    chest = "chest", abdomen = "abdomen", back = "back",
    rightarm = "right_arm", leftarm = "left_arm",
    rightleg = "right_leg", leftleg = "left_leg",
    righthand = "right_hand", lefthand = "left_hand",
    righteye = "right_eye", lefteye = "left_eye",
}

M.CRITICAL_PARTS = { "head", "nerves" }

function M.format_for_command(part)
    return part:gsub("(right)(.*)", "%1 %2"):gsub("(left)(.*)", "%1 %2")
end

function M.cost_for(part)
    return M.BODY_PART_COSTS[part] or 2
end

function M.wound_key(part)
    return M.WOUND_KEY_MAP[part] or part
end

-- Settings persistence
function M.load()
    local raw = CharSettings["ecure"]
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    local settings = {
        mode = "heal",
        done_verb = "",
        use_signs = false,
        use_trolls_blood = false,
        alternative_behavior = false,
        head_nerve_priority = true,
        all_wounds_level = 0,
        all_scars_level = 0,
        debug = false,
    }
    -- Initialize per-part defaults
    for _, part in ipairs(M.BODY_PARTS) do
        for _, mode in ipairs(M.MODES) do
            settings[part .. "_wounds_" .. mode] = M.DEFAULT_LEVEL
            settings[part .. "_scars_" .. mode] = M.DEFAULT_LEVEL
        end
    end
    return settings
end

function M.save(settings)
    CharSettings["ecure"] = Json.encode(settings)
end

function M.wound_level(settings, part, mode)
    mode = mode or settings.mode or "heal"
    local key = part .. "_wounds_" .. mode
    local per_part = settings[key] or M.DEFAULT_LEVEL
    local global = settings.all_wounds_level or M.DEFAULT_LEVEL
    return math.min(per_part, global)
end

function M.scar_level(settings, part, mode)
    mode = mode or settings.mode or "heal"
    local key = part .. "_scars_" .. mode
    local per_part = settings[key] or M.DEFAULT_LEVEL
    local global = settings.all_scars_level or M.DEFAULT_LEVEL
    return math.min(per_part, global)
end

return M
