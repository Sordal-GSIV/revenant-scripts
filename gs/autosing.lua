--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: autosing
--- version: 1.0.0
--- author: Timbalt
--- game: gs
--- tags: bard, loresing, logging, automation
--- description: Auto-loresing everything in a container; logs formatted results to a dated file
---
--- Original Lich5 author: Timbalt
---
--- Usage:
---   ;autosing
--- Requires sing_to_me_container to be set:
---   ;e UserVars.sing_to_me_container = "sack"

--------------------------------------------------------------------------------
-- Log file — one file per calendar day, sandboxed to the scripts data dir
--------------------------------------------------------------------------------

local LOG_FILE = "data/autoSing-LOG-" .. os.date("%Y-%m-%d") .. ".txt"

-- Append text to the sandboxed log file
local function log_append(text)
    local existing = File.exists(LOG_FILE) and (File.read(LOG_FILE) or "") or ""
    File.write(LOG_FILE, existing .. text)
end

-- Per-script log buffer; flushed after each item and on script death
local log_buf = ""

local function log(text)
    log_buf = log_buf .. text
end

local function flush_log()
    if log_buf ~= "" then
        log_append(log_buf)
        log_buf = ""
    end
end

before_dying(flush_log)

--------------------------------------------------------------------------------
-- Collect lines from the game until pattern matches or timeout elapses
--------------------------------------------------------------------------------

local function get_until(pattern, timeout)
    timeout = timeout or 30
    local lines = {}
    local start = os.time()
    while os.time() - start < timeout do
        local line = get()
        if not line then break end
        lines[#lines + 1] = line
        if Regex.test(pattern, line) then break end
    end
    return lines
end

--------------------------------------------------------------------------------
-- Send a loresing command; return the informational output lines
-- (everything after the "..." ellipsis, with XML stripped and empty lines removed)
--------------------------------------------------------------------------------

local function sing_info(cmd)
    local info    = {}
    fput(cmd)
    local lines   = get_until("Roundtime|<prompt")
    local catching = false
    for _, line in ipairs(lines) do
        if not catching and line:find("%.%.%.") then catching = true end
        if catching then
            local stripped = line:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
            if stripped ~= "" and not Regex.test("Roundtime|<prompt", line) then
                info[#info + 1] = stripped
            end
        end
    end
    return info
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local container_name = UserVars.sing_to_me_container
if not container_name or container_name == "" then
    echo("First time running the script? Set your container:")
    echo("  ;e UserVars.sing_to_me_container = \"sack\"")
    Script.exit()
end

-- Locate the container in inventory
local main_container = nil
for _, obj in ipairs(GameObj.inv()) do
    if Regex.test(container_name, obj.name) then
        main_container = obj
        break
    end
end

if not main_container then
    echo("Container '" .. container_name .. "' not found in inventory!")
    Script.exit()
end

-- Populate container contents via look
fput("look in my " .. main_container.noun)
pause(0.5)

local SEP = string.rep("=", 78)

local LORESING_SECTIONS = {
    { "Weight/Value", "loresing %s that I hold;let your value now be told"           },
    { "Purpose",      "loresing %s that I hold;let your purpose now be told"         },
    { "Magic",        "loresing %s that I hold;let your  magic now be told"          },
    { "Special",      "loresing %s that I hold;let your special ability now be told" },
}

for _, item in ipairs(main_container.contents or {}) do
    fput("get #" .. item.id)
    waitrt()

    -- Glance to get the full item name as it appears in-hand
    fput("glance")
    local glance_line = get()
    local fullname = glance_line
        and glance_line:match("You glance down to see (.+) in your right hand")
    if fullname then
        log("\n" .. SEP .. "\n")
        log("Item: " .. fullname .. "\n")
        log(SEP .. "\n\n")
    end

    fput("speak bard")
    pause(0.5)

    for _, section in ipairs(LORESING_SECTIONS) do
        local section_name = section[1]
        local cmd          = string.format(section[2], item.noun)

        local details = sing_info(cmd)
        pause(1)
        waitrt()
        waitcastrt()
        pause(1)

        -- Deduplicate, strip whitespace, filter out resonance noise
        local cleaned = {}
        local seen    = {}
        for _, line in ipairs(details) do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= ""
                and not Regex.test("^As you sing, you feel a faint resonating vibration", trimmed)
                and not seen[trimmed] then
                cleaned[#cleaned + 1] = trimmed
                seen[trimmed] = true
            end
        end

        if #cleaned > 0 then
            log("  " .. section_name .. ":\n")
            for _, line in ipairs(cleaned) do
                log("    \xE2\x80\xA2 " .. line .. "\n")  -- UTF-8 bullet •
            end
            log("\n")
        end
    end

    -- Flush after each item so data is preserved if script is killed
    flush_log()

    pause(1)
    fput("put #" .. item.id .. " in my " .. container_name)
    waitrt()
    waitcastrt()
    pause(0.5)
end

echo("Loresing complete. Log: " .. LOG_FILE)
