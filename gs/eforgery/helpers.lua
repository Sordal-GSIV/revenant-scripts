--- eforgery helper utilities
-- Container get/put, banking, note management, wastebin, apron, empty_hands
local data = require("eforgery/data")
local M = {}

-- Module-level references set by wire()
local state   -- runtime state table (settings, counters, note, wastebin, etc.)

function M.wire(deps)
    state = deps.state
end

---------------------------------------------------------------------------
-- Messaging
---------------------------------------------------------------------------

function M.info(text)
    respond("[eforgery] " .. text)
end

function M.dbg(text)
    if state and state.debug then
        respond("[eforgery:debug] " .. text)
    end
end

function M.warn(text)
    respond("[eforgery] WARNING: " .. text)
end

---------------------------------------------------------------------------
-- you_get — retrieve an item from a container (handles open/close)
---------------------------------------------------------------------------

function M.you_get(item, container)
    M.dbg("you_get(" .. tostring(item) .. ", " .. tostring(container) .. ")")

    if container then
        -- check if already in hand
        local rh = GameObj.right_hand()
        local lh = GameObj.left_hand()
        if (rh and rh.noun == item) or (lh and lh.noun == item) then
            M.dbg("item found in hand already")
            return true
        end

        local closed = false
        local line = nil
        while true do
            fput("get " .. item .. " from " .. container)
            line = matchtimeout(5, "You remove", "You grab", "It's closed", "Get what")
            if not line then return false end
            if line:find("It's closed") then
                closed = true
                fput("open " .. container)
            else
                break
            end
        end
        if closed then fput("close " .. container) end
        return (line and (line:find("You remove") or line:find("You grab"))) and true or false
    else
        fput("get my " .. item)
        local line = matchtimeout(5, "You remove", "You grab", "It's closed", "Get what")
        return (line and (line:find("You remove") or line:find("You grab"))) and true or false
    end
end

---------------------------------------------------------------------------
-- you_put — put an item in a container (handles open/close)
---------------------------------------------------------------------------

function M.you_put(item, container)
    M.dbg("you_put(" .. tostring(item) .. ", " .. tostring(container) .. ")")
    local closed = false
    local line = nil
    while true do
        fput("put " .. item .. " in " .. container)
        line = matchtimeout(5, "You put", "You tuck", "It's closed", "won't fit")
        if not line then return false end
        if line:find("won't fit") then
            M.warn("Container full — " .. container)
            return false
        elseif line:find("It's closed") then
            closed = true
            fput("open " .. container)
        else
            break
        end
    end
    if closed then fput("close " .. container) end
    return true
end

---------------------------------------------------------------------------
-- empty_hands / empty_right_hand / empty_left_hand
---------------------------------------------------------------------------

function M.empty_hands()
    waitrt()
    if checkright() then fput("stow right") end
    if checkleft() then fput("stow left") end
end

function M.empty_right_hand()
    if checkright() then fput("stow right") end
end

function M.empty_left_hand()
    if checkleft() then fput("stow left") end
end

---------------------------------------------------------------------------
-- Wastebin — find nearest town trash receptacle via pathfinding
---------------------------------------------------------------------------

function M.find_wastebin()
    M.dbg("find_wastebin")
    local current = Map.current_room()
    if not current then
        state.wastebin = "bin"
        return
    end

    local best_bin = nil
    local best_cost = nil
    for _, town_info in pairs(data.TARGETS) do
        local cost = Map.path_cost(current, town_info.town)
        if cost and (not best_cost or cost < best_cost) then
            best_cost = cost
            best_bin = town_info.wastebin
        end
    end
    state.wastebin = best_bin or "bin"
    M.dbg("wastebin set to: " .. state.wastebin)
end

---------------------------------------------------------------------------
-- Apron management
---------------------------------------------------------------------------

