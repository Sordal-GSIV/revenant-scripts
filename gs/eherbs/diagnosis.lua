local M = {}

-- Maps the Lich5 Wounds/Scars area names to eherbs herb area names
-- Lich5 areas: head, neck, chest (torso), abdomen, back, leftEye, rightEye,
--   leftArm, rightArm, leftHand, rightHand, leftLeg, rightLeg, leftFoot, rightFoot, nsys
-- eherbs areas: head, organ, limb, nerve
local AREA_MAP = {
    head = "head", neck = "head",
    chest = "organ", abdomen = "organ", back = "organ",
    leftEye = "organ", rightEye = "organ",
    leftArm = "limb", rightArm = "limb",
    leftHand = "limb", rightHand = "limb",
    leftLeg = "limb", rightLeg = "limb",
    leftFoot = "limb", rightFoot = "limb",
    nsys = "nerve",
}

-- The five wound scan areas (matching Lich5's Wounds.head, Wounds.torso, etc.)
-- We aggregate per-part max severity into these groups.
local WOUND_GROUPS = {
    { area = "head",   parts = {"head", "neck"} },
    { area = "organ",  parts = {"chest", "abdomen", "back"} },
    { area = "limb",   parts = {"leftArm", "rightArm", "leftHand", "rightHand", "leftLeg", "rightLeg", "leftFoot", "rightFoot"} },
    { area = "nerve",  parts = {"nsys"} },
}

local function max_severity(source, parts)
    local mx = 0
    for _, p in ipairs(parts) do
        local v = source[p]
        if v and v > mx then mx = v end
    end
    return mx
end

local function includes_severity(source, parts, sev)
    for _, p in ipairs(parts) do
        if (source[p] or 0) == sev then return true end
    end
    return false
end

-- Body parts that affect spellcasting ability
local SPELLCAST_PARTS = {
    wound = {"head", "nsys", "leftArm", "leftHand", "rightArm", "rightHand", "leftEye", "rightEye"},
    scar  = {"head", "nsys", "leftArm", "leftHand", "rightArm", "rightHand", "leftEye", "rightEye"},
}

-- Body parts that affect ranged combat
local RANGED_PARTS = {
    wound = {"leftArm", "leftHand", "rightArm", "rightHand", "head", "nsys"},
    scar  = {"leftArm", "leftHand", "rightArm", "rightHand", "head", "nsys"},
}

--- Determine if spellcasting is currently impaired by wounds
function M.able_to_cast()
    -- Check nsys/head: level 2+ blocks casting
    if (Wounds.nsys or 0) > 1 or (Scars.nsys or 0) > 1 then return false end
    if (Wounds.head or 0) > 1 or (Scars.head or 0) > 1 then return false end

    -- Check arm/hand: stacked wounds on one side > 1 blocks casting
    local left_wound  = (Wounds.leftArm or 0) + (Wounds.leftHand or 0)
    local left_scar   = (Scars.leftArm or 0) + (Scars.leftHand or 0)
    local right_wound = (Wounds.rightArm or 0) + (Wounds.rightHand or 0)
    local right_scar  = (Scars.rightArm or 0) + (Scars.rightHand or 0)

    if left_wound > 1 or left_scar > 1 then return false end
    if right_wound > 1 or right_scar > 1 then return false end

    -- Check eye wounds level 3+
    if (Wounds.leftEye or 0) > 2 or (Wounds.rightEye or 0) > 2 then return false end
    if (Scars.leftEye or 0) > 2 or (Scars.rightEye or 0) > 2 then return false end

    return true
end

--- Determine next herb type needed, respecting spellcast_only / ranged_only flags
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

    local spellcast_only = state.spellcast_only
    local ranged_only = state.ranged_only

    if spellcast_only or ranged_only then
        return M._next_herb_type_filtered(state, skipped, spellcast_only, ranged_only)
    end

    -- 4. Major wounds (severity > 1)
    for _, g in ipairs(WOUND_GROUPS) do
        local sev = max_severity(Wounds, g.parts)
        if sev > 1 and not skipped["major " .. g.area .. " wound"] then
            return "major " .. g.area .. " wound"
        end
    end

    -- 5. Minor wounds (severity == 1)
    for _, g in ipairs(WOUND_GROUPS) do
        if includes_severity(Wounds, g.parts, 1) and not skipped["minor " .. g.area .. " wound"] then
            return "minor " .. g.area .. " wound"
        end
    end

    -- 6. Severed limb
    if not skipped["severed limb"] then
        local limb_parts = {"leftArm", "rightArm", "leftHand", "rightHand", "leftLeg", "rightLeg", "leftFoot", "rightFoot"}
        if max_severity(Scars, limb_parts) >= 3 then
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
    for _, g in ipairs(WOUND_GROUPS) do
        local sev = max_severity(Scars, g.parts)
        if sev > 1 and not skipped["major " .. g.area .. " scar"] then
            return "major " .. g.area .. " scar"
        end
    end

    -- 9. Minor scars (severity == 1) — skippable
    if not state.skip_scars then
        for _, g in ipairs(WOUND_GROUPS) do
            if includes_severity(Scars, g.parts, 1) and not skipped["minor " .. g.area .. " scar"] then
                return "minor " .. g.area .. " scar"
            end
        end
    end

    -- 10. Blood if still needed (health not full, within 7 HP threshold from original)
    if not skipped["blood"] and Char.health and Char.max_health and (Char.health + 7) < Char.max_health then
        return "blood"
    end

    return nil  -- fully healed
end

--- Spellcast-only and ranged-only wound scanning
function M._next_herb_type_filtered(state, skipped, spellcast_only, ranged_only)
    -- For spellcast/ranged: only heal wounds that affect those abilities
    -- Order: limbs, head, nerves, torso (eyes)
    local check_areas = {}
    if spellcast_only then
        check_areas = {
            { area = "limb",  parts = {"leftArm", "leftHand", "rightArm", "rightHand"} },
            { area = "head",  parts = {"head"} },
            { area = "nerve", parts = {"nsys"} },
            { area = "organ", parts = {"leftEye", "rightEye"} },
        }
    elseif ranged_only then
        check_areas = {
            { area = "limb",  parts = {"leftArm", "leftHand", "rightArm", "rightHand"} },
            { area = "head",  parts = {"head"} },
            { area = "nerve", parts = {"nsys"} },
        }
    end

    -- Major wounds first
    for _, g in ipairs(check_areas) do
        if max_severity(Wounds, g.parts) > 1 and not skipped["major " .. g.area .. " wound"] then
            return "major " .. g.area .. " wound"
        end
    end

    -- Minor wounds
    for _, g in ipairs(check_areas) do
        if includes_severity(Wounds, g.parts, 1) and not skipped["minor " .. g.area .. " wound"] then
            return "minor " .. g.area .. " wound"
        end
    end

    -- Severed limb (affects both spellcast and ranged)
    if not skipped["severed limb"] then
        local arm_parts = {"rightHand", "rightArm", "leftHand", "leftArm"}
        if max_severity(Scars, arm_parts) >= 3 then
            return "severed limb"
        end
    end

    -- Missing eye (spellcast only)
    if spellcast_only and not skipped["missing eye"] then
        if max_severity(Scars, {"rightEye", "leftEye"}) >= 3 then
            return "missing eye"
        end
    end

    -- Major scars
    for _, g in ipairs(check_areas) do
        if max_severity(Scars, g.parts) > 1 and not skipped["major " .. g.area .. " scar"] then
            return "major " .. g.area .. " scar"
        end
    end

    return nil
end

--- Get wound summary for display
function M.get_wound_summary()
    local summary = {}
    for _, g in ipairs(WOUND_GROUPS) do
        local wsev = max_severity(Wounds, g.parts)
        local ssev = max_severity(Scars, g.parts)
        if wsev > 0 or ssev > 0 then
            summary[#summary + 1] = {
                area = g.area,
                wound_severity = wsev,
                scar_severity = ssev,
            }
        end
    end
    -- Also check eyes separately
    local eye_wsev = math.max(Wounds.leftEye or 0, Wounds.rightEye or 0)
    local eye_ssev = math.max(Scars.leftEye or 0, Scars.rightEye or 0)
    if eye_wsev > 0 or eye_ssev > 0 then
        summary[#summary + 1] = {
            area = "eye",
            wound_severity = eye_wsev,
            scar_severity = eye_ssev,
        }
    end
    return summary
end

--- Parse APPRAISE output for dead character wounds
function M.appraise_character(lines, full_heal)
    local injuries = {}
    local text = table.concat(lines, " ")

    -- Bleeding / major injuries
    if text:find("minor lacerations about the head") or text:find("bleeding from the head")
       or text:find("moderate bleeding from h[ie][sr] neck") or text:find("severe head trauma and bleeding from the ears")
       or text:find("snapped bones and serious bleeding from the neck") then
        injuries[#injuries + 1] = "major head wound"
    end
    if text:find("deep lacerations") or text:find("deep gashes and serious bleeding") then
        injuries[#injuries + 1] = "major organ wound"
    end
    if text:find("a completely severed") or text:find("a fractured and bleeding") then
        injuries[#injuries + 1] = "major limb wound"
    end

    if not full_heal then return injuries end

    -- Non-bleeding wounds
    if text:find("a blinded") or text:find("a swollen") then
        injuries[#injuries + 1] = "major organ wound"
    end
    if text:find("a case of uncontrollable convulsions") or text:find("a case of sporadic convulsions") then
        injuries[#injuries + 1] = "major nerve wound"
    end
    if text:find("minor bruises about the head") or text:find("minor bruises on h[ie][sr] neck") then
        injuries[#injuries + 1] = "minor head wound"
    end
    if text:find("minor cuts and bruises on h[ie][sr] chest") or text:find("minor cuts and bruises on h[ie][sr] abdomen")
       or text:find("minor cuts and bruises on h[ie][sr] back") or text:find("a bruised") then
        injuries[#injuries + 1] = "minor organ wound"
    end
    if text:find("some minor cuts and bruises on h[ie][sr]") then
        injuries[#injuries + 1] = "minor limb wound"
    end
    if text:find("a strange case of muscle twitching") then
        injuries[#injuries + 1] = "minor nerve wound"
    end

    if #injuries > 0 then return injuries end

    -- Scars - Major
    if text:find("several facial scars") or text:find("old mutilation wounds about h[ie][sr] head")
       or text:find("some old neck wounds") or text:find("terrible scars from some serious neck injury") then
        injuries[#injuries + 1] = "major head scar"
    end
    if text:find("constant muscle spasms") or text:find("a very difficult time with muscle control") then
        injuries[#injuries + 1] = "major nerve scar"
    end
    if text:find("several painful%-looking scars across") or text:find("terrible, permanent mutilation of")
       or text:find("severe bruises and swelling around") then
        injuries[#injuries + 1] = "major organ scar"
    end
    if text:find("a missing .+ eye") then
        injuries[#injuries + 1] = "missing eye"
    end
    if text:find("a mangled") then
        injuries[#injuries + 1] = "major limb scar"
    end
    if text:find("a missing .+ leg") or text:find("a missing .+ arm") or text:find("a missing .+ hand") then
        injuries[#injuries + 1] = "severed limb"
    end

    -- Scars - Minor
    if text:find("a scar across h[ie][sr] face") or text:find("a scar across h[ie][sr] neck") then
        injuries[#injuries + 1] = "minor head scar"
    end
    if text:find("developed slurred speech") then
        injuries[#injuries + 1] = "minor nerve scar"
    end
    if text:find("an old battle scar across h[ie][sr]") or text:find("a black%-and%-blue") then
        injuries[#injuries + 1] = "minor organ scar"
    end
    if text:find("old battle scars on h[ie][sr]") then
        injuries[#injuries + 1] = "minor limb scar"
    end

    return injuries
end

return M
