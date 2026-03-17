--- @revenant-script
--- name: soundfx
--- version: 0.2
--- author: Nisugi
--- game: gs
--- description: Audio triggers -- play sounds on pattern matches in game text
--- tags: sounds
---
--- Changelog (from Lich5):
---   v0.2 (2025-04-21) - Change mac from system call to NSSound, added error messaging
---   v0.1 - Initial release
---
--- Note: Place .wav files in data/sfx/. Use ;soundfx setup to configure triggers.

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local DATA_FILE = "data/sfx_triggers.json"

local function load_triggers()
    if not File.exists(DATA_FILE) then return {} end
    local ok, data = pcall(function()
        return Json.decode(File.read(DATA_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function save_triggers(triggers)
    File.write(DATA_FILE, Json.encode(triggers))
end

local triggers = load_triggers()

--------------------------------------------------------------------------------
-- Sound playback (Revenant uses Audio.play if available, else system command)
--------------------------------------------------------------------------------

local function play_sound(sound_name)
    local sound_file = "data/sfx/" .. sound_name .. ".wav"
    if not File.exists(sound_file) then
        echo("[SoundFX] Sound file not found: " .. sound_file)
        return
    end
    -- Attempt to play via system; Revenant may provide Audio.play in the future
    if Audio and Audio.play then
        Audio.play(sound_file)
    else
        os.execute('aplay "' .. sound_file .. '" >/dev/null 2>&1 &')
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function run_setup()
    local win = Gui.window("SoundFX Manager", { width = 600, height = 400 })
    local root = Gui.vbox()

    root:add(Gui.label("Configure trigger text and associated sound file name (no .wav):"))
    root:add(Gui.separator())

    local entries = {}
    for trigger, sound in pairs(triggers) do
        local row = Gui.hbox()
        local trigger_input = Gui.input({ text = trigger, placeholder = "trigger text" })
        local sound_input = Gui.input({ text = sound, placeholder = "sound name" })
        row:add(trigger_input)
        row:add(sound_input)
        root:add(row)
        entries[#entries + 1] = { trigger_input = trigger_input, sound_input = sound_input }
    end

    local add_btn = Gui.button("Add Trigger")
    add_btn:on_click(function()
        local row = Gui.hbox()
        local ti = Gui.input({ text = "", placeholder = "trigger text" })
        local si = Gui.input({ text = "", placeholder = "sound name" })
        row:add(ti)
        row:add(si)
        root:add(row)
        entries[#entries + 1] = { trigger_input = ti, sound_input = si }
    end)
    root:add(add_btn)

    local save_btn = Gui.button("Save & Close")
    save_btn:on_click(function()
        triggers = {}
        for _, e in ipairs(entries) do
            local t = e.trigger_input:get_text():match("^%s*(.-)%s*$")
            local s = e.sound_input:get_text():match("^%s*(.-)%s*$")
            if t ~= "" and s ~= "" then
                triggers[t] = s
            end
        end
        save_triggers(triggers)
        echo("SoundFX triggers saved!")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(Gui.scroll(root))
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- CLI
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]
if arg1 and (arg1:lower() == "setup" or arg1:lower() == "gui") then
    run_setup()
    return
end

--------------------------------------------------------------------------------
-- Downstream hook: match triggers and play sounds
--------------------------------------------------------------------------------

local HOOK_NAME = "soundfx_downstream"

DownstreamHook.add(HOOK_NAME, function(line)
    if not line then return line end
    local stripped = line:gsub("<.->", ""):lower()

    for trigger, sound in pairs(triggers) do
        if stripped:find(trigger:lower(), 1, true) then
            if sound and sound ~= "" then
                play_sound(sound)
            else
                echo("[SoundFX] No sound file set for trigger: " .. trigger)
            end
            break
        end
    end
    return line
end)

before_dying(function()
    DownstreamHook.remove(HOOK_NAME)
    save_triggers(triggers)
end)

echo("SoundFX active with " .. (function()
    local n = 0; for _ in pairs(triggers) do n = n + 1 end; return n
end)() .. " trigger(s). Type ;soundfx setup to configure.")

while true do
    pause(60)
end