function M.wear_apron()
    M.dbg("wear_apron")
    local found = false
    for _, item in ipairs(GameObj.inv()) do
        if item.noun == "apron" then found = true; break end
    end
    if not found then
        multifput("get my apron", "wear my apron")
        -- check again
        found = false
        for _, item in ipairs(GameObj.inv()) do
            if item.noun == "apron" then found = true; break end
        end
        if not found then
            M.get_apron()
            multifput("get my apron", "wear my apron")
        end
    end
end

function M.get_apron()
    M.dbg("get_apron")
    fput("stow all")
    M.bank(1000)
    M.buy(1)
end

---------------------------------------------------------------------------
-- Hammer — ensure forging-hammer is in right hand
---------------------------------------------------------------------------

function M.hammer_time()
    M.dbg("hammer_time")
    waitrt()
    if checkleft("forging-hammer") then
        fput("swap")
    end
    while not checkright("forging-hammer") do
        -- check if worn
        local worn = false
        for _, item in ipairs(GameObj.inv()) do
            if item.noun == "forging-hammer" then worn = true; break end
        end
        if checkright() then fput("stow right") end
        local cmd = worn and "remove my forging-hammer" or "get my forging-hammer"
        if not checkright("forging-hammer") then
            fput(cmd)
        end
        -- safety break
        if checkright("forging-hammer") then break end
        pause(0.5)
    end
end

---------------------------------------------------------------------------
-- Rent — ensure workshop access
---------------------------------------------------------------------------

function M.rent()
    M.dbg("rent")
    if not checkroom("Workshop") then
        fput("go workshop")
        local line = matchtimeout(10, "rentals", "remaining", "collects")
        if line and line:find("don't have enough") then
            M.bank(data.RENT)
            move("go workshop")
        end
    end
end

---------------------------------------------------------------------------
-- Banking — ensure we have enough silver
---------------------------------------------------------------------------

function M.bank(silver_needed)
    M.dbg("bank(" .. tostring(silver_needed) .. ")")
    M.dbg("Current silver: " .. tostring(Currency.silver))
    if Currency.silver >= silver_needed then return end

    waitrt()
    Script.run("go2", "bank")
    M.withdraw(silver_needed)
    Script.run("go2", "forge")
end

function M.withdraw(silver_needed)
    M.dbg("withdraw(" .. tostring(silver_needed) .. ")")
    local need = silver_needed - Currency.silver
    if need > 0 then
        fput("withdraw " .. need .. " silver")
        local line = matchtimeout(10, "makes a few marks", "carefully records the transaction",
            "scribbles the transaction", "don't seem to have that much")
        if line and line:find("don't seem to have") then
            M.warn("Insufficient bank funds!")
            error("Insufficient bank funds")
        end
    end
end

---------------------------------------------------------------------------
-- Promissory note management
---------------------------------------------------------------------------

function M.is_note(item)
    if not item then return false end
    for _, name in ipairs(data.NOTE_NAMES) do
        if item.name and name:find(item.name, 1, true) then return true end
    end
    return false
end

function M.read_note()
    M.dbg("read_note")
    if not state.note then return nil end
    local lines = quiet_command("read #" .. state.note.id, "Hold in right hand to use", nil, 5)
    for _, l in ipairs(lines or {}) do
        local val = l:match("has a value of ([%d,]+) silver")
        if val then
            return tonumber(val:gsub(",", ""))
        end
    end
    return nil
end

