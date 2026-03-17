--- @revenant-script
--- name: catchemintheact
--- version: 2.0.0
--- author: Kaetel
--- game: gs
--- description: Highlight observed ACTs from other players with configurable preset styling
--- tags: text, formatting, act, highlight
---
--- Usage:
---   ;catchemintheact                    - use default bold preset
---   ;catchemintheact --preset=thought   - use thought preset
---   ;catchemintheact --no-parentheses   - remove parentheses around ACT text
---   ;catchemintheact --help             - show help
---
--- Presets: bold, thought, whisper, speech, link, none

local HOOK_NAME = Script.name .. "::hook"

local ALL_PRESETS = {"bold", "thought", "whisper", "speech", "link", "none"}

local HELP_TXT = [[
Usage: catchemintheact [options]
Options:
  --help, -h          Show this help message
  --preset=<preset>   One of bold, thought, whisper, speech, link, none (default: bold)
  --no-parentheses    Remove parentheses around ACT text
]]

local ACT_PATTERN = '^%((<a exist="[^"]+" noun="[^"]+">.-</a>)(.-%))'

local options = {
    preset = "bold",
    keep_parentheses = true,
}

local function is_valid_preset(p)
    for _, v in ipairs(ALL_PRESETS) do
        if v == p then return true end
    end
    return false
end

local function parse_opts(args)
    for _, opt in ipairs(args) do
        if opt == "--help" or opt == "-h" then
            respond(HELP_TXT)
            return false
        elseif opt:match("^%-%-preset=(.+)") then
            local preset = opt:match("^%-%-preset=(.+)"):lower()
            if not is_valid_preset(preset) then
                echo("Unknown preset option '" .. preset .. "'")
                return false
            end
            options.preset = preset
        elseif opt == "--no-parentheses" then
            options.keep_parentheses = false
        else
            -- Legacy: single word preset
            local lower = opt:lower()
            if is_valid_preset(lower) then
                options.preset = lower
            else
                echo("Unknown option '" .. opt .. "'")
                return false
            end
        end
    end
    return true
end

local function wrap_preset(text)
    if options.preset == "none" then return text end
    return "<preset id=\"" .. options.preset .. "\">" .. text .. "</preset>"
end

-- Parse args
local args = {}
for i = 1, 10 do
    if Script.vars[i] then
        table.insert(args, Script.vars[i])
    end
end

if not parse_opts(args) then return end

echo("Capturing ACTs with preset '" .. options.preset .. "', " .. (options.keep_parentheses and "keeping" or "removing") .. " parentheses")

DownstreamHook.add(HOOK_NAME, function(server_string)
    if not server_string then return server_string end

    -- ACT format: (CharacterLink does something)
    local anchor, act_text = server_string:match('^%((<a [^>]*noun="[^"]+[^>]*>.-</a>)(.-%))')
    if anchor and act_text then
        if options.preset ~= "none" then
            server_string = server_string:gsub(act_text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"), wrap_preset(act_text), 1)
        end
        if not options.keep_parentheses then
            server_string = server_string:gsub("[()]", "")
        end
    end

    return server_string
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
end)

while true do
    pause(1)
end
