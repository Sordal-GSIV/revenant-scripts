--- Bounty display formatting for creature window.
--- Uses Bounty.parse() for structured bounty data plus custom regex for
--- detailed bounty task/status/action lines matching the original Lich5 creaturewindow.

local inventory = require("inventory")

local M = {}

-- Bounty origin tracking
M.origin_room_id = nil
M.origin_npc_id = nil
M.origin_npc_noun = nil

-- Parsed bounty state (detailed, beyond Bounty.parse())
local bt = {} -- bounty table, repopulated each parse

-- Workflow running flags
M.herb_workflow_running = false
M.gem_workflow_running = false
M.guild_workflow_running = false
M.guard_workflow_running = false
M.furrier_workflow_running = false
M.skin_workflow_running = false

--- Parse bounty text into detailed fields for display.
function M.parse()
    local text = checkbounty()
    if not text or text == "" then
        bt = { task_type = "none" }
        return
    end

    bt = {}

    -- No bounty
    if text:find("You are not currently assigned a task") then
        bt.task_type = "none"
        return
    end

    -- Completed heirloom
    local heirloom_found = Regex.new("You have located (?:an? |a pair of |some )(.+?) and should bring")
    local caps = heirloom_found:captures(text)
    if caps then
        bt.task_type = "completeheirloom"
        bt.heirloom = caps[1]
        return
    end

    -- Complete guard
    if Regex.test("report back to", text) then
        bt.task_type = "completeguard"
        local npc_caps = Regex.new("report back to (.+?)\\."):captures(text)
        bt.turnin_npc = npc_caps and npc_caps[1] or nil
        return
    end

    -- Complete guild
    if text:find("Guild to receive your reward") then
        bt.task_type = "completeguild"
        return
    end

    -- Guild visit
    if Regex.test("(?:visit|head|go|return)\\s+(?:to\\s+)?the Adventurer'?s Guild", text)
       or Regex.test("talk to (?:the )?Guild Taskmaster", text) then
        bt.task_type = "guildvisit"
        return
    end

    -- Bandit (general)
    local bandit_gen = Regex.new("task here from the town of (.+?)\\.  It appears they have a bandit problem")
    caps = bandit_gen:captures(text)
    if caps then
        bt.task_type = "bandit"
        bt.remaining = "Talk to guard for specifics."
        bt.location = caps[1]
        return
    end

    -- Bandit (specific)
    local bandit_loc = Regex.new("You have been tasked to suppress bandit activity (?:on|in the|in) (.+?) (?:near|between)")
    local bandit_kill = Regex.new("You need to kill (\\d+)")
    caps = bandit_loc:captures(text)
    local caps2 = bandit_kill:captures(text)
    if caps and caps2 then
        bt.task_type = "banditspecifics"
        bt.location = caps[1]
        bt.remaining = tonumber(caps2[1])
        return
    end

    -- Escort
    if Regex.test("protective escort", text) then
        local dest = Regex.new("safety to (.+?) as"):captures(text)
        local start = Regex.new("(?:inside the |area just |south end )(.+?) and wait"):captures(text)
        if dest and start then
            bt.task_type = "escort"
            bt.escort_start = start[1]
            bt.location = dest[1]
            return
        end
    end

    -- Gem (general)
    local gem_gen = Regex.new("(?:town|outpost) of ([^\\.]+)\\.\\s+The local gem dealer")
    caps = gem_gen:captures(text)
    if caps then
        bt.task_type = "gem"
        bt.remaining = "Talk to gem dealer for specifics."
        bt.location = caps[1]
        return
    end

    -- Gem (specific)
    local gem_loc = Regex.new("The gem dealer in (.+?),")
    local gem_name = Regex.new("The gem dealer in .*? requesting (.+?)\\.")
    local gem_count = Regex.new("You have been tasked to retrieve (\\d+) (?:more )?of them")
    local gc1, gc2, gc3 = gem_loc:captures(text), gem_name:captures(text), gem_count:captures(text)
    if gc1 and gc2 and gc3 then
        bt.task_type = "gemspecifics"
        bt.gem = gc2[1]
        bt.remaining = tonumber(gc3[1])
        bt.location = gc1[1]
        return
    end

    -- Herb (general)
    if Regex.test("task here from the (?:town|outpost) of (.+?)\\.  The local .*(?:alchemist|healer|herbalist)", text) then
        local herb_gen = Regex.new("task here from the (?:town|outpost) of (.+?)\\.  The local")
        caps = herb_gen:captures(text)
        if caps then
            bt.task_type = "herb"
            bt.remaining = "Talk to healer for specifics."
            bt.location = caps[1]
            return
        end
    end

    -- Herb (specific)
    local herb_name_re = Regex.new("working on a concoction that requires (?:an?|a handful of|some)\\s+(.+?)(?:\\s+found\\s+in|\\.)")
    local herb_count_re = Regex.new("retrieve (\\d+)\\s+(?:more\\s+)?samples?")
    local hc1, hc2 = herb_name_re:captures(text), herb_count_re:captures(text)
    if hc1 and hc2 then
        bt.task_type = "herbspecifics"
        bt.herb = hc1[1]
        bt.remaining = tonumber(hc2[1])
        local loc = Regex.new("found in (?:the )?(.+?) near"):captures(text)
            or Regex.new("only grows in (?:the )?(.+?) near"):captures(text)
        bt.location = loc and loc[1] or bt.location
        return
    end

    -- Alternate herb specifics
    local herb_alt = Regex.new("concoction that requires (?:an?|some) (.+?) found")
    local herb_alt_loc = Regex.new("found (?:in|on the) (?:the )?(.+?) near")
    local herb_alt_count = Regex.new("You have been tasked to retrieve (\\d+) (?:more )?samples?")
    local ha1, ha2, ha3 = herb_alt:captures(text), herb_alt_loc:captures(text), herb_alt_count:captures(text)
    if ha1 and ha2 and ha3 then
        bt.task_type = "herbspecifics"
        bt.herb = ha1[1]
        bt.remaining = tonumber(ha3[1])
        bt.location = ha2[1]
        return
    end

    -- Skin (general)
    if Regex.test("The local furrier .* has an order to fill and wants our help", text) then
        local skin_loc = Regex.new("of (.+?)\\.  The local furrier")
        caps = skin_loc:captures(text)
        if caps then
            bt.task_type = "skin"
            bt.remaining = "Talk to furrier for specifics."
            bt.location = caps[1]
            return
        end
    end

    -- Skin (specific)
    local skin_count = Regex.new("You have been tasked to retrieve (\\d+) .* of at")
    local skin_name = Regex.new("retrieve \\d+ (.+?) of at least")
    local skin_loc = Regex.new("quality\\s+for.*?(?:in|on the)\\s+(.+?)\\.\\s+You")
    local sc1, sc2, sc3 = skin_count:captures(text), skin_name:captures(text), skin_loc:captures(text)
    if sc1 and sc2 and sc3 then
        bt.task_type = "skinspecifics"
        bt.skin = sc2[1]
        bt.remaining = tonumber(sc1[1])
        bt.location = sc3[1]
        return
    end

    -- Creature (general)
    if Regex.test("It appears they have a creature problem", text) then
        local cloc = Regex.new("(?:town|outpost) of ([^\\.]+)\\.\\s+It")
        caps = cloc:captures(text)
        if caps then
            bt.task_type = "creature"
            bt.remaining = "Talk to guard for specifics."
            bt.location = caps[1]
            return
        end
    end

    -- Dangerous creature
    local dang_cr = Regex.new("hunt down and kill a particularly dangerous (.+?) that has")
    local dang_loc = Regex.new("(?:activity|territory) (?:in|on the) (?:the )?(.+?)(?: near)?\\.")
    local dc1, dc2 = dang_cr:captures(text), dang_loc:captures(text)
    if dc1 and dc2 then
        bt.task_type = "dangerous"
        bt.target_creature = dc1[1]
        bt.location = dc2[1]
        return
    end

    -- Kill (cull)
    local kill_cr = Regex.new("(?:tasked to|by) (?:.* )?(?:suppressing|suppress) (.+?) activity")
    local kill_count = Regex.new("You need to kill (\\d+)")
    local kill_loc = Regex.new("(?:activity|territory) (?:in|on the) (?:the )?(.+?)(?: near)?\\.")
    local kc1, kc2, kc3 = kill_cr:captures(text), kill_count:captures(text), kill_loc:captures(text)
    if kc1 and kc2 and kc3 then
        bt.task_type = "kill"
        bt.target_creature = kc1[1]
        bt.remaining = tonumber(kc2[1])
        bt.location = kc3[1]
        return
    end

    -- Resident (note: original Lich5 has typo "some king of" — we match both)
    if Regex.test("It appears (?:that a local resident|they need your help in tracking down some ki(?:ng|nd) of lost heirloom)", text) then
        local rloc = Regex.new("(?:town|outpost) of ([^\\.]+)\\.\\s+It")
        caps = rloc:captures(text)
        if caps then
            bt.task_type = "resident"
            bt.remaining = "Talk to guard for specifics."
            bt.location = caps[1]
            return
        end
    end

    -- Rescue
    if Regex.test("rescue", text) then
        local rescue_cr = Regex.new("the child fleeing from an? (.+?) in")
        local rescue_loc = Regex.new("(?:in|on the) (?:the )?(.+?) near")
        local rc1, rc2 = rescue_cr:captures(text), rescue_loc:captures(text)
        if rc1 and rc2 then
            bt.task_type = "rescue"
            bt.target_creature = rc1[1]
            bt.location = rc2[1]
            return
        end
    end

    -- Heirloom (general)
    if Regex.test("tracking down some kind of lost heirloom", text) then
        local hloc = Regex.new("(?:town|outpost) of (.+?)\\.  It appears they need")
        caps = hloc:captures(text)
        if caps then
            bt.task_type = "heirloom"
            bt.remaining = "Talk to guard for specifics."
            bt.location = caps[1]
            return
        end
    end

    -- Heirloom kill
    local heir_item = Regex.new("tasked to recover (?:an|a pair of|a|some) (.+?) that")
    local heir_cr = Regex.new("attacked by an? (.+?) (?:in the |in |on the )(.+?)(?: near)?")
    local hi1, hi2 = heir_item:captures(text), heir_cr:captures(text)
    if hi1 and hi2 and text:find("hunt down") then
        bt.task_type = "heirloomkill"
        bt.heirloom = hi1[1]
        bt.target_creature = hi2[1]
        bt.location = hi2[2]
        return
    end

    -- Heirloom search
    if hi1 and hi2 and text:find("search") then
        bt.task_type = "heirloomsearch"
        bt.heirloom = hi1[1]
        bt.target_creature = hi2[1]
        bt.location = hi2[2]
        return
    end

    bt.task_type = "unknown"
