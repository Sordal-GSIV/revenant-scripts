--- @revenant-script
--- name: star_sing
--- version: 1.0.0
--- author: Starsworn
--- game: gs
--- tags: bard, loresing, loresong, singing
--- description: Loresing items with raise/tap detection, bot mode, and log mode
---
--- Original Lich5 authors: Starsworn, Ifor Get
--- Ported to Revenant Lua from star-sing.lic
---
--- Usage:
---   ;star_sing           - sing all four aspects on right-hand item
---   ;star_sing help      - show help
---   ;star_sing bot       - accept offers and recite in person
---   ;star_sing log       - append to daily log

local failed_items = {}

local function clean_noun(noun)
    return (noun or ""):gsub("^a pair of%s+", ""):gsub("^an%s+", ""):gsub("^a%s+", ""):gsub("^the%s+", ""):gsub("<.->", ""):match("^%s*(.-)%s*$")
end

local function sing_info(cmd)
    local info = {}
    local done = false
    local catching = false

    local HOOK_ID = "SingInfoHook"
    DownstreamHook.add(HOOK_ID, function(ss)
        local stripped = ss:match("^%s*(.-)%s*$"):gsub("<.->", "")
        if Regex.test(ss, "You sing:|As you sing|Continuing your song|Your voice weaves|Your song flows|Your music surrounds") then
            catching = true
        end
        if catching and stripped ~= "" and not Regex.test(ss, "^Roundtime:") then
            info[#info + 1] = stripped
        end
        if Regex.test(ss, "Roundtime: %d+ sec|resonates with what you previously learned") then
            done = true
            DownstreamHook.remove(HOOK_ID)
        end
        return ss
    end)

    fput(cmd)
    wait_until(function() return done end)
    waitrt()
    waitcastrt()
    wait(0.5)
    DownstreamHook.remove(HOOK_ID)
    return info
end

local function full_right_desc()
    fput("glance")
    local line = get()
    if line then
        local desc = line:match("You glance down to see (.-) in your right hand")
        if desc then return desc:match("^%s*(.-)%s*$") end
    end
    return checkright() or ""
end

local aspects = { "value", "purpose", "magic", "special ability" }
local args = Script.current.vars

if not args[1] then
    -- Sing on right-hand item
    local raw_desc = full_right_desc()
    local raw_noun = clean_noun(raw_desc)

    fput("speak bard")
    for _, aspect in ipairs(aspects) do
        waitrt()
        waitcastrt()
        sing_info("loresing " .. raw_noun .. " that I hold;let your " .. aspect .. " now be told")
    end
    fput("speak common")
    waitrt()

elseif args[1]:lower() == "help" then
    respond("Usage:")
    respond("  ;star_sing           - sing all four on right-hand item")
    respond("  ;star_sing help      - show this message")
    respond("  ;star_sing bot       - accept offers & recite in person")
    respond("  ;star_sing log       - append to daily log")

elseif args[1]:lower() == "bot" then
    while true do
        local customer = matchfind("? offers you")
        fput("accept")
        wait(2)
        waitrt()

        local raw_desc = full_right_desc()
        local raw_noun = clean_noun(raw_desc)

        for _, aspect in ipairs(aspects) do
            waitrt()
            waitcastrt()
            local details = sing_info("loresing " .. raw_noun .. " that I hold;let your " .. aspect .. " now be told")
            local recite_text = table.concat(details, "; ")
            if #recite_text > 600 then
                for _, d in ipairs(details) do
                    fput("say " .. d)
                    waitrt()
                end
            else
                fput("recite " .. recite_text)
                waitrt()
            end
        end

        local result = dothistimeout("give " .. customer, 35, "accepted|declined|expired")
        if result and Regex.test(result, "expired|declined") then
            fput("stow right")
        end
    end

elseif args[1]:lower() == "log" then
    local log_file = (GameState.script_dir or ".") .. "/iSing-LOG-" .. os.date("%Y-%m-%d") .. ".txt"
    local raw_desc = full_right_desc()
    local raw_noun = clean_noun(raw_desc)

    local file = io.open(log_file, "a")
    if file then
        file:write("=== " .. raw_noun .. " ===\n")
        for _, aspect in ipairs(aspects) do
            waitrt()
            waitcastrt()
            local details = sing_info("loresing " .. raw_noun .. " that I hold;let your " .. aspect .. " now be told")
            file:write(table.concat(details, "; ") .. "\n\n")
        end
        file:close()
        echo("Logged to " .. log_file)
    end
end

if #failed_items > 0 then
    respond("Items returned without being loresung: " .. table.concat(failed_items, ", "))
end
