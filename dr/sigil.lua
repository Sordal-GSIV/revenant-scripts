--- @revenant-script
--- name: sigil
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Harvest sigils from attunement rooms.
--- tags: magic, sigils, attunement
--- Converted from sigil.lic

local settings = get_settings()
local hometown = settings.hometown or "Crossing"
local attunement_rooms = settings.attunement_rooms or {}
local timer = settings.sigil_timer or 240

if #attunement_rooms == 0 then
    local town_data = get_data("town")
    if town_data[hometown] and town_data[hometown].attunement_rooms then
        attunement_rooms = town_data[hometown].attunement_rooms
    end
end

local start_timer = os.time()
for _, room_id in ipairs(attunement_rooms) do
    local dead_room = false
    DRC.bput("get my burin", "You get", "You are already")
    DRC.bput("get my scrolls", "You get", "You are already", "You pick up")
    DRCT.walk_to(room_id)
    local result = DRC.bput("perceive sigil", "Almost obscured", "Sorting through",
        "After much scrutiny", "Subtleties", "Though the seemingly", "In your mind",
        "Roundtime", "Having recently")
    if result and result:find("Having recently") then dead_room = true end
    if not dead_room then
        DRC.bput("scribe sigil", "You need", "You carefully scribe")
        waitrt()
        DRC.bput("stow burin", "You put")
        DRC.bput("get sigil book", "You get")
        DRC.bput("put sigil in sigil book", "You add", "You rearrange", "completely full")
        DRC.bput("stow sigil book", "You put")
    end
    if os.time() - start_timer > timer then break end
end
