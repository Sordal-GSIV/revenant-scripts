-- Player display helpers: status normalization, group display, Wrayth XML,
-- and action determination for both Wrayth links and the Revenant GUI.

local state = require("state")

local M = {}

-- Normalise a raw game status string to a canonical label, or nil if no
-- special status (i.e. the player is standing and unaffected).
-- Priority matches the original: stunned > sleeping > prone > sitting > ...
function M.player_status_fix(status)
    if not status or status == "" then return nil end
    if status:find("dead",         1, true) then return "dead"     end
    if status:find("stun",         1, true) then return "stunned"  end
    if status:find("unconscious",  1, true) or
       status:find("slumber",      1, true) or
       status:find("sleeping",     1, true) then return "sleeping" end
    if status:find("lying down",   1, true) or
       status:find("prone",        1, true) or
       status:find("knocked",      1, true) then return "prone"    end
    if status:find("sitting",      1, true) then return "sitting"  end
    if status:find("kneeling",     1, true) then return "kneeling" end
    if status:find("calmed",       1, true) then return "calmed"   end
    if status:find("frozen",       1, true) then return "frozen"   end
    if status:find("held",         1, true) then return "held"     end
    if status:find("web",          1, true) then return "webbed"   end
    return nil
end

-- Extract the display noun from a GameObj (noun field, fallback to name).
function M.extract_noun(pc)
    if pc.noun and pc.noun ~= "" then return pc.noun end
    return pc.name or "?"
end