end

--- Get the bounty task type.
function M.task_type()
    return bt.task_type or "none"
end

--- Get detailed bounty table for workflow use.
function M.bounty_table()
    return bt
end

--- Bounty task display line.
function M.task_line()
    local t = bt.task_type
    if not t then return "No Bounty" end

    local loc = bt.location or ""
    local lookup = {
        bandit          = loc .. " - Bandit Bounty",
        banditspecifics = loc .. " - Bandit Bounty",
        escort          = "Escort - " .. loc,
        gem             = loc .. " - Gem Bounty",
        gemspecifics    = loc .. " - Gem Bounty",
        herb            = loc .. " - Foraging Bounty",
        herbspecifics   = loc .. " - Foraging Bounty",
        skin            = loc .. " - Skinning Bounty",
        skinspecifics   = loc .. " - Skinning Bounty",
        creature        = loc .. " - Creature Bounty",
        kill            = loc .. " - Culling Bounty",
        dangerous       = loc .. " - Dangerous Bounty",
        resident        = loc .. " - Resident Bounty",
        rescue          = loc .. " - Rescue Bounty",
        heirloom        = loc .. " - Heirloom Bounty",
        heirloomkill    = "Find - " .. (bt.heirloom or ""),
        heirloomsearch  = "Find - " .. (bt.heirloom or ""),
        completeheirloom = "Found! - " .. (bt.heirloom or ""),
        completeguard   = "Task Complete!",
        completeguild   = "Task Complete!",
        guildvisit      = "Guild Bounty",
        none            = "No Bounty",
    }
    return lookup[t] or "No Bounty"
