--- @revenant-script
--- name: sammu
--- version: 1.2
--- author: spiffyjr
--- contributors: Elanthia-Online
--- game: gs
--- description: Ammunition fletching script for arrows, bolts, and darts
--- tags: ammo,ammunition,fletching,crafting
---
--- Changelog (from Lich5):
---   v1.2 - Update for Ruby v3 compatibility
---   v1.1 - updates to support GTK3
---   v1.0 - Initial release

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local settings = {}

local function smsg(msg, bold)
    if bold then
        put("\n[SAmmu] " .. msg)
    else
        put("[SAmmu] " .. msg)
    end
end

local function convert_to_string(item)
    if type(item) == "number" then
        return "#" .. tostring(item)
    end
    return tostring(item)
end

local function holding(item)
    item = tostring(item)
    local right = GameObj.right_hand
    local left = GameObj.left_hand
    if right and (tostring(right.id) == item or right.noun == item or right.name == item) then return true end
    if left and (tostring(left.id) == item or left.noun == item or left.name == item) then return true end
    return false
end

local function get_inventory(sack)
    for _, inv in ipairs(GameObj.inv) do
        if Regex.test(inv.name, "^" .. sack .. "$") or Regex.test(inv.noun, "\\b" .. sack .. "\\b") then
            return inv
        end
    end
    return nil
end

local function get_inventory_id(sack)
    local inv = get_inventory(sack)
    return inv and tonumber(inv.id) or 4
end

local function get_item(item, sack)
    if holding(item) then return nil end
    waitrt()
    item = convert_to_string(item)

    local line = "get " .. item
    if sack then
        if type(sack) ~= "number" then
            local found = get_inventory_id(sack)
            if found ~= 4 then sack = found end
        end
        sack = convert_to_string(sack)
        line = line .. " from " .. sack
    end

    local res = fput(line)
    if res and (string.find(res, "You pick") or string.find(res, "You get") or string.find(res, "You remove")) then
        return res
    end
    if holding(item) then return "holding" end
    return nil
end

local function put_item(item, sack)
    if not holding(item) then return nil end
    waitrt()
    item = convert_to_string(item)

    local line
    if not sack then
        line = "stow " .. item
    else
        line = "put " .. item .. " in "
        if type(sack) ~= "number" then
            local found = get_inventory_id(sack)
            if found ~= 4 then sack = found end
        end
        sack = convert_to_string(sack)
        line = line .. sack
    end

    local res = fput(line)
    if res and string.find(res, "closed") then
        fput("open " .. sack)
        res = put_item(item, sack)
        fput("close " .. sack)
    end
    if holding(item) then return nil end
    return res
end

local function go2(room)
    if Room.current and tostring(Room.current.id) == tostring(room) then return end
    waitrt()
    run_script("go2", { tostring(room), "_disable_confirm_" })
end

--------------------------------------------------------------------------------
-- SAmmu class equivalent
--------------------------------------------------------------------------------

local shaft = nil
local state = "pare"
local count = 0
local fletch_mode = "normal"

local function load_settings()
    settings = CharSettings.to_hash and CharSettings.to_hash() or {}
    -- Ensure defaults for commonly used keys
    local defaults = {
        knife = "", axe = "", product = "arrow", cap = "",
        weapon_ready = "", weapon_store = "",
        band_paint_one = "", band_paint_two = "", shaft_paint = "",
        woodsack = "", donesack = "", wastesack = "", knifesack = "",
        axesack = "", gluesack = "", fletchingsack = "", capsack = "",
        paintsack = "", scribesack = "", drillsack = "",
        order_room = "", fletch_room = "",
        fletch_room_enter = "", fletch_room_exit = "",
        waste_room = "", waste_room_enter = "", waste_room_exit = "", waste_command = "",
        buy_wood_order = "", buy_wood_count = "",
        mind_pause = "", mind_exit = "",
    }
    for k, v in pairs(defaults) do
        if not settings[k] or settings[k] == "" then
            settings[k] = v
        end
    end
end

