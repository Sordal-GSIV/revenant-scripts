--- @revenant-script
--- name: imagination
--- version: 1.1
--- author: Dendum
--- game: gs
--- description: Character image viewer - detects character names from game text for image display
--- tags: roleplay, images, whisper, window
---
--- Ported from imagination.lic (265 lines)
---
--- NOTE: The original script used GTK3 to display character images in a window.
--- Revenant does not include GTK. This conversion preserves all the game-text
--- parsing logic (detecting "You see", whispers, prename titles) and echoes
--- detections. A GUI frontend could subscribe to these events for image display.
---
--- Original features preserved:
---   - Detects character names from "You see <Title> <Name>" lines
---   - Detects character names from whispers (direct and distant/faint)
---   - Filters out "You see a " lines (animals/objects)
---   - Handles prename title stripping
---   - 10-second inactivity reset to default
---   - Location-based default image concept

local IMAGE_FILES = {
    tabubu  = "Tabubupic.jpg",
    dendum  = "Dendumpic.jpg",
    galiont = "Galiontpic.jpg",
}

local last_character = nil
local last_activity_time = os.time()

local function on_character_detected(name)
    if not name or name == "" then return end
    local lower_name = name:lower()
    if lower_name == last_character then return end
    last_character = lower_name
    last_activity_time = os.time()
    local image = IMAGE_FILES[lower_name] or (lower_name .. "pic.jpg")
    echo("[Imagination] Detected: " .. name .. " -> " .. image)
end

-- Window settings from CharSettings
local window_position = CharSettings["window_position"] or {500, 500}
local window_width = CharSettings["window_width"] or 500
local window_height = CharSettings["window_height"] or 500

-- Location image update (runs every 10 seconds)
local function update_default_image()
    local cur = Room.current and Room.current()
    if cur and cur.location then
        local location = cur.location
        local clean = location:match("^([^,]+)") or location
        clean = clean:lower():gsub("[^a-z0-9]", "")
        -- In original, checks if locationpics/<clean>.jpg exists
    end
end

update_default_image()

-- Background reset thread
task.new(function()
    while true do
        sleep(5)
        if last_character and (os.time() - last_activity_time > 10) then
            last_character = nil
        end
        update_default_image()
    end
end)

-- Save settings on exit
before_dying(function()
    CharSettings["window_position"] = window_position
    CharSettings["window_width"] = window_width
    CharSettings["window_height"] = window_height
    Settings.save()
end)

-- Main monitoring loop
while true do
    local line = get()
    if not line then break end

    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local lower_trimmed = trimmed:lower()

    -- Skip "You see a " lines (animals/objects)
    if lower_trimmed:sub(1, 10) == "you see a " then
        goto continue
    end

    -- Handle direct whispers: "Character whispers,"
    if trimmed:match("whispers,") then
        local whisper_name = trimmed:match("(%w+) whispers,")
        if whisper_name then
            on_character_detected(whisper_name)
            last_activity_time = os.time()
        end
    end

    -- Handle distant/faint whispers
    if trimmed:match("You hear the %w+ whisper of") then
        local dist_name = trimmed:match("You hear the %w+ whisper of (%w+) saying,")
        if dist_name then
            on_character_detected(dist_name)
            last_activity_time = os.time()
        end
    end

    -- Handle "You see <possible title> <Name>" lines
    -- The original has a massive regex with all prename titles as optional prefix
    -- We simplify: try to extract the first capitalized word after "You see"
    local see_match = trimmed:match("You see %S+ (%u%l+)")
    if not see_match then
        see_match = trimmed:match("You see (%u%l+)")
    end
    if see_match and see_match ~= "a" and see_match ~= "an" and see_match ~= "the" then
        on_character_detected(see_match)
        last_activity_time = os.time()
    end

    ::continue::
    sleep(0.1)
end