function M.get_note(amt)
    M.dbg("get_note(" .. tostring(amt) .. ")")
    local need_note = false

    -- search inventory for existing note
    state.note = nil
    for _, item in ipairs(GameObj.inv()) do
        local contents = item.contents
        if contents then
            for _, sub in ipairs(contents) do
                if M.is_note(sub) then
                    state.note = sub
                    M.dbg("Found note: " .. sub.name)
                    break
                end
            end
            if state.note then break end
        end
    end

    if state.note then
        M.dbg("Checking note amount")
        fput("get #" .. state.note.id)
        local note_amount = M.read_note()
        if not note_amount or note_amount < amt then
            need_note = true
        end
    else
        need_note = true
    end

    M.dbg("Need note: " .. tostring(need_note))
    if not need_note then return end

    Script.run("go2", "bank")

    -- v1.3.0: removed deposit all — it resets any existing note
    local withdraw_amt = (amt > state.note_size) and amt or state.note_size
    local result = dothistimeout("withdraw " .. withdraw_amt .. " note", 5,
        "carefully records the transaction", "Very well", "hands you the coins",
        "makes some marks on a blank note", "makes a few scribblings",
        "taps her quill thoughtfully", "scribbles the transaction",
        "seem to have that much")

    if result and result:find("seem to have that much") then
        M.warn("Insufficient funds for note!")
        error("Insufficient funds")
    end

    waitrt()

    -- find the note in hands
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if M.is_note(rh) then state.note = rh
    elseif M.is_note(lh) then state.note = lh end

    -- get rent money while at bank
    M.withdraw(data.RENT)

    Script.run("go2", "forge")
end

function M.clear_note()
    M.dbg("clear_note")
    local rh = GameObj.right_hand()
    local lh = GameObj.left_hand()
    if M.is_note(rh) then fput("stow right")
    elseif M.is_note(lh) then fput("stow left") end
end

---------------------------------------------------------------------------
-- Buy — purchase an item with note payment
---------------------------------------------------------------------------

function M.buy(item, material)
    M.dbg("buy(" .. tostring(item) .. ", " .. tostring(material) .. ")")
    local line = ""
    while not line or not line:find("hands you") do
        local order_cmd
        if material then
            order_cmd = "order " .. item .. " material " .. material
        else
            order_cmd = "order " .. item
        end

        local cost_line = dothistimeout(order_cmd, 10,
            "drop the price to", "silvers")
        if not cost_line then
            M.warn("No response from merchant")
            return
        end

        local cost_str = cost_line:match("(%d[%d,]*)")
        local cost = cost_str and tonumber(cost_str:gsub(",", "")) or 5000

        M.get_note(cost)
        fput("swap")

        -- re-order to confirm
        if material then
            dothistimeout("order " .. item .. " material " .. material, 10,
                "drop the price to", "silvers")
        else
            dothistimeout("order " .. item, 10, "drop the price to", "silvers")
        end

        fput("buy")
        line = matchtimeout(10, "buckle under", "hands you", "do not have")
        if line and line:find("buckle under") then
            M.warn("You're carrying too much.")
            error("Encumbered")
        end

        M.clear_note()
    end
end

---------------------------------------------------------------------------
-- Trash — dispose of an item using the trash verb
---------------------------------------------------------------------------

function M.trash(item)
    M.dbg("trash(" .. tostring(item) .. ")")
    waitrt()
    if checkroom("Forge") then
        move("go door")
        fput("trash my " .. tostring(item))
        move("go door")
    else
        fput("trash my " .. tostring(item))
    end
end

---------------------------------------------------------------------------
-- Scrap — store scrap, sell if full, or trash
---------------------------------------------------------------------------

