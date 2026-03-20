--- @revenant-script
--- name: dr_dig
--- version: 1.0.0
--- author: Alastir
--- game: dr
--- description: Automated Duskruin archaeology digging — loops dig, identifies box quality, loots or discards
--- tags: duskruin, digging, archaeology, loot, automation
---
--- Converted from dr_dig.lic (Lich5) to Revenant Lua
--- Original author: Alastir
---
--- Requires Vars: lootsack, questsack, lootchar (optionally lootchar2)
--- Supporting scripts: dr_dig_watch, duskruin_adventurer, duskruin_archaeologist, moonshardbundle
---
--- NOTE: In Lich5 the $dr_dig_bs / $dr_dig_total Ruby globals were shared with
--- dr_dig_watch via the Ruby runtime's shared global state.  In Revenant each
--- script runs in its own Lua VM.  The counters are stored in CharSettings so
--- dr_dig_watch can read/write them independently:
---   CharSettings.dr_dig_bs    — count of backswings seen by dr_dig_watch
---   CharSettings.dr_dig_total — total digs tracked by dr_dig_watch
---
--- Usage:
---   ;dr_dig   - begin digging loop (run until manually stopped or error)

hide_me()

-- Initialise shared counters in CharSettings if not already set
if not CharSettings.dr_dig_bs    then CharSettings.dr_dig_bs    = "0" end
if not CharSettings.dr_dig_total then CharSettings.dr_dig_total = "0" end

-- F2P troop: characters in this list pass loot to lootchar instead of keeping it
local f2p_troop = Regex.new(
    "Rieti|Rimini|Rindisi|Dobbir|Tackil|Debth|Cflor|Bayte|Bobbir|Sinkur|Pheesh|Toggam")

-- Bin items: these junk items go into the bin rather than the loot sack
local bin_items_re = Regex.new(
    "balenite|coin|hide|jade|leaf|plumille|rhimar|rag|ring|wyrwood")

-- Dig-result patterns for dothistimeout (broad enough to catch all branches)
local dig_patterns = {
    "You begin to dig with your",
    "You continue to dig with your",
    "You reach down and pull",
    "You need your left hand free to help grasp",
    "Perhaps you need a shovel or something similar",
}

-- Compiled regexes for distinguishing dig results
local ornate_re = Regex.new(
    "You reach down and pull (?:an ornate|an elegant|a ruby-set|a bejeweled" ..
    "|an opal-set|a gem-flecked|a gem-studded|a diamond-set|a saewehna-set" ..
    "|a feystone-set|a despanel-set|an emerald-set|a sapphire-set" ..
    "|a sunstone-set|a blazestar-set|a firestone-set|a gem-encrusted" ..
    "|a jewel-studded|a malachite-set|a moonstone-set|a opal-encrusted" ..
    "|a firestone-inset|a gold-lined|a silver-lined)")

local common_re = Regex.new(
    "You reach down and pull a " ..
    "(?:battered|corroded|damaged|dented|grimy|marred|rotted|rusted|stained|warped)")

local sealed_re = Regex.new("You reach down and pull a sealed")

-- Start the companion watch script (mirrors Script.start('dr_dig_watch'))
Script.run("dr_dig_watch")

-- Announce a found loot item to the client window.
-- Replaces the Lich5 fam_window (Stormfront pushStream / GSe escape) output
-- with a standard respond() call that Revenant routes to the active frontend.
local function announce_loot(item_name)
    respond("You hear the faint thoughts of Found echo in your mind:\r\n" .. item_name)
end

-- get_pickaxe: retrieve pickaxe from questsack / back / over-shoulder slot.
-- Returns true on success, false if the pickaxe cannot be found (caller should exit).
local function get_pickaxe()
    local result = dothistimeout("get my pickaxe", 5,
        "You remove", "You discreetly", "You retrieve", "You already",
        "Reaching over your shoulder", "Get what?")
    if result and result:find("Get what?") then
        echo("get_pickaxe: pickaxe not found — exiting")
        return false
    end
    return true
