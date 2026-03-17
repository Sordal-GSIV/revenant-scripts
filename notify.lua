--- @revenant-script
--- name: notify
--- version: 1.3.1
--- author: Ondreian
--- contributors: Dalem
--- description: Desktop notification system for whispers, messages, stuns, and custom events
--- tags: util,notification,whisper,lnet
---
--- Changelog (from Lich5):
---   v1.3.1 (2025-02-26): Fix for Lich 5.11+, rubocop cleanup
---   v1.3.0 (2017-02-18): Spinners, pattern matching
---   v1.2.0 (2017-02-17): Sound pattern matching
---   v1.1.0 (2017-02-15): Danger notifications (stun, low health)
---
--- Usage:
---   ;notify                     - Start notification watcher
---   ;notify help                - Show help
---   ;notify sounds              - List available system sounds
---   ;notify sounds <pattern>    - List matching sounds
---   ;notify set-sound <sound>   - Set notification sound
---   ;notify play <sound>        - Play a sound once
---   ;notify mute                - Turn off sound
---   ;notify ignore <name>       - Ignore messages from a character
---   ;notify unignore <name>     - Stop ignoring a character
---
--- Supported platforms: Linux (notify-send), macOS (osascript)
--- Game-agnostic: works with GS and DR

--------------------------------------------------------------------------------
-- Platform detection
--------------------------------------------------------------------------------

local OS = {}
function OS.linux()
    local p = os.getenv("OSTYPE") or ""
    -- In Revenant, check platform info
    if GameState and GameState.platform then
        return string.find(string.lower(GameState.platform), "linux") ~= nil
    end
    return string.find(p, "linux") ~= nil
end

function OS.mac()
    if GameState and GameState.platform then
        return string.find(string.lower(GameState.platform), "darwin") ~= nil
    end
    return false
end

function OS.which(cmd)
    local handle = io.popen("which " .. cmd .. " 2>/dev/null")
    if handle then
        local result = handle:read("*l")
        handle:close()
        return result
    end
    return nil
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SETTINGS_FILE = "data/notify_settings.json"

local function load_settings()
    if File.exists(SETTINGS_FILE) then
        local ok, data = pcall(function() return Json.decode(File.read(SETTINGS_FILE)) end)
        if ok and type(data) == "table" then return data end
    end
    return { sound = nil, duration = 3000, ignored = {} }
end

local function save_settings(s)
    File.write(SETTINGS_FILE, Json.encode(s))
end

local notify_settings = load_settings()

--------------------------------------------------------------------------------
-- Sounds
--------------------------------------------------------------------------------

local Sounds = {}

function Sounds.dirs()
    if OS.linux() then return { "/usr/share/sounds/" }
    elseif OS.mac() then
        local home = os.getenv("HOME") or ""
        return { home .. "/Library/Sounds/", "/System/Library/Sounds/" }
    end
    return {}
end

function Sounds.bin()
    if OS.linux() then return "paplay"
    elseif OS.mac() then return "afplay"
    end
    return nil
end

function Sounds.list()
    local result = {}
    for _, dir in ipairs(Sounds.dirs()) do
        local handle = io.popen("find " .. dir .. " -type f 2>/dev/null")
        if handle then
            for line in handle:lines() do
                if string.match(line, "%.[a-zA-Z0-9]+$") then
                    table.insert(result, line)
                end
            end
            handle:close()
        end
    end
    return result
end

function Sounds.match(pattern)
    local all = Sounds.list()
    if not pattern or pattern == "" or pattern == "/" then return all end
    local result = {}
    for _, f in ipairs(all) do
        if string.find(string.lower(f), string.lower(pattern)) then
            table.insert(result, f)
        end
    end
    return result
end

function Sounds.find(name)
    if not name then return nil end
    for _, f in ipairs(Sounds.list()) do
        if string.find(string.lower(f), string.lower(name)) then
            return f
        end
    end
    return nil
end

