--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: premsong
--- version: 1.0.0
--- author: Revenant
--- game: gs
--- description: Sing a GemStone IV premium song with configurable tone and lyrics
---
--- Usage:
---   ;premsong                  — sing with saved tone and lyrics
---   ;premsong [tone]           — override tone for this sing only
---   ;premsong set-tone [tone]  — save a default tone (blank = none)
---   ;premsong add [line]       — append a lyric line to the saved list
---   ;premsong remove [n]       — remove lyric line number n
---   ;premsong clear            — clear all saved lyrics
---   ;premsong list             — show saved tone and lyrics
---   ;premsong preview          — show what will be sent to the game
---   ;premsong settings         — open GUI settings editor
---   ;premsong help             — show this help

local settings    = require("settings")
local gui_settings = require("gui_settings")

local state = settings.load()

-- ──────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────────────────────

local function build_lyric_string()
    return table.concat(state.lyrics, ";")
end

local function do_sing(tone_override)
    local tone = (tone_override and tone_override ~= "") and tone_override
                 or (state.tone ~= "" and state.tone or nil)

    if #state.lyrics == 0 then
        respond("[premsong] No lyrics saved. Use ';premsong add <line>' to add lyrics.")
        return
    end

    waitrt()

    if tone then
        fput("song " .. tone)
        if state.delay > 0 then wait(state.delay) end
    end

    local lyric_str = build_lyric_string()
    fput("sing " .. lyric_str)
    waitrt()

    if tone and state.reset_tone then
        fput("song none")
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Argument dispatch
-- ──────────────────────────────────────────────────────────────────────────────

local cmd = Script.vars[0] or ""
local rest = Script.vars[1] or ""

-- ;premsong settings / setup → GUI
if cmd == "settings" or cmd == "setup" then
    gui_settings.open(state)

-- ;premsong set-tone [tone]
elseif cmd == "set-tone" or cmd == "tone" then
    state.tone = rest
    settings.save(state)
    if rest == "" then
        respond("[premsong] Default tone cleared.")
    else
        respond("[premsong] Default tone set to: " .. rest)
    end

-- ;premsong add <line>
elseif cmd == "add" then
    if rest == "" then
        respond("[premsong] Usage: ;premsong add <lyric line>")
    else
        -- rest may be just vars[1]; reconstruct full line from all remaining vars
        local parts = {}
        local i = 1
        while Script.vars[i] do
            table.insert(parts, Script.vars[i])
            i = i + 1
        end
        local line = table.concat(parts, " ")
        table.insert(state.lyrics, line)
        settings.save(state)
        respond(string.format("[premsong] Added line %d: %s", #state.lyrics, line))
    end

-- ;premsong remove <n>
elseif cmd == "remove" or cmd == "rm" then
    local n = tonumber(rest)
    if not n or n < 1 or n > #state.lyrics then
        respond(string.format("[premsong] Invalid line number. Have %d lines.", #state.lyrics))
    else
        local removed = table.remove(state.lyrics, n)
        settings.save(state)
        respond(string.format("[premsong] Removed line %d: %s", n, removed))
    end

-- ;premsong clear
elseif cmd == "clear" then
    state.lyrics = {}
    settings.save(state)
    respond("[premsong] All lyrics cleared.")

-- ;premsong list
elseif cmd == "list" then
    local tone_disp = state.tone ~= "" and state.tone or "(none)"
    respond(string.format("[premsong] Tone: %s | Reset: %s | Lines: %d",
        tone_disp, tostring(state.reset_tone), #state.lyrics))
    for i, line in ipairs(state.lyrics) do
        respond(string.format("  %2d. %s", i, line))
    end

-- ;premsong preview
elseif cmd == "preview" then
    local tone_disp = state.tone ~= "" and state.tone or "(none)"
    respond("[premsong] Preview:")
    if state.tone ~= "" then
        respond("  song " .. state.tone)
    end
    if #state.lyrics > 0 then
        respond("  sing " .. build_lyric_string())
    else
        respond("  (no lyrics)")
    end
    if state.tone ~= "" and state.reset_tone then
        respond("  song none")
    end

-- ;premsong help
elseif cmd == "help" then
    respond("[premsong] Commands:")
    respond("  ;premsong                 — sing with saved tone and lyrics")
    respond("  ;premsong [tone]          — override tone for this sing only")
    respond("  ;premsong set-tone [tone] — save a default tone (blank to clear)")
    respond("  ;premsong add <line>      — append a lyric line")
    respond("  ;premsong remove <n>      — remove lyric line n")
    respond("  ;premsong clear           — clear all saved lyrics")
    respond("  ;premsong list            — show saved tone and lyrics")
    respond("  ;premsong preview         — preview commands that will be sent")
    respond("  ;premsong settings        — open GUI settings editor")

-- ;premsong [tone] or ;premsong (bare)
else
    -- cmd is either blank (sing with defaults) or a tone override string
    do_sing(cmd)
end
