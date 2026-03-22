--- @revenant-script
--- @lic-certified: complete 2026-03-19
--- name: nautical_charts
--- version: 1.1.0
--- author: Peggyanne
--- game: gs
--- tags: maps, nautical, ocean, sailing, gui, osa
--- description: Interactive nautical chart viewer for OSA ocean navigation with ship tracking
---
--- Original Lich5 authors: Peggyanne
--- Ported to Revenant Lua from nautical-charts.lic v1.0.2
---
--- Usage:
---   ;nautical_charts              Open the interactive map viewer
---   ;nautical_charts update       Update map files from GitHub repos
---
--- Features:
---   - Real-time ship position tracking via UID parsing
---   - Interactive map with zoom and pan
---   - Click on map to identify room IDs
---   - Click room markers to navigate via sail2
---   - Map/scale selection via GUI controls
---
--- Change Log:
---   March 4, 2026  - Initial Release (Peggyanne)
---   March 6, 2026  - Changed Map File Folder Locations And Added Repo Info (Peggyanne)
---   March 14, 2026 - Added Update Option To Remove Nautical-Charts-Update Dependancy (Peggyanne)
---   March 19, 2026 - Ported to Revenant Lua with native GUI map_view widget

no_kill_all()
no_pause_all()

-- If called with "update", delegate to the update script
if Script.vars[1] == "update" then
    Script.run("nautical_charts_update")
    return
end

-- ---------- CONFIG ----------
local MAP_DIR = GameState.map_dir or "maps"
local JSON_PATH = MAP_DIR .. "/OSAMaps/Database/oceandb.json"
local PNG_DIR   = MAP_DIR .. "/OSAMaps/Maps"
local BG_DIR    = MAP_DIR .. "/OSAMaps/Backgrounds"
local ICON_DIR  = MAP_DIR .. "/OSAMaps/Icons"
local SHIP_FILE = "ship_icon.png"
local INITIAL_SCALE = 0.50
local MIN_SCALE = 0.25
local MAX_SCALE = 2.50
local CLICK_THRESHOLD = 15

-- ---------- HELPERS ----------
local function mm_echo(msg)
    respond("[nautical-charts: " .. msg .. "]")
end

--- Search all top-level buckets in the ocean database for a room by ID.
--- @param data table The parsed oceandb JSON
--- @param rid_int number The room ID to search for
--- @return table|nil Room info table or nil
local function find_room(data, rid_int)
    local rid = tostring(rid_int)
    for _, bucket in pairs(data) do
        if type(bucket) == "table" and bucket[rid] then
            return bucket[rid]
        end
    end
    return nil
end

--- Find the room nearest to given image-space coordinates on a specific map.
--- @param data table The parsed oceandb JSON
--- @param map_file string The current map filename
--- @param click_x number Image-space X coordinate
--- @param click_y number Image-space Y coordinate
--- @return string|nil Room ID string or nil
local function find_room_at_coords(data, map_file, click_x, click_y)
    for _, bucket in pairs(data) do
        if type(bucket) == "table" then
            for rid, room_info in pairs(bucket) do
                local rm = room_info.map or room_info.map_file
                if rm == map_file then
                    local dx = (tonumber(room_info.cx) or 0) - click_x
                    local dy = (tonumber(room_info.cy) or 0) - click_y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= CLICK_THRESHOLD then
                        return rid
                    end
                end
            end
        end
    end
    return nil
end

--- List available map PNG files (excluding backgrounds and ship icon).
--- @return table Array of filename strings
local function list_maps()
    local maps = {}
    if not File.is_dir(PNG_DIR) then return maps end
    local files = File.list(PNG_DIR)
    for _, f in ipairs(files) do
        local lower = f:lower()
        if lower:match("%.png$") and not lower:match("_background") and f ~= SHIP_FILE then
            table.insert(maps, f)
        end
    end
    table.sort(maps)
    return maps
end

-- ---------- LOAD DATA ----------
if not File.exists(JSON_PATH) then
    mm_echo("Ocean database not found. Run ;nautical_charts update first.")
    return
end

local json_str = File.read(JSON_PATH)
if not json_str or json_str == "" then
    mm_echo("Failed to read ocean database.")
    return
end

local data = Json.decode(json_str)
if not data then
    mm_echo("Failed to parse ocean database JSON.")
    return
end

-- ---------- STATE ----------
local current_room_id = nil
local current_map_file = nil
local current_cx = nil
local current_cy = nil
local current_scale = INITIAL_SCALE
local map_alive = true

-- Persistent settings via CharSettings (JSON-serialized)
local settings = {}
if CharSettings.nautical_charts then
    local ok, s = pcall(Json.decode, CharSettings.nautical_charts)
    if ok and s then settings = s end
end

local function save_settings()
    CharSettings.nautical_charts = Json.encode(settings)
end

-- ---------- BUILD GUI ----------
local win = Gui.window("Nautical Charts", { width = 500, height = 550, resizable = true })

local root = Gui.vbox()

-- Top toolbar
local toolbar = Gui.hbox()

-- Map selector
local available_maps = list_maps()
local map_options = {}
for _, m in ipairs(available_maps) do
    table.insert(map_options, m)