end

--- Bounty status display line.
function M.status_line()
    local t = bt.task_type
    if not t then return "" end

    local r = bt.remaining
    local lookup = {
        bandit          = tostring(r or ""),
        banditspecifics = "Kill " .. tostring(r or "") .. " - Bandit",
        escort          = "Start - " .. (bt.escort_start or ""),
        gem             = tostring(r or ""),
        gemspecifics    = "Find " .. tostring(r or "") .. " - " .. (bt.gem or ""),
        herb            = tostring(r or ""),
        herbspecifics   = "Find " .. tostring(r or "") .. " - " .. (bt.herb or ""),
        skin            = tostring(r or ""),
        skinspecifics   = "Find " .. tostring(r or "") .. " - " .. (bt.skin or ""),
        creature        = tostring(r or ""),
        kill            = "Kill " .. tostring(r or "") .. " - " .. (bt.target_creature or ""),
        dangerous       = "Kill - " .. (bt.target_creature or ""),
        resident        = tostring(r or ""),
        rescue          = "Kill - " .. (bt.target_creature or ""),
        heirloom        = tostring(r or ""),
        heirloomkill    = "Kill - " .. (bt.target_creature or ""),
        heirloomsearch  = "Search Near - " .. (bt.target_creature or ""),
        completeheirloom = "Return it to the guard!",
        completeguard   = (bt.turnin_npc and bt.turnin_npc ~= "")
                          and ("Report to " .. bt.turnin_npc)
                          or "Report to the guard!",
        completeguild   = "Report to the guild!",
        guildvisit      = "Visit the Adventurer's Guild",
        none            = "",
    }
    return lookup[t] or ""