end

-- stow_pickaxe: put pickaxe back in questsack; pause if something goes wrong.
local function stow_pickaxe()
    waitrt()
    local questsack = Vars.questsack or ""
    if questsack == "" then
        echo("stow_pickaxe: Vars.questsack is not set — pausing")
        pause_script(Script.name)
        return
    end
    local result = dothistimeout("put my pickaxe in my " .. questsack, 5,
        "You put", "You discreetly tuck", "You slip",
        "Reaching over your shoulder", "Get what?", "won't fit")
    if result and result:find("Get what?") then
        echo("stow_pickaxe: questsack not found — pausing")
        pause_script(Script.name)
    elseif result and result:find("won't fit") then
        echo("stow_pickaxe: questsack is full — pausing")
        pause_script(Script.name)
    end
end

-- open_box: open whatever is in the left hand.
local function open_box()
    local lh = GameObj.left_hand()
    if not lh then return end
    dothistimeout("open my " .. lh.noun, 5, "You open the lid", "You lift the lid")
end

-- pass_loot: give the item in the right hand to lootchar; falls back to lootchar2.
local function pass_loot()
    local lootchar  = Vars.lootchar  or ""
    local lootchar2 = Vars.lootchar2 or ""
    if lootchar == "" then
        echo("pass_loot: Vars.lootchar is not set — pausing")
        pause_script(Script.name)
        return
    end
    while true do
        local rh = GameObj.right_hand()
        if not rh or rh.noun == "pickaxe" then
            echo("pass_loot: right hand is empty or pickaxe — pausing")
            pause_script(Script.name)
            return
        end

        local result = dothistimeout("give " .. lootchar, 120,
            "has accepted", "already has an outstanding offer.",
            "What is it you're trying to give?", "What are you trying to give?")

        if result and result:find("has accepted") then
            return
        elseif result and result:find("already has an outstanding offer.") then
            pause(1)
        elseif result and (result:find("What is it you") or result:find("What are you trying to give?")) then
            -- Primary lootchar unavailable; try secondary
            rh = GameObj.right_hand()
            if rh and rh.noun ~= "pickaxe" and lootchar2 ~= "" then
                local result2 = dothistimeout("give " .. lootchar2, 120,
                    "has accepted", "already has an outstanding offer.",
                    "What is it you're trying to give?", "What are you trying to give?")
                if result2 and result2:find("has accepted") then
                    return
                elseif result2 and result2:find("already has an outstanding offer.") then
                    pause(1)
                else
                    echo("pass_loot: could not give to lootchar or lootchar2 — pausing")
                    pause_script(Script.name)
                    return
                end
            else
                echo("pass_loot: right hand is pickaxe or Vars.lootchar2 not set — pausing")
                pause_script(Script.name)
                return
            end
        end
    end
end

-- process_box: loot the contents of the open box in the left hand.
local function process_box()
    waitrt()
    local lh = GameObj.left_hand()
    if not lh then return end
    local result = dothistimeout("look in #" .. lh.id, 5, "In the", "Inside the")
    if result and result:find("In the") then
        local contents = lh.contents
        if contents then
            for _, item in ipairs(contents) do
                fput("get #" .. item.id)
                announce_loot(item.name)
                if f2p_troop:test(Char.name) then
                    pass_loot()
                else
                    if bin_items_re:test(item.noun) then
                        fput("put " .. item.noun .. " in bin")
                    else
                        fput("put " .. item.noun .. " in my " .. (Vars.lootsack or ""))
                    end
                end
            end
        end
    end
end