local function empty_hand(hand)
    waitrt()
    local item
    if hand == "left" then
        item = GameObj.left_hand
    else
        item = GameObj.right_hand
    end
    if not item or not item.noun then return end

    local noun = item.noun
    if Regex.test(noun, "shaft|wood") then
        put_item(tonumber(item.id), settings.woodsack)
    elseif Regex.test(noun, "bow|cross|dart") then
        fput(settings.weapon_store)
    elseif Regex.test(noun, "fletching") then
        put_item(tonumber(item.id), settings.fletchingsack)
    elseif Regex.test(noun, "glue") then
        put_item(tonumber(item.id), settings.gluesack)
    elseif Regex.test(noun, "drill") then
        put_item(tonumber(item.id), settings.drillsack)
    elseif Regex.test(noun, "scribe") then
        put_item(tonumber(item.id), settings.scribesack)
    elseif Regex.test(noun, "paint") then
        put_item(tonumber(item.id), settings.paintsack)
    elseif Regex.test(noun, "cap") then
        put_item(tonumber(item.id), settings.capsack)
    elseif Regex.test(noun, "arrow|bolt|dart") then
        fput("put #" .. item.id .. " in " .. settings.product .. "s in " .. settings.donesack)
        if holding(item.noun) then
            put_item(tonumber(item.id), settings.donesack)
        end
    elseif settings.knife ~= "" and Regex.test(noun, settings.knife) then
        put_item(tonumber(item.id), settings.knifesack)
    elseif settings.axe ~= "" and Regex.test(noun, settings.axe) then
        put_item(tonumber(item.id), settings.axesack)
    end
end

local function empty_hands()
    empty_hand("left")
    empty_hand("right")
end

local function save_shaft()
    shaft = nil
    local right = GameObj.right_hand
    local left = GameObj.left_hand
    if right and right.noun and Regex.test(right.noun, "shaft") then shaft = right end
    if left and left.noun and Regex.test(left.noun, "shaft") then shaft = left end
end

local function crash(msg)
    smsg("-- sorry, a fatal error has occured", true)
    smsg(msg)
    error(msg)
end

local function buy(item)
    local order, cnt
    if Regex.test(item, "arrowhead|cap") then
        order = settings.buy_cap_order
        cnt = settings.buy_cap_count
    else
        order = settings["buy_" .. item .. "_order"]
        cnt = settings["buy_" .. item .. "_count"]
    end

    if not order or order == "" then crash("missing order data for item: " .. item) end
    if not cnt or cnt == "" then crash("missing order count data for item: " .. item) end

    empty_hands()

    -- Exit fletch room
    if settings.fletch_room_exit and settings.fletch_room_exit ~= "" then
        for cmd in string.gmatch(settings.fletch_room_exit, "[^,]+") do
            fput(cmd:match("^%s*(.-)%s*$"))
        end
    end

    go2("bank")
    fput("withdraw 10000 silver")

    go2(settings.order_room)

    local sack
    if Regex.test(item, "paint") then
        sack = settings.paintsack
    else
        sack = settings[item .. "sack"]
    end

    for _ = 1, tonumber(cnt) do
        fput("order " .. order)
        fput("buy")
        local right = GameObj.right_hand
        if right and right.id then
            put_item(tonumber(right.id), sack)
        end
    end

    empty_hands()

    go2("bank")
    fput("deposit all")

    go2(settings.fletch_room)
    if settings.fletch_room_enter and settings.fletch_room_enter ~= "" then
        for cmd in string.gmatch(settings.fletch_room_enter, "[^,]+") do
            fput(cmd:match("^%s*(.-)%s*$"))
        end
    end
end

local function get_and_buy(item)
    save_shaft()

    if not get_item(item, settings[item .. "sack"]) then
        buy(item)
        if not get_item(item, settings[item .. "sack"]) then
            crash("Could not locate your " .. item .. "!")
        end
    end

    if shaft and shaft.id and not holding("shaft") then
        get_item(tonumber(shaft.id))
    end

    local right = GameObj.right_hand
    if right and right.name and string.find(right.name, item) then return right end
    local left = GameObj.left_hand
    if left and left.name and string.find(left.name, item) then return left end
    return nil