end

--- Bounty action button label (or nil if no action available).
function M.action_line()
    local t = bt.task_type
    if not t then return nil end

    if t == "none" then
        if M.guild_workflow_running then return "Guild Run Active..." end
        return "Get New Bounty (AdvGuild)"
    end

    if t == "herb" or t == "herbspecifics" then
        if M.herb_workflow_running then return "Herb Run Active..." end
        return "Forage Herbs (zzherb) and Turn In"
    end

    if t == "gem" or t == "gemspecifics" then
        if M.gem_workflow_running then return "Gem Run Active..." end
        return "Gem Bounty Workflow"
    end

    if t == "guildvisit" or t == "completeguild" then
        if M.guild_workflow_running then return "Guild Run Active..." end
        return "Go to AdvGuild and Ask About Bounty"
    end

    if t == "skin" then
        if M.furrier_workflow_running then return "Furrier Run Active..." end
        return "Go to Furrier and Ask About Bounty"
    end

    if t == "skinspecifics" then
        if M.skin_workflow_running then return "Skin Run Active..." end
        -- Count skins on hand
        local skin_name = (bt.skin or ""):match("^%s*(.-)%s*$")
        if skin_name ~= "" then
            local singles, bundles = 0, 0
            local all_items = inventory.collect_all_inv()
            for _, item in ipairs(all_items) do
                if inventory.item_matches_bounty(item.name or "", skin_name) then
                    local count = inventory.item_stack_count(item)
                    if (item.name or ""):lower():find("bundle of") then
                        bundles = bundles + count
                    else
                        singles = singles + count
                    end
                end
            end
            local required = tonumber(bt.remaining) or 1
            if required < 1 then required = 1 end
            return string.format("Turn In Skins (%d singles, %d bundles / need %d)", singles, bundles, required)
        end
        return "Turn In Skins"
    end

    if t == "bandit" or t == "creature" or t == "resident" or t == "heirloom"
       or t == "completeguard" or t == "completeheirloom" then
        if M.guard_workflow_running then return "Guard Run Active..." end
        return "Go to AdvGuard and Ask About Bounty"
    end

    return nil
