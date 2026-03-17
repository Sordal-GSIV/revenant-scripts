--- @revenant-script
--- name: hud_bounty
--- version: 0.4
--- author: Ondreian
--- game: gs
--- description: Formats bounty output into a HUD with session tracking
--- tags: cosmetic,bounty
---
--- Changelog (from Lich5):
---   v0.4 - Fix for Lich refactor 5.11+ namescope issue
---   v0.3 - Fix monospaced output for SF/Wiz FE
---   v0.2 - Fix for fmt_time
---   v0.1 - Initial release

--------------------------------------------------------------------------------
-- Session state
--------------------------------------------------------------------------------

local session_start = os.time()
local session_tasks = {}
local session_start_earned = nil
local session_start_expedites = nil

local HOOK_NAME = "hud_bounty_downstream"
local buffer = {}
local capturing = false

local START_MARKER = Char.name .. ", your Adventurer's Guild information is as follows:"
local TASK_INFO_RX  = Regex.new("^You have succeeded at the (.+?) task ([\\d,]+) times?(?:(?: and failed ([\\d,]+) times?)?)?\\.")
local TOTAL_RX      = Regex.new("^You have accumulated a total of ([\\d,]+) lifetime bounty points\\.")
local UNSPENT_RX    = Regex.new("^You currently have ([\\d,]+) unspent bounty points\\.")
local VOUCHERS_RX   = Regex.new("^You have ([\\d,]+) expedited task reassignment vouchers remaining\\.")
local EXEMPTION_RX  = Regex.new("^You are currently exempt from being assigned the (.+?) task\\.  Your exemption period will last until (.+?)\\.")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function parse_int(s)
    if not s then return 0 end
    return tonumber(s:gsub(",", "")) or 0
end

local function with_commas(num)
    local s = tostring(num)
    while true do
        local k
        s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return s
end

local function fmt_time(seconds)
    local days    = math.floor(seconds / 86400)
    seconds = seconds - (days * 86400)
    local hours   = math.floor(seconds / 3600)
    seconds = seconds - (hours * 3600)
    local minutes = math.floor(seconds / 60)
    seconds = math.floor(seconds - (minutes * 60))

    local parts = {}
    if days > 0 then parts[#parts + 1] = string.format("%02dd", days) end
    if hours > 0 then parts[#parts + 1] = string.format("%02dh", hours) end
    if minutes > 0 then parts[#parts + 1] = string.format("%02dm", minutes) end
    if seconds > 0 or #parts == 0 then parts[#parts + 1] = string.format("%02ds", seconds) end
    return table.concat(parts, " ")
end

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function pad_left(s, w)
    if #s >= w then return s end
    return string.rep(" ", w - #s) .. s
end

--------------------------------------------------------------------------------
-- Parse and display
--------------------------------------------------------------------------------

local function parse_and_show(lines)
    local tasks = {}
    local total_earned = 0
    local unspent = 0
    local expedites = 0
    local current_task = lines[#lines] or ""
    local total_done = 0
    local total_recent = 0
    local total_fails = 0

    for _, line in ipairs(lines) do
        local m = TASK_INFO_RX:match(line)
        if m then
            local task_name = m[1]:lower()
            local completions = parse_int(m[2])
            local fails = parse_int(m[3])
            session_tasks[task_name] = session_tasks[task_name] or completions
            local recent = completions - (session_tasks[task_name] or completions)
            total_done = total_done + completions
            total_recent = total_recent + recent
            total_fails = total_fails + fails
            tasks[#tasks + 1] = { task_name, completions, recent, fails }
        end

        local tm = TOTAL_RX:match(line)
        if tm then total_earned = parse_int(tm[1]) end

        local um = UNSPENT_RX:match(line)
        if um then unspent = parse_int(um[1]) end

        local vm = VOUCHERS_RX:match(line)
        if vm then expedites = parse_int(vm[1]) end
    end

    if not session_start_earned then session_start_earned = total_earned end
    if not session_start_expedites then session_start_expedites = expedites end

    local recent_earned = total_earned - session_start_earned
    local used_vouchers = session_start_expedites - expedites
    local uptime = fmt_time(os.time() - session_start)

    -- Build HUD output
    respond("")
    respond("This session has been active for " .. uptime .. ".")

    local earned_str = "You have earned " .. with_commas(total_earned) .. " lifetime points"
    if recent_earned > 0 then
        local hours = (os.time() - session_start) / 3600
        local per_hour = hours > 0 and math.floor(recent_earned / hours) or 0
        earned_str = earned_str .. ", " .. with_commas(recent_earned) .. " recently"
        earned_str = earned_str .. " [" .. with_commas(per_hour) .. " per hour],"
    end
    earned_str = earned_str .. " and " .. with_commas(unspent) .. " unspent."
    respond(earned_str)

    respond("You have " .. expedites .. " expedites remaining and have recently used " .. used_vouchers .. " vouchers.")

    -- Table
    respond("")
    respond(pad_right("task", 22) .. pad_left("done", 10) .. pad_left("recent", 10) .. pad_left("fails", 10))
    respond(string.rep("-", 52))
    for _, t in ipairs(tasks) do
        respond(pad_right(t[1], 22) .. pad_left(with_commas(t[2]), 10) .. pad_left(t[3] > 0 and tostring(t[3]) or "", 10) .. pad_left(t[4] > 0 and with_commas(t[4]) or "", 10))
    end
    respond(pad_right("total", 22) .. pad_left(with_commas(total_done), 10) .. pad_left(total_recent > 0 and tostring(total_recent) or "", 10) .. pad_left(total_fails > 0 and with_commas(total_fails) or "", 10))
    respond("")
    respond(current_task)
    respond("")
end

--------------------------------------------------------------------------------
-- Downstream hook: capture bounty output
--------------------------------------------------------------------------------

DownstreamHook.add(HOOK_NAME, function(line)
    if not line then return line end

    -- Start capturing when we see the bounty header
    if line:find(START_MARKER, 1, true) then
        capturing = true
        buffer = { line }
        return nil
    end

    if capturing then
        buffer[#buffer + 1] = line
        -- End of bounty output on prompt
        if line:find("<prompt") or line:find("^>") then
            capturing = false
            parse_and_show(buffer)
            buffer = {}
            return line
        end
        return nil
    end

    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

echo("Bounty HUD active. Type BOUNTY to see formatted output.")

while true do
    pause(1)
end
