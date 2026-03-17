--- @revenant-script
--- name: lp
--- version: 1.1.0
--- author: Peggyanne
--- game: gs
--- tags: locate, person, spell 116, voln sight
--- description: Locate a person using spell 116 or Symbol of Sight with town identification
---
--- Original Lich5 authors: Peggyanne, Daedeus
--- Ported to Revenant Lua from lp.lic v1.1.0
---
--- Usage:
---   ;lp <person>          - locate using spell 116
---   ;lp sight <person>    - locate using Symbol of Sight
---   ;lp help              - show help

local function show_help()
    respond("LP Version: 1.1.0")
    respond("")
    respond("   ;lp sight <person>    Locate using Symbol of Sight")
    respond("   ;lp <person>          Locate using spell 116")
    respond("")
    respond("   ~Peggyanne")
end

local args = Script.current.vars

if not args[1] or args[1] == "help" or args[1] == "?" then
    show_help()
    return
end

local TOWN_PATTERNS = {
    { "The foliage ends abruptly at an expansive cemetery", "in Wehnimer's Landing" },
    { "metallic features illuminated by a nearby lava tube", "in Teras" },
    { "enormous lake that randomly ripples", "in Ta'Vaalor" },
    { "shrines that gleam only slightly less", "in Ta'Illistim" },
    { "Fishing boats and lobster pots", "in Solhaven" },
    { "dull red glow of eerie, equine eyes", "in Shadow Valley" },
    { "vessels of ill%-repute as they turn to port", "in River's Rest" },
    { "tantalize the edges of your vision and spiral", "in The Rift" },
    { "shadowy mass of land can be seen through", "in The Settlement of Reim" },
    { "nestled in the few trees that survive", "in Pinefar" },
    { "shadows of the aging forest", "in The Old City of Ta'Faendryl" },
    { "foliage ripples like waves as the wind batters", "in Mist Harbor" },
    { "waters beneath the ships glitter like a bright blue sapphire", "in Kraken's Fall" },
    { "abandoned structures only slightly paler than the ice", "in Icemule or nearby" },
    { "prismatic rainbow in the gentle mists", "in Cysaegir" },
    { "haunted cries of jackals and the clacking", "in The Broken Lands" },
    { "blur of the countryside as you soar", "Flying on a griffin" },
    { "bright yellow canary chases after it", "in or near Zul Loggoth" },
    { "resplendent cities, and tangled jungles", "on trail to Solhaven or Zul Loggoth" },
}

local use_sight = args[1]:lower() == "sight"
local target = use_sight and args[2] or args[1]

if not target then
    show_help()
    return
end

local command
if use_sight then
    command = "symbol of sight " .. target
else
    fput("release")
    fput("prep 116")
    command = "cast " .. target
end

local cast = dothistimeout(command, 5,
    "armor prevents|can't seem to make the link|no picture comes to mind|unseen force|Cast at what|distance is too great|same room with you|%(%-?%d+%)|blur of the countryside|bright yellow canary|resplendent cities|foliage ends abruptly|metallic features|enormous lake|shrines that gleam|Fishing boats|dull red glow|vessels of ill|tantalize the edges|shadowy mass|nestled in the few|shadows of the aging|foliage ripples|waters beneath|abandoned structures|prismatic rainbow|haunted cries")

if not cast then
    respond("No response from locate attempt.")
    return
end

if cast:find("armor prevents") then
    respond("Armor hindrance prevents the spell.")
elseif cast:find("unseen force") then
    respond("Player is using unpresence.")
elseif cast:find("Cast at what") then
    respond("Player is hidden, buried, or no longer logged in.")
elseif cast:find("same room with you") then
    respond("Player is in the room with you!")
elseif cast:find("distance is too great") then
    respond("Player is out of range of Symbol of Sight.")
elseif cast:find("can't seem to make the link") or cast:find("no picture comes to mind") then
    respond("Player is not a member of The Order of Voln.")
else
    -- Check town patterns
    for _, pat in ipairs(TOWN_PATTERNS) do
        if cast:find(pat[1]) then
            respond("Player is out of range. They are currently " .. pat[2])
            return
        end
    end
    -- Check for room ID
    local room_id = cast:match("%(%-?(%d+)%)")
    if room_id then
        local room = Room["u" .. room_id]
        if room then
            respond("Player is in: " .. (room.title or "?") .. " in " .. (room.location or "?") .. " | Room #: " .. (room.id or "?"))
        else
            respond("Player located at room UID: " .. room_id)
        end
    end
end