end

--- Get the workflow command ID for the current bounty action.
function M.action_cmd()
    local t = bt.task_type
    if not t then return nil end

    if t == "none" then return "guild" end
    if t == "herb" or t == "herbspecifics" then return "herb" end
    if t == "gem" or t == "gemspecifics" then return "gem" end
    if t == "guildvisit" or t == "completeguild" then return "guild" end
    if t == "skin" then return "furrier" end
    if t == "skinspecifics" then return "skin" end
    if t == "bandit" or t == "creature" or t == "resident" or t == "heirloom"
       or t == "completeguard" or t == "completeheirloom" then return "guard" end
    return nil
end

--- Capture bounty origin context (room and NPC).
function M.capture_origin()
    M.origin_room_id = M.origin_room_id or GameState.room_id
    local npc = inventory.find_bounty_npc()
    if npc then
        M.origin_npc_id = npc.id
        M.origin_npc_noun = npc.noun
    end
end

--- Ask an NPC about bounty and refresh, using change-detection.
function M.ask_bounty_and_sync(npc, use_put, timeout)
    if not npc then return false end
    timeout = timeout or 1.5
    local interval = 0.15

    -- Capture state signature before asking
    local before = M.state_signature()

    local cmd = "ask #" .. npc.id .. " about bounty"
    if use_put then
        put(cmd)
    else
        fput(cmd)
    end

    -- Poll until bounty state changes or timeout
    local changed = false
    local start = os.clock()
    while (os.clock() - start) < timeout do
        M.parse()
        if M.state_signature() ~= before then
            changed = true
            break
        end
        pause(interval)
    end

    if not changed then
        M.parse()  -- final attempt
    end
    return changed
end

--- State signature for change-detection in ask_bounty_and_sync.
function M.state_signature()
    return table.concat({
        tostring(bt.task_type),
        tostring(bt.remaining),
        tostring(bt.location),
        tostring(bt.gem),
        tostring(bt.skin),
        tostring(bt.heirloom),
        tostring(bt.target_creature),
        tostring(bt.herb),
        tostring(bt.turnin_npc),
    }, "|")
end

--- Pre-clear stale gem bounty state (used before asking gem dealer for fresh specifics).
function M.clear_gem_state()
    bt.task_type = "gem"
    bt.gem = nil
    bt.remaining = 0
end

--- Get the current herb name cleaned for use.
function M.current_herb_name()
    local herb = bt.herb or ""
    herb = herb:gsub("^some%s+", ""):gsub("^an?%s+", ""):gsub("^a handful of%s+", "")
    herb = herb:gsub("%s+found%s+in%s+.+$", ""):gsub("%s+that%s+only%s+grows%s+in%s+.+$", "")
    return herb:match("^%s*(.-)%s*$") or ""
end

--- Get the base noun of the current herb.
function M.current_herb_noun()
    local name = M.current_herb_name()
    if name == "" then return "" end
    local last = name:match("(%S+)$") or ""
    return last:gsub("[^%a'%-]", ""):lower()
end

return M
