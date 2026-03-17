--- @revenant-script
--- name: puzzlebox
--- version: 1.0.0
--- author: Demandred
--- game: gs
--- tags: puzzle, puzzlebox, automation
--- description: Solve a mithril puzzlebox by analyzing sides and manipulating dials
---
--- Original Lich5 authors: Demandred
--- Ported to Revenant Lua from puzzlebox.lic v1.0
---
--- Usage: ;puzzlebox (hold the puzzlebox first)

put("analyze puzzlebox")

local side_1, side_2, side_3, side_4

while true do
    local line = get()
    local s = line:match("Side%-1 dial: (.+)$")
    if s then side_1 = s end
    s = line:match("Side%-2 dial: (.+)$")
    if s then side_2 = s end
    s = line:match("Side%-3 dial: (.+)$")
    if s then side_3 = s end
    s = line:match("Side%-4 dial: (.+)$")
    if s then side_4 = s; break end
end

dothistimeout("spin puzzlebox", 5, "You place your angular mithril puzzlebox in the palm of your hand and give it a good spin")
wait(0.5)
waitrt()
wait(1)

local sides_match = side_1 .. "|" .. side_2 .. "|" .. side_3 .. "|" .. side_4

local facing_side, current_side

local function get_facing_side()
    local line = dothistimeout("look puzzlebox", 5, "dial is currently")
    if line then
        current_side = line:match("The (.+) dial is currently")
        facing_side = line:match("angled toward the puzzlebox's (.+) dial")
    end
end

local function navigate_to(target_side, angle_side)
    dothistimeout("turn puzzlebox", 5, "dial now facing you")
end

local function flip_and_pull(current, target, side_name)
    get_facing_side()
    if facing_side == target then
        dothistimeout("flip puzzlebox", 5, "You swivel")
    end
    dothistimeout("pull puzzlebox", 5, "makes a soft click")
end

get_facing_side()

-- Navigate side 1 to face you
if current_side == side_2 then
    dothistimeout("turn puzzlebox", 5, "dial now facing you")
elseif current_side == side_3 then
    dothistimeout("turn puzzlebox", 5, "dial now facing you")
    get_facing_side()
    dothistimeout("turn puzzlebox", 5, "dial now facing you")
elseif current_side == side_4 then
    dothistimeout("turn puzzlebox", 5, "dial now facing you")
end

-- Pull sequence
get_facing_side()
if facing_side == side_4 then
    dothistimeout("flip puzzlebox", 5, "You swivel")
end
dothistimeout("pull puzzlebox", 5, "makes a soft click")

get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")

get_facing_side()
if facing_side == side_3 then
    dothistimeout("flip puzzlebox", 5, "You swivel")
end
dothistimeout("pull puzzlebox", 5, "makes a soft click")

get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")
get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")

get_facing_side()
if facing_side == side_1 then
    dothistimeout("flip puzzlebox", 5, "You swivel")
end
dothistimeout("pull puzzlebox", 5, "makes a soft click")

get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")

get_facing_side()
if facing_side == side_2 then
    dothistimeout("flip puzzlebox", 5, "You swivel")
end
dothistimeout("pull puzzlebox", 5, "makes a soft click")

get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")
get_facing_side()
dothistimeout("turn puzzlebox", 5, "dial now facing you")

dothistimeout("push puzzlebox", 5, "pulses as its dials retract")
wait(0.5)
waitrt()
wait(0.5)
dothistimeout("twist puzzlebox", 5, "twists open to reveal")