end
local map_combo = Gui.editable_combo({
    text = "Select Map...",
    hint = "Choose a map",
    options = map_options,
})

-- Scale selector
local scale_options = { "25%", "50%", "75%", "100%", "150%", "200%", "250%" }
local scale_combo = Gui.editable_combo({
    text = "50%",
    hint = "Zoom",
    options = scale_options,
})

-- Center on ship button
local center_btn = Gui.button("Center")

toolbar:add(map_combo)
toolbar:add(scale_combo)
toolbar:add(center_btn)
root:add(toolbar)

-- Status label
local status = Gui.label("Waiting for movement...")
root:add(status)

-- Map view widget
local map_view = Gui.map_view({ width = 480, height = 450 })
root:add(map_view)

win:set_root(root)
win:show()

-- ---------- MAP LOADING ----------

--- Load a map image and optionally its background.
--- @param map_file string The map filename to load
local function load_map(map_file)
    local map_path = PNG_DIR .. "/" .. map_file
    if not File.exists(map_path) then
        mm_echo("Map file not found: " .. map_file)
        return false
    end

    local ok, err = map_view:load_image(map_path)
    if not ok then
        mm_echo("Failed to load map: " .. tostring(err))
        return false
    end

    current_map_file = map_file
    map_view:set_scale(current_scale)
    return true
end

--- Navigate to a room: load its map if needed, place ship marker, center view.
--- @param room_id number The room ID
--- @param force boolean Force reload even if same map
--- @return boolean Success
local function load_room(room_id, force)
    local room = find_room(data, room_id)
    if not room then return false end

    local map_file = room.map or room.map_file
    local cx = tonumber(room.cx)
    local cy = tonumber(room.cy)
    if not map_file or not cx or not cy then return false end

    -- Load new map if needed
    if current_map_file ~= map_file or force then
        if not load_map(map_file) then return false end
        map_combo:set_text(map_file)
    end

    current_room_id = room_id
    current_cx = cx
    current_cy = cy

    -- Place ship marker at room position
    map_view:clear_markers()
    map_view:set_marker(room_id, {
        x = cx,
        y = cy,
        color = "cyan",
        shape = "circle",
    })

    -- Center view on ship
    map_view:center_on(cx, cy)

    -- Update status
    status:set_text("Map: " .. map_file .. " | Room: " .. tostring(room_id))

    return true
end

-- ---------- EVENT HANDLERS ----------

-- Map selector change
map_combo:on_change(function(text)
    -- Find matching map file
    for _, m in ipairs(available_maps) do
        if m == text then
            load_map(m)
            current_room_id = nil
            current_cx = nil
            current_cy = nil
            status:set_text("Map: " .. m .. " | Room: None")
            map_view:clear_markers()
            return
        end
    end
end)

-- Scale selector change
scale_combo:on_change(function(text)
    local pct = tonumber(text:match("(%d+)"))
    if pct then
        current_scale = pct / 100.0
        if current_scale < MIN_SCALE then current_scale = MIN_SCALE end
        if current_scale > MAX_SCALE then current_scale = MAX_SCALE end
        map_view:set_scale(current_scale)
        -- Re-center on ship if we have a position
        if current_cx and current_cy then
            map_view:center_on(current_cx, current_cy)
        end
    end
end)

-- Center button
center_btn:on_click(function()
    if current_room_id then
        load_room(current_room_id, true)
    end
end)

-- Map click handler — receives table {x, y, room_id} from map_view
map_view:on_click(function(event)
    if not current_map_file then return end
    if type(event) ~= "table" then return end

    local click_x = event.x
    local click_y = event.y

    if not click_x or not click_y then return end

    -- Find room at clicked coordinates
    local clicked_rid = find_room_at_coords(data, current_map_file, click_x, click_y)
    if clicked_rid then
        mm_echo("Room ID: " .. clicked_rid .. " — run ;sail2 " .. clicked_rid .. " to navigate")
    end
end)

-- ---------- ROOM TRACKING VIA DOWNSTREAM HOOK ----------
-- Parse XML room name tags for UID-based room tracking.
-- Format: style id="roomName" />...(1234567)

local last_seen_id = nil

DownstreamHook.add("nautical_charts_tracker", function(line)
    if not map_alive then return line end

    -- Match room ID from roomName XML tag
    local rid = line:match('style id="roomName".-%((%d+)%)')
    if rid then
        rid = tonumber(rid)
        if rid then
            local room = find_room(data, rid)
            local room_map = room and (room.map or room.map_file) or nil

            -- Only update if room changed or map needs switching
            if rid ~= last_seen_id or current_map_file ~= room_map then
                if load_room(rid, false) then
                    last_seen_id = rid
                end
            end
        end
    end

    return line  -- pass through, never squelch
end)

-- ---------- CLEANUP ----------
before_dying(function()
    map_alive = false
    DownstreamHook.remove("nautical_charts_tracker")
end)

-- ---------- MAIN LOOP ----------
-- Keep script alive until window is closed
mm_echo("Nautical Charts loaded. Use WATCH OCEAN or LOOK OCEAN for position tracking.")
Gui.wait(win, "close")
mm_echo("Nautical Charts closed.")