end

local function get_shaft()
    if shaft then
        get_item(tonumber(shaft.id))
        return
    end

    if not get_item("1 my shaft", settings.woodsack) then
        -- Try to get wood and cut a shaft
        if not get_item("wood", settings.woodsack) then
            buy("wood")
            if not get_item("wood", settings.woodsack) then
                crash("Failed to buy wood!")
            end
        end

        if not get_item(settings.axe, settings.axesack) then
            crash("Unable to locate your axe")
        end

        local prod_type = "arrow"
        if fletch_mode ~= "rank" and settings.product ~= "" then
            prod_type = settings.product
        end

        fput("cut " .. prod_type .. " shaft from my wood")
        empty_hands()

        if not get_item("1 shaft", settings.woodsack) then
            crash("Out of shafts and buying failed")
        end
    end
end

local function knife_command(cmd, _match_pattern)
    if not holding(settings.knife) then
        if not get_item(settings.knife, settings.knifesack) then
            crash("Unable to locate your knife!")
        end
    end

    local right = GameObj.right_hand
    local left = GameObj.left_hand
    return fput(cmd .. " #" .. right.id .. " with #" .. left.id)
end

local function bundle()
    empty_hands()

    local quiver = nil
    for _, inv in ipairs(GameObj.inv) do
        if inv.name and Regex.test(inv.name, settings.donesack) then
            quiver = inv
            break
        end
    end
    if not quiver then return end

    fput("look in #" .. quiver.id)
    pause(0.5)

    if quiver.contents then
        for _, item in ipairs(quiver.contents) do
            if item.name and Regex.test(item.name, settings.product) then
                fput("get #" .. item.id)
                if GameObj.left_hand and GameObj.left_hand.id and GameObj.right_hand and GameObj.right_hand.id then
                    fput("bundle")
                end
            end
        end
    end

    empty_hands()
end

local function finish()
    bundle()
    shaft = nil
    count = count - 1
    smsg("-- you have " .. count .. " more to make")
end

local function check_state()
    if GameObj.left_hand and GameObj.left_hand.id then
        empty_hand("left")
    end

    local right_name = GameObj.right_hand and GameObj.right_hand.name or ""
    if not Regex.test(right_name, "shaft") then
        empty_hand("right")
        get_shaft()
    end

    local res = fput("look at my shaft")
    if not res then
        state = "pare"
    elseif string.find(res, "drilled") then
        state = "cap"
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "fletched") then
        state = "whittle"
        if settings.cap ~= "" then
            if Regex.test(settings.cap, "arrowhead") then state = "drill"
            elseif Regex.test(settings.cap, "cap") then state = "cap"
            end
        end
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "cut to length") then
        state = "fletch"
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "nocked") or string.find(res, "cut with nocks") then
        state = "measure_and_cut"
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "a single %w+ band") then
        state = "nock"
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "covers the shaft") then
        state = "nock"
        if fletch_mode == "rank" then state = "waste" end
    elseif string.find(res, "pared down and smoothed") then
        state = "nock"
        if settings.product and Regex.test(settings.product:match("^%s*(.-)%s*$"), "dart") then
            state = "measure_and_cut"
        end
    else
        state = "pare"
    end

    smsg("-- current state: " .. state, true)
end

-- State handlers
local state_handlers = {}

function state_handlers.pare()
    knife_command("cut")
end

function state_handlers.nock()
    local res = knife_command("cut nock in")
    if res and string.find(res, "Generally") then
        return state_handlers.nock()
    end
end

function state_handlers.measure_and_cut()
    fput(settings.weapon_ready)
    local left = GameObj.left_hand
    if not left or not Regex.test(left.noun or "", "bow|dart|cross") then
        crash("Could not locate your weapon!")
    end
    local right = GameObj.right_hand
    fput("measure #" .. right.id .. " with #" .. left.id)
    empty_hand("left")
    knife_command("cut")
end

