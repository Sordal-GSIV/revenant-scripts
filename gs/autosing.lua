--- @revenant-script
--- name: autosing
--- version: 1.0.0
--- author: Timbalt
--- game: gs
--- tags: bard, loresing, logging, automation
--- description: Auto-loresing everything in a container and log formatted results
---
--- Original Lich5 authors: Timbalt
--- Ported to Revenant Lua from autosing.lic
---
--- Usage: ;autosing
--- Requires: ;vars set sing_to_me_container = <container>

local log_dir = GameState.script_dir or "."

local function get_until(pattern, timeout)
    timeout = timeout or 30
    local lines = {}
    local start = os.time()
    while os.time() - start < timeout do
        local line = get()
        if not line then break end
        lines[#lines + 1] = line
        if Regex.test(line, pattern) then break end
    end
    return lines
end

local function sing_info(cmd)
    local info = {}
    fput(cmd)
    local lines = get_until("Roundtime|prompt")
    local catching = false
    for _, line in ipairs(lines) do
        if not catching and line:find("%.%.%.") then catching = true end
        if catching then
            local stripped = line:match("^%s*(.-)%s*$"):gsub("<.->", "")
            if stripped ~= "" and not Regex.test(line, "Roundtime|prompt") then
                info[#info + 1] = stripped
            end
        end
    end
    return info
end

local container_name = UserVars.get("sing_to_me_container")
if not container_name or container_name == "" then
    echo("First time running the script? Set your sing_to_me_container")
    echo(";vars set sing_to_me_container = container")
    return
end

local main_container = nil
for _, obj in ipairs(GameObj.inv()) do
    if Regex.test(obj.name, container_name) then
        main_container = obj
        break
    end
end

if not main_container then
    echo("Container '" .. container_name .. "' not found in inventory!")
    return
end

fput("look in my " .. main_container.noun)

for _, item in ipairs(main_container.contents or {}) do
    fput("get #" .. item.id)

    local log_file = log_dir .. "/autoSing-LOG-" .. os.date("%Y-%m-%d") .. ".txt"
    local file = io.open(log_file, "a")

    fput("glance")
    local glance_result = get()
    local fullitemname = glance_result and glance_result:match("You glance down to see (.-) in your right hand")
    if fullitemname and file then
        local sep = string.rep("=", 78)
        file:write("\n" .. sep .. "\n")
        file:write("Item: " .. fullitemname .. "\n")
        file:write(sep .. "\n\n")
    end

    fput("speak bard")
    wait(0.5)

    local sections = {
        { "Weight/Value", "loresing " .. item.noun .. " that I hold;let your value now be told" },
        { "Purpose",      "loresing " .. item.noun .. " that I hold;let your purpose now be told" },
        { "Magic",        "loresing " .. item.noun .. " that I hold;let your  magic now be told" },
        { "Special",      "loresing " .. item.noun .. " that I hold;let your special ability now be told" },
    }

    for _, section in ipairs(sections) do
        local section_name, cmd = section[1], section[2]
        local details = sing_info(cmd)
        wait(1)
        waitrt()
        waitcastrt()
        wait(1)

        -- Clean lines
        local cleaned = {}
        local seen = {}
        for _, line in ipairs(details) do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" and not Regex.test(trimmed, "^As you sing, you feel a faint resonating vibration") and not seen[trimmed] then
                cleaned[#cleaned + 1] = trimmed
                seen[trimmed] = true
            end
        end

        if #cleaned > 0 and file then
            file:write("  " .. section_name .. ":\n")
            for _, line in ipairs(cleaned) do
                file:write("    * " .. line .. "\n")
            end
            file:write("\n")
        end
    end

    if file then file:close() end

    wait(1)
    fput("put #" .. item.id .. " in my " .. container_name)
    waitrt()
    waitcastrt()
    wait(0.5)
end
