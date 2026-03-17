local M = {}

-- Body area → wound API fields mapping
local AREAS = {
    head   = { wounds = {"head", "neck"},   scars = {"head", "neck"} },
    organ  = { wounds = {"torso"},          scars = {"torso"} },
    limb   = { wounds = {"rightArm", "leftArm", "rightHand", "leftHand",
                         "rightLeg", "leftLeg", "rightFoot", "leftFoot"},
               scars  = {"rightArm", "leftArm", "rightHand", "leftHand",
                         "rightLeg", "leftLeg", "rightFoot", "leftFoot"} },
    nerve  = { wounds = {"nsys"},           scars = {"nsys"} },
}

local AREA_ORDER = { "head", "organ", "limb", "nerve" }

local function max_severity(category, parts)
    local max = 0
    for _, part in ipairs(parts) do
        local val = category[part]
        if val and val > max then max = val end
    end
    return max
end

function M.next_herb_type(state)
    local skipped = state.skipped or {}

    -- 1. Blood — if health < 50%
    if not skipped["blood"] and Char.percent_health and Char.percent_health < 50 then
        return "blood"
    end

    -- 2. Poison
    if not skipped["poison"] and poisoned and poisoned() then
        return "poison"
    end

    -- 3. Disease
    if not skipped["disease"] and diseased and diseased() then
        return "disease"
    end

    -- 4. Major wounds (severity > 1)
    for _, area in ipairs(AREA_ORDER) do
        local sev = max_severity(Wounds, AREAS[area].wounds)
        if sev > 1 and not skipped["major " .. area .. " wound"] then
            return "major " .. area .. " wound"
        end
    end

    -- 5. Minor wounds (severity == 1)
    for _, area in ipairs(AREA_ORDER) do
        local sev = max_severity(Wounds, AREAS[area].wounds)
        if sev == 1 and not skipped["minor " .. area .. " wound"] then
            return "minor " .. area .. " wound"
        end
    end

    -- 6. Severed limb
    if not skipped["severed limb"] then
        local limb_scar = max_severity(Scars, AREAS.limb.scars)
        if limb_scar >= 3 then
            return "severed limb"
        end
    end

    -- 7. Missing eye
    if not skipped["missing eye"] then
        if (Scars.rightEye and Scars.rightEye >= 3) or
           (Scars.leftEye and Scars.leftEye >= 3) then
            return "missing eye"
        end
    end

    -- 8. Major scars (severity > 1)
    for _, area in ipairs(AREA_ORDER) do
        local sev = max_severity(Scars, AREAS[area].scars)
        if sev > 1 and not skipped["major " .. area .. " scar"] then
            return "major " .. area .. " scar"
        end
    end

    -- 9. Minor scars (severity == 1) — skippable
    if not state.skip_scars then
        for _, area in ipairs(AREA_ORDER) do
            local sev = max_severity(Scars, AREAS[area].scars)
            if sev == 1 and not skipped["minor " .. area .. " scar"] then
                return "minor " .. area .. " scar"
            end
        end
    end

    -- 10. Blood if still needed
    if not skipped["blood"] and Char.percent_health and Char.percent_health < 100 then
        return "blood"
    end

    return nil  -- fully healed
end

function M.get_wound_summary()
    local summary = {}
    for _, area in ipairs(AREA_ORDER) do
        local wsev = max_severity(Wounds, AREAS[area].wounds)
        local ssev = max_severity(Scars, AREAS[area].scars)
        if wsev > 0 or ssev > 0 then
            summary[#summary + 1] = {
                area = area,
                wound_severity = wsev,
                scar_severity = ssev,
            }
        end
    end
    return summary
end

return M