function Sounds.play(sound_name)
    local bin = Sounds.bin()
    if not bin or not OS.which(bin) then return end
    local path = sound_name
    if not string.find(sound_name or "", "/") then
        path = Sounds.find(sound_name)
    end
    if path then
        os.execute(bin .. " " .. path .. " &")
    end
end

function Sounds.current()
    return notify_settings.sound
end

function Sounds.set(sound)
    notify_settings.sound = sound
    save_settings(notify_settings)
end

--------------------------------------------------------------------------------
-- Cooldown cache
--------------------------------------------------------------------------------

local Cooldown = {}
Cooldown.data = {}
Cooldown.ttl_sec = 5

function Cooldown.put(key)
    Cooldown.data[key] = os.time() + Cooldown.ttl_sec
    Cooldown.prune()
end

function Cooldown.has(key)
    Cooldown.prune()
    return Cooldown.data[key] ~= nil and Cooldown.data[key] > os.time()
end

function Cooldown.prune()
    local now = os.time()
    for k, v in pairs(Cooldown.data) do
        if now > v then Cooldown.data[k] = nil end
    end
end

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

local PRIVATE_MSG_RE = Regex.new("^\\[Private\\]-GSIV:(.+?): \"(.+?)\"")
local GM_SEND_RE     = Regex.new("^SEND\\[(\\w+)\\]\\s+(.+?)$")
local OOC_WHISPER_RE = Regex.new("^\\(OOC\\) (.+?)'s player whispers(?:.*?), \"(.+?)\"$")
local IC_WHISPER_RE  = Regex.new("^(.+?) whispers(?:.*?), \"(.+?)\"$")
local SPEECH_RE      = Regex.new("^Speaking (?:.*?)to you, (.+?) (?:.*?), \"(.+?)\"$")
local SPINNER_RE     = Regex.new("comes to a stop pointing directly at you!")
local LEVEL_UP_RE    = Regex.new("^You are now level (\\d+)!")
local SHOP_SALE_RE   = Regex.new("^Your (.+?) just sold for (.+?) silvers from")
local RAFFLE_RE      = Regex.new("^You sense you have just won a raffle")

local IGNORED_BODIES = Regex.new("^Clearcheck\\.|^Clear:|^Coinme$")

local TRAINING_AREAS = { [16994] = true }

--------------------------------------------------------------------------------
-- Notification dispatch
--------------------------------------------------------------------------------

local function show_notification(title, body)
    if OS.linux() then
        local cmd = string.format('notify-send "%s" "%s" --icon=mail-send-receive --app-name=gemstone',
            tostring(title), tostring(body))
        os.execute(cmd .. " &")
    elseif OS.mac() then
        local cmd = string.format([[osascript -e 'display notification "%s" with title "%s"']],
            tostring(body), tostring(title))
        os.execute(cmd .. " &")
    end
end

local function notify(from, body, msg_type)
    local title = tostring(from) .. " => " .. GameState.name .. " [" .. tostring(msg_type) .. "]"
    show_notification(title, body)
    if Sounds.current() then
        Sounds.play(Sounds.current())
    end
end

local function should_skip(from, body)
    if not from then return true end
    for _, name in ipairs(notify_settings.ignored or {}) do
        if string.lower(name) == string.lower(from) then return true end
    end
    if body and IGNORED_BODIES:test(body) then return true end
    if Cooldown.has(from) then return true end
    return false
end

local function parse_message(line)
    local m

    m = PRIVATE_MSG_RE:match(line)
    if m then return m[1], m[2], "lnet" end

    m = GM_SEND_RE:match(line)
    if m then return m[1], m[2], "gm" end

    m = OOC_WHISPER_RE:match(line)
    if m then return m[1], m[2], "whisper:ooc" end

    m = IC_WHISPER_RE:match(line)
    if m then return m[1], m[2], "whisper:ic" end

    m = SPEECH_RE:match(line)
    if m then return m[1], m[2], "speech" end

    if SPINNER_RE:test(line) then
        return "merchant", "You were spun for a service!", "spinner"
    end

    m = LEVEL_UP_RE:match(line)
    if m then return "game", GameState.name .. " is now level " .. m[1], "level_up" end

    if SHOP_SALE_RE:test(line) then
        return "shop", line, "sale"
    end

    if RAFFLE_RE:test(line) then
        return "raffle", GameState.name .. " won a raffle!", "win"
    end

    return nil
