local settings_mod = require("settings")

local M = {}

function M.show(st)
    local win = Gui.window("EBounty Setup v2.0", {width = 850, height = 700, resizable = true})
    local root = Gui.vbox()

    -- Bounty Types
    root:add(Gui.label("=== Bounty Types ==="))
    root:add(Gui.separator())
    for _, opt in ipairs({
        {"boss_culling", "Boss Creature"}, {"culling", "Culling"},
        {"escort", "Escort"}, {"foraging", "Foraging"},
        {"gem_collecting", "Gem Collecting"}, {"heirloom_loot", "Heirloom (Loot)"},
        {"heirloom_search", "Heirloom (Search)"}, {"rescue", "Rescue"},
        {"skinning", "Skinning"}, {"kill_bandits", "Bandits"},
    }) do
        local key, label = opt[1], opt[2]
        local cb = Gui.checkbox(label, settings_mod.list_contains(st.bounty_types, key))
        cb:on("change", function(val)
            if val then settings_mod.list_add(st.bounty_types, key)
            else settings_mod.list_remove(st.bounty_types, key) end
        end)
        root:add(cb)
    end

    -- Limits
    root:add(Gui.separator())
    root:add(Gui.label("=== Limits ==="))
    for _, f in ipairs({
        {"culling_max","Max Culling"},{"gem_max","Max Gems"},
        {"herb_max","Max Herbs"},{"skin_max","Max Skins"},{"extra_skin","Extra Skins"},
    }) do
        local row = Gui.hbox()
        row:add(Gui.label(f[2] .. ": "))
        local inp = Gui.input({text = tostring(st[f[1]] or 0)})
        inp:on("change", function(v) st[f[1]] = tonumber(v) or 0 end)
        row:add(inp); root:add(row)
    end

    -- Toggles
    root:add(Gui.separator())
    root:add(Gui.label("=== Behavior ==="))
    for _, t in ipairs({
        {"exp_pause","Pause when mind full"},{"skip_healing","Skip healing"},
        {"once_and_done","Run one bounty and quit"},{"new_bounty_on_exit","Get new bounty before exit"},
        {"keep_hunting","Keep hunting after bounty"},{"basic","Basic mode"},
        {"ranger_track","Use Ranger Track"},{"return_to_group","Return to group on exit"},
        {"use_boosts","Use bounty boosts"},{"use_vouchers","Use vouchers"},
        {"remove_heirloom","Remove if heirloom lost"},{"debug","Debug mode"},
    }) do
        local cb = Gui.checkbox(t[2], st[t[1]] or false)
        cb:on("change", function(v) st[t[1]] = v end)
        root:add(cb)
    end

    -- Scripts
    root:add(Gui.separator())
    root:add(Gui.label("=== Scripts ==="))
    for _, f in ipairs({
        {"selling_script","Selling"},{"healing_script","Healing"},
        {"death_script","Death"},{"hording_script","Hoarding"},
        {"escort_script","Escort"},{"rescue_script","Rescue"},
        {"gem_history","Gem History"},{"buff_script","Buff"},
    }) do
        local row = Gui.hbox()
        row:add(Gui.label(f[2] .. ": "))
        local inp = Gui.input({text = st[f[1]] or ""})
        inp:on("change", function(v) st[f[1]] = v end)
        row:add(inp); root:add(row)
    end

    -- Resting
    root:add(Gui.separator())
    root:add(Gui.label("=== Resting ==="))
    for _, t in ipairs({
        {"table_rest","Rest at table"},{"bigshot_rest","Use bigshot resting room"},
        {"custom_rest","Custom room"},{"rest_random","Random town spot"},
        {"use_script","Use resting script"},{"join_player","Join player after rest"},
        {"use_buff_script","Run buff script"},
    }) do
        local cb = Gui.checkbox(t[2], st[t[1]] or false)
        cb:on("change", function(v) st[t[1]] = v end)
        root:add(cb)
    end
    for _, f in ipairs({
        {"resting_room","Custom Room IDs"},{"use_script_name","Resting Script"},
        {"join_list","Join Player Names"},
    }) do
        local row = Gui.hbox()
        row:add(Gui.label(f[2] .. ": "))
        local inp = Gui.input({text = st[f[1]] or ""})
        inp:on("change", function(v) st[f[1]] = v end)
        row:add(inp); root:add(row)
    end

    -- Exclusions
    root:add(Gui.separator())
    root:add(Gui.label("=== Exclusions (comma-separated) ==="))
    for _, f in ipairs({
        {"creature_exclude","Creatures"},{"herb_exclude","Herbs"},
        {"gem_exclude","Gems"},{"location_exclude","Locations"},
    }) do
        local row = Gui.hbox()
        row:add(Gui.label(f[2] .. ": "))
        local inp = Gui.input({text = table.concat(st[f[1]] or {}, ", ")})
        inp:on("change", function(v)
            local list = {}
            for item in v:gmatch("[^,]+") do
                item = item:match("^%s*(.-)%s*$")
                if item ~= "" then list[#list + 1] = item end
            end
            st[f[1]] = list
        end)
        row:add(inp); root:add(row)
    end

    -- Profiles
    root:add(Gui.separator())
    root:add(Gui.label("=== Profiles ==="))
    for _, f in ipairs({{"default_profile","Default Profile"},{"bandits_profile","Bandits Profile"}}) do
        local row = Gui.hbox()
        row:add(Gui.label(f[2] .. ": "))
        local inp = Gui.input({text = st[f[1]] or ""})
        inp:on("change", function(v) st[f[1]] = v end)
        row:add(inp); root:add(row)
    end
    for _, letter in ipairs({"a","b","c","d","e","f","g","h","i","j"}) do
        local row = Gui.hbox()
        row:add(Gui.label(letter:upper() .. " Names: "))
        local n = Gui.input({text = st["names_" .. letter] or ""})
        n:on("change", function(v) st["names_" .. letter] = v end)
        row:add(n)
        row:add(Gui.label(" Profile: "))
        local p = Gui.input({text = st["profile_" .. letter] or ""})
        p:on("change", function(v) st["profile_" .. letter] = v end)
        row:add(p)
        local k = Gui.checkbox("Kill Only", st["kill_" .. letter] or false)
        k:on("change", function(v) st["kill_" .. letter] = v end)
        row:add(k); root:add(row)
    end

    -- Buttons
    root:add(Gui.separator())
    local btns = Gui.hbox()
    local save = Gui.button("Save & Close")
    save:on("click", function() settings_mod.save(st); win:close() end)
    btns:add(save)
    local cancel = Gui.button("Cancel")
    cancel:on("click", function() win:close() end)
    btns:add(cancel); root:add(btns)

    win:add(Gui.scroll(root))
    Gui.wait(win, "close")
    return st
end

return M