-- Build group display string from Group.members / Group.leader (lib/group.lua).
function M.get_group_display()
    local leader  = Group.leader
    local members = type(Group.members) == "table" and Group.members or {}

    if not leader and #members == 0 then return nil end

    local self_name = Char.name
    local display   = {}
    local seen      = {}

    -- Leader at the front, marked with asterisks
    if leader then
        local lbl = (leader == self_name) and "*YOU*" or ("*" .. leader .. "*")
        display[#display + 1] = lbl
        seen[leader] = true
    end

    -- Sort remaining members alphabetically
    local sorted = {}
    for _, n in ipairs(members) do sorted[#sorted + 1] = n end
    table.sort(sorted)

    for _, name in ipairs(sorted) do
        if not seen[name] then
            display[#display + 1] = (name == self_name) and "YOU" or name
            seen[name] = true
        end
    end

    -- Suppress solo display (only ourselves)
    if #display == 0 then return nil end
    if #display == 1 and (display[1] == "*YOU*" or display[1] == "YOU") then return nil end

    return "Group: " .. table.concat(display, ", ")
end

-- Search inventory containers for an oak/oaken wand or rod.
-- Returns {container_id, wand} or nil.
local function find_oak_wand()
    local inv = GameObj.inv()
    for _, item in ipairs(inv) do
        local contents = item.contents
        if contents then
            for _, c in ipairs(contents) do
                local cname = (c.name or ""):lower()
                if (cname:find("oak") or cname:find("oaken")) and
                   (cname:find("wand") or cname:find(" rod")) then
                    return { container_id = item.id, wand = c }
                end
            end
        end
    end
    return nil
end

-- Determine the action to perform when the Wrayth XML link is clicked.
-- Must return a single game command string (Wrayth links can only send one cmd).
local function action_cmd_wrayth(status, pc)
    if     status == "sitting"  or
           status == "kneeling" or
           status == "prone"    then return "pull #" .. pc.id
    elseif status == "sleeping" then return "poke #" .. pc.id
    else                             return "look #" .. pc.id
    end
end

-- Determine the action for the Revenant GUI button.
-- Returns a descriptor table; the init module processes it via fput sequences.
--   {type="cmd",   cmd="..."}
--   {type="spell", num=N,    target_id="#..."}
--   {type="wand",  wand_id=, container_id=, target_id="#..."}
function M.action_for_status_gui(status, pc)
    if status == "stunned" then
        if Spell[108] and Spell[108].known and Spell[108]:affordable() then
            return { type = "spell", num = 108, target_id = "#" .. pc.id }
        end
        local w = find_oak_wand()
        if w then
            return { type = "wand", wand_id = w.wand.id,
                     container_id = w.container_id, target_id = "#" .. pc.id }
        end

    elseif status == "sitting" or status == "kneeling" or status == "prone" then
        return { type = "cmd", cmd = "pull #" .. pc.id }

    elseif status == "sleeping" then
        return { type = "cmd", cmd = "poke #" .. pc.id }

    elseif status == "webbed" then
        if Spell[209] and Spell[209].known and Spell[209]:affordable() then
            return { type = "spell", num = 209, target_id = "#" .. pc.id }
        end
    end

    return { type = "cmd", cmd = "look #" .. pc.id }
end

-- Push sorted player list to the Wrayth/Stormfront dynamic dialog window.
function M.push_players_to_window(pcs)
    if not Frontend.supports_streams() then return end

    -- Sort: dead players first, then alphabetical by noun
    local sorted = {}
    for _, pc in ipairs(pcs) do sorted[#sorted + 1] = pc end
    table.sort(sorted, function(a, b)
        local sa = M.player_status_fix(a.status)
        local sb = M.player_status_fix(b.status)
        local da = (sa == "dead") and 0 or 1
        local db = (sb == "dead") and 0 or 1
        if da ~= db then return da < db end
        return M.extract_noun(a):lower() < M.extract_noun(b):lower()
    end)

    local out       = "<dialogData id='PlayerWindow' clear='t'>"
    local cur_top   = 0
    local col_right = 180

    -- Filter toggle buttons (only shown for Wrayth single/double column)
    if state.show_filter_buttons then
        local filters = {
            { id = "filter_toggle", on = state.filter_spam,         cmd = "*filterspam",    lbl = "Spam Filter" },
            { id = "flare_toggle",  on = state.filter_flares,       cmd = "*pwflare",       lbl = "Flare Filter" },
            { id = "combat_toggle", on = state.filter_combat_math,  cmd = "*pwcombat",      lbl = "Combat Filter" },
            { id = "animal_toggle", on = state.filter_animals,      cmd = "*filteranimals", lbl = "Animal Filter" },
        }
        if state.single_column then
            for _, f in ipairs(filters) do
                local val = f.lbl .. ": " .. (f.on and "ON" or "OFF")
                out = out .. string.format(
                    "<link id='%s' value='%s' cmd='%s' echo='Toggling...' justify='bottom' left='0' top='%d' />",
                    f.id, val, f.cmd, cur_top)
                cur_top = cur_top + 20
            end
        else
            -- Two-column: pairs of filters side-by-side
            for i = 1, #filters, 2 do
                local f1 = filters[i]
                local f2 = filters[i + 1]
                local v1 = f1.lbl .. ": " .. (f1.on and "ON" or "OFF")
                out = out .. string.format(
                    "<link id='%s' value='%s' cmd='%s' echo='Toggling...' justify='bottom' left='0' top='%d' />",
                    f1.id, v1, f1.cmd, cur_top)
                if f2 then
                    local v2 = f2.lbl .. ": " .. (f2.on and "ON" or "OFF")
                    out = out .. string.format(
                        "<link id='%s' value='%s' cmd='%s' echo='Toggling...' justify='bottom' left='%d' top='%d' />",
                        f2.id, v2, f2.cmd, col_right, cur_top)
                end
                cur_top = cur_top + 20
            end
        end
    end

    -- Group display
    if state.group_display then
        out = out .. string.format(
            "<label id='group' value='%s' justify='bottom' left='0' top='%d'/>",
            state.group_display, cur_top)
        cur_top = cur_top + 20
    end

    -- PC count
    out = out .. string.format(
        "<label id='total' value='PCs: %d' justify='bottom' left='0' top='%d'/>",
        #sorted, cur_top)
    cur_top = cur_top + 20

    -- Player rows
    local row_h    = 20
    local top_off  = cur_top / row_h
    local slice    = state.single_column and 1 or 2
    local row, col = 0, 0

    for _, pc in ipairs(sorted) do
        local noun   = M.extract_noun(pc)
        local status = M.player_status_fix(pc.status)
        local label  = status and (noun .. " (" .. status .. ")") or noun
        local cmd    = action_cmd_wrayth(status, pc)
        local left   = (col == 0) and 0 or col_right
        local top    = row_h * (row + top_off)

        out = out .. string.format(
            "<link id='player_%d_%d' value='%s' cmd=\"%s\" echo=\"%s\" justify='bottom' left='%d' top='%d' />",
            row, col, label, cmd, cmd, left, top)

        col = col + 1
        if col >= slice then col = 0; row = row + 1 end
    end

    out = out .. "</dialogData>"
    put(out)
end

return M