function state_handlers.fletch()
    local glue = get_and_buy("glue")
    if not glue then return end

    fput("put #" .. glue.id .. " on #" .. (shaft and shaft.id or GameObj.right_hand.id))

    put_item(tonumber(glue.id), settings.gluesack)

    local fletching = get_and_buy("fletching")
    if not fletching then return end

    local res = fput("put #" .. fletching.id .. " on #" .. (shaft and shaft.id or GameObj.right_hand.id))
    if not res then
        empty_hands()
        shaft = nil
        return
    end

    put_item(tonumber(fletching.id), settings.fletchingsack)

    -- Wait for glue to dry
    local start_time = os.time()
    while true do
        local line = get()
        if line and string.find(line, "The glue on your .* shaft has dried") then break end
        if os.time() - start_time > 30 then break end
    end
end

function state_handlers.cap()
    local cap = get_and_buy(settings.cap)
    if cap then
        fput("turn #" .. cap.id)
    end
    finish()
end

function state_handlers.drill()
    get_item("drill", settings.drillsack)
    local res = fput("turn my drill")
    if not res then
        crash("failed to drill shaft")
    end
end

function state_handlers.whittle()
    local res = knife_command("cut")
    if res and string.find(res, "If you cut this now") then
        return state_handlers.whittle()
    end
    finish()
end

function state_handlers.waste()
    if not put_item("shaft", settings.wastesack) then
        if settings.fletch_room_exit and settings.fletch_room_exit ~= "" then
            for cmd in string.gmatch(settings.fletch_room_exit, "[^,]+") do
                fput(cmd:match("^%s*(.-)%s*$"))
            end
        end
        go2(settings.waste_room)
        if settings.waste_room_enter and settings.waste_room_enter ~= "" then
            for cmd in string.gmatch(settings.waste_room_enter, "[^,]+") do
                fput(cmd:match("^%s*(.-)%s*$"))
            end
        end

        while true do
            if holding("shaft") then fput(settings.waste_command) end
            fput("get shaft from " .. settings.wastesack)
            if not holding("shaft") then break end
        end

        if settings.waste_room_exit and settings.waste_room_exit ~= "" then
            for cmd in string.gmatch(settings.waste_room_exit, "[^,]+") do
                fput(cmd:match("^%s*(.-)%s*$"))
            end
        end
        go2(settings.fletch_room)
        if settings.fletch_room_enter and settings.fletch_room_enter ~= "" then
            for cmd in string.gmatch(settings.fletch_room_enter, "[^,]+") do
                fput(cmd:match("^%s*(.-)%s*$"))
            end
        end
    end
end

local function check_mind()
    local pause_percent
    if settings.mind_pause and settings.mind_pause:match("^%s*(.-)%s*$") == "auto" then
        local line = fput("art skil")
        local cur_ranks = 0
        if line then
            local ranks = Regex.match(line, "In the skill of fletching, you are a .* with (\\d+) ranks\\.")
            if ranks and ranks[1] then cur_ranks = tonumber(ranks[1]) end
        end

        if cur_ranks == 500 then
            echo("-- congrats, you mastered!")
            return false
        end

        local total_mind = 800 + (Stats.log and Stats.log[1] or 0) + (Stats.dis and Stats.dis[1] or 0)
        pause_percent = ((total_mind - (cur_ranks + 1)) / total_mind) * 100
    else
        pause_percent = tonumber(settings.mind_pause) or 100
    end

    while true do
        local pm = GameState.percentmind or 0
        if settings.mind_exit then
            local me = settings.mind_exit:match("^%s*(.-)%s*$")
            if me == "bigshot" then
                -- Exit if mind is low enough for bigshot
                if pm < 80 then return false end
            elseif tonumber(me) and pm < tonumber(me) then
                return false
            end
        end

        if pm <= pause_percent then break end

        smsg("Waiting on mind, current: " .. pm .. "% continue at: " .. math.floor(pause_percent) .. "%", true)
        pause(60)
    end
    return true
end

