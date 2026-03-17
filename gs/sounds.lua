--- @revenant-script
--- name: sounds
--- version: 1.0
--- author: unknown
--- game: gs
--- description: Play a sound on incoming messages. Listens for game lines and triggers audio.
--- NOTE: Sound playback requires OS-level support; the original used Win32 WAV.
---       This version echoes a notification. Replace play_sound() with your platform hook.

local sound_file = "Messaging - Captain Incoming Message.wav"

local function play_sound()
    -- Platform-specific sound playback would go here.
    -- For now, echo a notification.
    echo("[sounds] *ding* -- incoming message")
end

while true do
    local line = get()
    if line and line:find("Please rephrase that command%.") then
        play_sound()
    end
end