function M.scrap(item)
    M.dbg("scrap")
    if not item then return end
    if state.scrap_container then
        local closed = false
        local done = false
        while not done do
            fput("put #" .. item.id .. " in " .. state.scrap_container)
            local line = matchtimeout(5, "You put", "You tuck", "It's closed", "won't fit")
            if not line then done = true
            elseif line:find("won't fit") then
                -- container full — sell at pawnshop
                fput("look in my " .. state.scrap_container)
                if checkroom("Workshop") then
                    -- already in workshop
                end
                move("go door")
                move("out")
                Script.run("go2", "pawnshop")
                fput("sell #" .. item.id)
                local sell_line = matchtimeout(5, "then hands you", "basically worthless", "hands it back")
                if sell_line and sell_line:find("then hands you") then
                    -- sell container contents too
                    local box = nil
                    for _, inv_item in ipairs(GameObj.inv()) do
                        if inv_item.noun and inv_item.noun:find(state.scrap_container) then
                            box = inv_item
                            break
                        end
                    end
                    if box and box.contents then
                        for _, obj in ipairs(box.contents) do
                            if obj.name and obj.name:find(state.material_name) and obj.name:find("slab") then
                                multifput("get #" .. obj.id, "sell #" .. obj.id)
                            end
                        end
                    end
                    done = true
                    Script.run("go2", "forge")
                    M.rent()
                elseif sell_line and (sell_line:find("worthless") or sell_line:find("hands it back")) then
                    fput("trash #" .. item.id)
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if (rh and rh.id == item.id) or (lh and lh.id == item.id) then
                        fput("drop #" .. item.id)
                    end
                    M.info("Scrap was worthless, trashed or dropped.")
                    M.warn("Pausing for user review. ;unpause eforgery to continue.")
                    Script.pause()
                    done = true
                end
            elseif line:find("It's closed") then
                closed = true
                fput("open my " .. state.scrap_container)
            else
                done = true
            end
        end
        if closed then fput("close " .. state.scrap_container) end
    else
        M.trash(checkleft() or "left")
    end
end

---------------------------------------------------------------------------
-- Surge of Strength
---------------------------------------------------------------------------

function M.use_surge()
    M.dbg("use_surge")
    CMan.use("surge")
end

---------------------------------------------------------------------------
-- Squelch hook — suppress forge spam
---------------------------------------------------------------------------

function M.install_squelch()
    M.dbg("installing squelch hook")

    local suppress_patterns = {
        "begin pumping to set the wheel spinning",
        "you press it against the spinning stone",
        "dust rises from the spinning wheel as you grind",
        "internal strength fully recovers",
        "begin to lose touch with your internal sources",
        "You swap",
        "you feel pleased with yourself at having cleaned",
        "may order a .* of this item",
        "for your patronage",
        "ask about the price",
        "silvers you offer in payment",
        "sparks leap from the spinning wheel",
        "around you see a grinder that may suit your",
        "focus deep within yourself, searching for untapped sources",
        "feel a great deal stronger",
        "feel fully energetic",
        "you still have some time remaining",
        "press it against the spinning wheel",
        "hum of the spinning wheel and the scent",
        "reducing areas of roughness to a polished",
        "pause to press a tube of diamond dust paste",
        "straighten up from working at the polishing wheel",
        "is using the polisher right",
        "pause to examine both pieces closely",
        "pick up a file and file",
        "decide the safest thing to do now is to",
        "you get to your feet",
        "you set to work assembling your",
        "dip some rendered rolton fat from a small",
        "upon fitting the two pieces together",
        "around you see a trough and a pair of tongs",
        "need it in order to set the temper",
        "pull the drain plug from the tempering trough",
        "the tempering trough is empty nothing happens",
        "lift the bucket from its hook",
        "take the mithril tongs from their place",
        "dull orange glow filling the gaps",
        "darkens with perspiration as the newly awakened heat",
        "takes on the glow from the surrounding",
        "you begin to shape it with your forging",
        "reddish sparks fly in all directions",
        "hammer until the glow has faded",
        "waiting for.*to heat up again",
        "from the forge and resume your work",
        "fall about the base of the anvil",
        "toward its final form as beads of perspiration",
        "you realize that the scribed pattern is gone",
        "wipe sweat from your forehead",
        "sparks fly in all directions as you hammer",
        "dozens of the blue sparks strike the chain",
        "spinning wheel as you grind away",
    }

    DownstreamHook.add("forgesquelch", function(line)
        if not line or line:match("^%s*$") then return nil end

        for _, pat in ipairs(suppress_patterns) do
            if line:find(pat) then return nil end
        end

        -- preserve roundtime from glyph tracing
        local rt_match = line:match("(<roundTime value='[^']*'/>)")
        if rt_match and (line:find("You carefully trace") or line:find("You begin to trace")) then
            return rt_match
        end

        return line
    end)
end

function M.remove_squelch()
    DownstreamHook.remove("forgesquelch")
end

return M