-- process_sealed: loot the skeleton contents from the sealed box in left hand.
local function process_sealed()
    waitrt()
    local lh = GameObj.left_hand()
    if not lh then return end
    local result = dothistimeout("look in #" .. lh.id, 5,
        "On the skeleton you see",
        "The skeleton has been picked clean of belongings.")
    if result and result:find("On the skeleton you see") then
        -- Extract noun: last whitespace-separated word before ". The stench"
        local item_list = result:match("On the skeleton you see (.-)%.%s+The stench")
        local prize = item_list and item_list:match("%S+$")
        if prize then
            waitrt()
            lh = GameObj.left_hand()
            if lh then
                fput("get " .. prize .. " from #" .. lh.id)
                announce_loot(prize)
                if f2p_troop:test(Char.name) then
                    pass_loot()
                else
                    local rh = GameObj.right_hand()
                    local rh_noun = (rh and rh.noun) or prize
                    if bin_items_re:test(rh_noun) then
                        fput("put " .. prize .. " in bin")
                    else
                        fput("put " .. prize .. " in my " .. (Vars.lootsack or ""))
                    end
                end
            end
        end
    elseif result and result:find("The skeleton has been picked clean") then
        -- Nothing to loot — normal, continue
    else
        echo("process_sealed: unexpected response — pausing")
        pause_script(Script.name)
    end
end

-- found_sealed: pry open a sealed container, then process it twice.
-- Uses a loop rather than recursion to avoid stack overflow on stubborn lids.
local function found_sealed()
    local lh = GameObj.left_hand()
    if not lh then return end
    while true do
        waitrt()
        lh = GameObj.left_hand()
        if not lh then return end
        local result = dothistimeout("pry my " .. lh.noun, 5,
            "You begin pulling at",
            "With the lid loosened",
            "is already opened.")
        if result and result:find("You begin pulling at") then
            -- Still prying; loop and try again
        elseif result and (result:find("With the lid loosened") or result:find("is already opened")) then
            process_sealed()
            process_sealed()
            waitrt()
            return
        else
            waitrt()
            return
        end
    end
end

-- empty_loot: dump everything in the left-hand container into the loot sack.
local function empty_loot()  -- luacheck: ignore (available for external callers)
    local lh = GameObj.left_hand()
    if lh then
        fput("empty my " .. lh.noun .. " in my " .. (Vars.lootsack or ""))
    end
end

-- trash_box: close and bin the empty box, then re-equip the pickaxe.
local function trash_box()
    local lh = GameObj.left_hand()
    if lh and lh.noun ~= "pickaxe" then
        fput("close my " .. lh.noun)
        -- Re-read after the close command in case the handle changes
        lh = GameObj.left_hand()
        if lh then
            local result = dothistimeout("put my " .. lh.noun .. " in bin", 5,
                "As you place",
                "There appears to be an item or items attached")
            if result and result:find("There appears to be an item") then
                echo("trash_box: high-value item detected on container — pausing")
                pause_script(Script.name)
            end
        end
    else
        echo("trash_box: unexpected left-hand state — pausing")
        pause_script(Script.name)
    end
    get_pickaxe()
end

-- dig: perform one dig cycle and dispatch on the result.
local function dig()
    local result = dothistimeout("dig", 15, dig_patterns)
    if not result then
        waitrt()
        return
    end

    if ornate_re:test(result) then
        -- Premium find — spam alert and wait for manual intervention
        for _ = 1, 5 do
            echo("Found a winner!")
        end
        pause(30)
    elseif common_re:test(result) then
        waitrt()
        stow_pickaxe()
        open_box()
        process_box()
        trash_box()
    elseif sealed_re:test(result) then
        waitrt()
        stow_pickaxe()
        found_sealed()
        trash_box()
    elseif result:find("You need your left hand free to help grasp") then
        echo("dig: left hand not free — pausing")
        pause_script(Script.name)
    elseif result:find("Perhaps you need a shovel") then
        local lh = GameObj.left_hand()
        if lh and lh.noun == "pickaxe" then
            fput("swap")
        else
            get_pickaxe()
        end
    else
        -- Continuing-dig messages (no dig result yet); wait for RT and loop
        waitrt()
    end
end

-- ── Main ─────────────────────────────────────────────────────────────────────

if not get_pickaxe() then
    return
end

while true do
    dig()
end