local function fletch(cnt, mode)
    fletch_mode = mode or "normal"
    count = cnt or 1

    while true do
        waitrt()

        if not check_mind() then return end
        check_state()

        local handler = state_handlers[state]
        if handler then
            handler()
        else
            smsg("Unknown state: " .. state)
            break
        end

        if count <= 0 then break end
    end
end

local function refill(refill_type, refill_count)
    if not refill_type then
        smsg("-- please specify buy or fletch", true)
        smsg("-- ;sammu refill [buy|fletch]", true)
        return
    end

    smsg("-- Refilling ammo to " .. refill_count, true)

    local quiver = nil
    for _, inv in ipairs(GameObj.inv) do
        if inv.name and Regex.test(inv.name, settings.donesack) then
            quiver = inv
            break
        end
    end
    if not quiver then return end

    fput("look in #" .. quiver.id)
    pause(0.5)

    local arrows = 0
    if quiver.contents then
        for _, item in ipairs(quiver.contents) do
            if item.name and string.find(item.name, "bundle of") and string.find(item.name, settings.product) then
                local look_line = fput("look at #" .. item.id)
                if look_line then
                    local m = Regex.match(look_line, "carefully count the .* and find (\\d+) in the bundle|you quickly count (\\d+) of them")
                    if m and m[1] then arrows = arrows + tonumber(m[1]) end
                end
            elseif item.name and Regex.test(item.name, settings.product) then
                arrows = arrows + 1
            end
        end
    end

    if (refill_count - arrows) <= 0 then return end

    smsg("-- You need " .. (refill_count - arrows) .. " more arrows", true)

    if refill_type == "fletch" then
        fletch(refill_count - arrows)
    elseif refill_type == "buy" then
        local bundle_count = math.floor((refill_count - arrows) / 20)
        if bundle_count < 1 then return end
        go2("bank")
        fput("withdraw " .. (bundle_count * 100) .. " silvers")
        go2(settings.order_room)

        for _ = 1, bundle_count do
            fput("order " .. settings.buy_arrows)
            fput("buy")
            local right = GameObj.right_hand
            if right and right.id then
                put_item(tonumber(right.id), settings.donesack)
            end
        end

        go2("bank")
        fput("deposit all")
        go2(settings.fletch_room)

        bundle()
    end
end

local function show_help()
    smsg("SAmmu", true)
    respond(string.format("%17s: SpiffyJr <spiffyjr@gmail.com>", "Author"))
    respond(string.format("%17s: SAmmu is the only fletching script you will ever need!", "Description"))
    respond("")
    respond(string.format("%17s     %s", "help, ?", "show this help message"))
    respond(string.format("%17s     %s", "setup", "run the configuration (set CharSettings manually)"))
    respond("")
    respond(string.format("%17s     %s", "bundle", "attempts to bundle your ammunition"))
    respond(string.format("%17s     %s", "refill", "refills ammo to amount using method specified"))
    respond("")
    respond(string.format("%17s     %s", "rank", "runs in rank-up mode"))
    respond(string.format("%17s     %s", "#", "runs in regular mode fletching # product(s)"))
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

load_settings()

local args = Script.args or {}
local cmd = args[1]

if not cmd or cmd == "" then
    smsg("-- you're doing it wrong!", true)
    show_help()
    return
end

-- Cleanup on exit
on_exit(function()
    empty_hands()
end)

if cmd == "bundle" then
    smsg("-- Bundling", true)
    bundle()
elseif cmd == "refill" then
    refill(args[2], tonumber(args[3]) or 0)
elseif cmd == "setup" then
    smsg("-- Setup: use CharSettings to configure SAmmu keys", true)
    smsg("-- Keys: knife, axe, product, cap, woodsack, donesack, etc.", true)
elseif Regex.test(cmd, "^rank") then
    smsg("-- Running in rank mode", true)
    fletch(9999, "rank")
elseif Regex.test(cmd, "^%d+$") then
    smsg("-- Running in normal mode", true)
    fletch(tonumber(cmd))
elseif cmd == "help" or cmd == "?" then
    show_help()
end
