--- @revenant-script
--- name: nurse
--- version: 0.01
--- author: Zadrix
--- game: dr
--- description: Empath self-healing script - heals wounds and scars by body part
--- tags: empath, healing, wounds, scars
---
--- Ported from nurse.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;nurse self   - Heal yourself immediately
---   ;nurse        - Wait for empathic link before healing

local mode = Script.vars[1] or ""

local body_parts = {
    "head", "neck", "chest", "abdomen", "back",
    "left hand", "left leg", "left arm",
    "right hand", "right leg", "right arm",
    "right eye", "left eye", "skin",
}

local wound_patterns = {
    "minor abrasions", "cuts and bruises", "tiny scratches",
    "black and blue", "slightly tender", "bruised",
    "minor swelling", "severely swollen",
    "minor twitching", "severe twitching",
    "difficulty controlling", "partial paralysis",
    "severe paralysis", "complete paralysis",
}

local scar_patterns = {
    "nearly invisible scars", "tiny scars", "minor scars",
    "severe scarring", "ugly gashes", "missing chunks",
    "mangled and malformed", "stump for",
    "chunks of flesh missing", "flesh stump",
    "non%-existent", "empty", "loss of skin tone",
    "skin discoloration", "shriveled", "bone exposed",
    "occasional twitch", "constant twitching",
    "internal scarring", "confused look", "blank stare",
    "paralyzed", "painful", "emaciated",
    "clouded", "blind", "numbness",
}

local function find_body_part(text)
    for _, part in ipairs(body_parts) do
        if text:find(part) then return part end
    end
    -- Edge cases
    if text:find("controlling actions") or text:find("twitching") or text:find("paralysis") or text:find("numbness") then
        return "skin"
    end
    if text:find("blank stare") then return "head" end
    if text:find("pallor") then return "abdomen" end
    return nil
end

local function parse_wounds()
    fput("heal")
    pause(1)

    local wounds = {}
    local scars = {}

    while true do
        local line = get()
        if not line then break end

        if line:find("no significant injuries") then
            return wounds, scars
        end

        if line:find("You have") then
            -- Check for wound patterns
            for _, wp in ipairs(wound_patterns) do
                if line:find(wp) then
                    local part = find_body_part(line)
                    if part then table.insert(wounds, part) end
                    break
                end
            end
            -- Check for scar patterns
            for _, sp in ipairs(scar_patterns) do
                if line:find(sp) then
                    local part = find_body_part(line)
                    if part then table.insert(scars, part) end
                    break
                end
            end
        end

        -- End of wound list
        if line:find("Your spirit") or line:find("Your body") or line:find("^$") then
            break
        end
    end

    return wounds, scars
end

local function heal_wounds(wounds)
    local internals = false
    local externals = false

    while #wounds > 0 do
        local part = wounds[1]

        fput("prep hw 10")
        waitfor("feel fully prepared")

        if externals and not internals then
            fput("cast " .. part .. " internal")
        elseif not externals and internals then
            fput("cast " .. part .. " external")
        else
            fput("cast " .. part)
        end
        pause(2)

        local result = get()
        if result then
            if result:find("appear completely healed") then
                if result:find("internal") then internals = true end
                if result:find("external") then externals = true end

                if (internals and externals) or result:find("cannot heal what is not injured") then
                    table.remove(wounds, 1)
                    internals = false
                    externals = false
                end
            elseif result:find("cannot heal") then
                table.remove(wounds, 1)
                internals = false
                externals = false
            end
        end
    end
end

local function heal_scars(scars)
    local internals = false
    local externals = false

    while #scars > 0 do
        local part = scars[1]

        fput("prep hs 15")
        waitfor("feel fully prepared")

        if externals and not internals then
            fput("cast " .. part .. " internal")
        elseif not externals and internals then
            fput("cast " .. part .. " external")
        else
            fput("cast " .. part)
        end
        pause(2)

        local result = get()
        if result then
            if result:find("appear completely healed") then
                if result:find("internal") then internals = true end
                if result:find("external") then externals = true end

                if (internals and externals) or result:find("cannot heal") then
                    table.remove(scars, 1)
                    internals = false
                    externals = false
                end
            elseif result:find("cannot heal") then
                table.remove(scars, 1)
                internals = false
                externals = false
            end
        end
    end
end

if mode == "self" then
    local wounds, scars = parse_wounds()
    if #wounds == 0 and #scars == 0 then
        echo("No injuries found!")
    else
        heal_wounds(wounds)
        heal_scars(scars)
        echo("Done healing!")
    end
else
    echo("Waiting for empathic link initiation...")
    echo("(Self-healing on link not yet implemented)")
end
