--- @revenant-script
--- name: bounty_bitch
--- version: 0.4.0
--- author: nishima
--- game: gs
--- tags: bounty, tracking
--- description: Track group bounties and display shared bounty list
---
--- Original Lich5 authors: nishima
--- Ported to Revenant Lua from bounty-bitch.lic v0.4
---
--- Usage:
---   ;bounty_bitch                    - record and display bounties
---   ;bounty_bitch set familiar on    - display in familiar window
---   ;bounty_bitch set familiar off   - display in main window

local window = CharSettings.get("bounty_bitch_window") or "main"

local args = Script.current.vars[0]
if args then
    local toggle = args:match("^set fam%w* (on|off)")
    if toggle then
        if toggle == "on" then
            CharSettings.set("bounty_bitch_window", "familiar")
            respond("Bounty list will display in the familiar window.")
        else
            CharSettings.set("bounty_bitch_window", "main")
            respond("Bounty list will display in the main window.")
        end
        return
    else
        respond("")
        respond("See everyone's bounties so the bounty bitch can get them.")
        respond("Add it to your autostart / run it after you get a new one.")
        respond("")
        respond("To display in the familiar window use")
        respond(";bounty_bitch set familiar [on|off]")
        respond("")
        return
    end
end

local file_path = GameState.data_dir .. "/bounty-bitch.txt"
local prefix = GameState.character_name .. ":"
local non_gather_text = "-"

local function write_or_replace_line(fp, pfx, new_line)
    local lines = {}
    local f = io.open(fp, "r")
    if f then
        for line in f:lines() do
            lines[#lines + 1] = line
        end
        f:close()
    end
    local updated = false
    for i, line in ipairs(lines) do
        if line:sub(1, #pfx) == pfx then
            lines[i] = new_line
            updated = true
            break
        end
    end
    if not updated then
        lines[#lines + 1] = new_line
    end
    f = io.open(fp, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end
end

local result_lines = quiet_command("bounty", "your Adventurer's Guild information is as follows")
local bounty = nil
for _, l in ipairs(result_lines or {}) do
    if l:find("You have been tasked ") then
        bounty = l
        break
    end
end

local new_line
if bounty then
    if Regex.test(bounty, "^You have been tasked to (rescue|suppress|recover|hunt)") then
        bounty = non_gather_text
    end
    local description, quantity = bounty:match("multiple customers requesting a?n? ?(.-).  You have been tasked to retrieve (%d+)")
    if quantity then
        bounty = quantity .. " " .. description
    else
        local qty2, quality = bounty:match("retrieve (.+) of at least (.-) quality")
        if qty2 then
            bounty = qty2 .. " (" .. quality .. " quality)"
        else
            local name, loc, count = bounty:match('forage (.-)">(.-) found (.-).  These samples.-retrieve (%d+)')
            if name then
                bounty = (count or "?") .. " " .. name .. " " .. loc
            end
        end
    end
    new_line = prefix .. " " .. bounty
else
    new_line = prefix .. " " .. non_gather_text
end

write_or_replace_line(file_path, prefix, new_line)

local f = io.open(file_path, "r")
local bounty_list = f and f:read("*a") or ""
if f then f:close() end

bounty_list = bounty_list:gsub("([^\n]+):", "<pushBold/>%1:<popBold/>")

if window == "familiar" then
    put('<clearStream id="familiar"/><pushStream id="familiar"/><output class="mono"/>' .. bounty_list .. '<output class=""/><popStream/>')
else
    put("~")
    put('<output class="mono"/>' .. bounty_list .. '<output class=""/>')
    put("~")
end