end

--------------------------------------------------------------------------------
-- Danger monitor
--------------------------------------------------------------------------------

local function check_danger()
    if stunned and stunned() and not TRAINING_AREAS[Room.id] then
        return GameState.name .. " has been stunned!"
    end
    if percenthealth and percenthealth() < 90 then
        return GameState.name .. "'s health is at " .. tostring(percenthealth()) .. "%"
    end
    return nil
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(args, word)
end

local cmd = args[1] and string.lower(args[1]) or nil

if cmd == "help" then
    respond("  ;notify                     - Start notification watcher")
    respond("  ;notify sounds [pattern]    - List available sounds")
    respond("  ;notify set-sound <sound>   - Set notification sound")
    respond("  ;notify play <sound>        - Play a sound once")
    respond("  ;notify mute                - Turn off sound")
    respond("  ;notify ignore <name>       - Ignore messages from character")
    respond("  ;notify unignore <name>     - Stop ignoring character")
    return
end

if cmd == "sounds" then
    local matches = Sounds.match(args[2] or "/")
    for _, f in ipairs(matches) do
        -- Show last two path components
        local parts = {}
        for part in string.gmatch(f, "[^/]+") do table.insert(parts, part) end
        if #parts >= 2 then
            respond(parts[#parts - 1] .. "/" .. parts[#parts])
        else
            respond(f)
        end
    end
    return
end

if cmd == "play" then
    local target = Sounds.find(args[2])
    if target then
        respond("Playing: " .. target)
        Sounds.play(target)
    else
        respond("Sound not found: " .. tostring(args[2]))
    end
    return
end

if cmd == "mute" then
    Sounds.set(nil)
    respond("[notify] muted")
    return
end

if cmd == "ignore" then
    for i = 2, #args do
        local name = args[i]
        if name then
            name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
            table.insert(notify_settings.ignored, name)
        end
    end
    save_settings(notify_settings)
    respond("Ignored: " .. table.concat(notify_settings.ignored, ", "))
    return
end

if cmd == "unignore" then
    for i = 2, #args do
        local name = args[i]
        if name then
            name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
            local new = {}
            for _, n in ipairs(notify_settings.ignored) do
                if n ~= name then table.insert(new, n) end
            end
            notify_settings.ignored = new
        end
    end
    save_settings(notify_settings)
    respond("Ignored: " .. table.concat(notify_settings.ignored, ", "))
    return
end

if cmd == "set-sound" then
    Sounds.set(args[2])
    local path = Sounds.find(args[2])
    if path then
        respond("[notify] playing -> " .. path)
        Sounds.play(path)
    else
        respond("[notify] muted")
    end
    return
end

-- Check notify-send / osascript availability
local notify_bin = OS.linux() and "notify-send" or (OS.mac() and "osascript" or nil)
if notify_bin and not OS.which(notify_bin) then
    echo("Warning: " .. notify_bin .. " not found in $PATH. Desktop notifications disabled.")
end

--------------------------------------------------------------------------------
-- Main watcher loop
--------------------------------------------------------------------------------

echo("Notify v1.3.1 started. Watching for messages...")

-- Danger check background (simulated via periodic polling)
local last_danger_check = 0
local DANGER_TIMEOUT = 30

while true do
    local line = get()
    if line then
        local from, body, msg_type = parse_message(line)
        if from and not should_skip(from, body) then
            notify(from, body, msg_type)
            Cooldown.put(from)
        end
    end

    -- Periodic danger check
    local now = os.time()
    if now - last_danger_check > 5 then
        last_danger_check = now
        local danger = check_danger()
        if danger then
            notify("notify", danger, "danger")
        end
    end
end
