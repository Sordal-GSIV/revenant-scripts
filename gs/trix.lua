--- @revenant-script
--- name: trix
--- version: 1.0.3
--- author: elanthia-online
--- contributors: Scribs, Claude
--- @lic-certified: complete 2026-03-19
--- game: gs
--- description: Magic item container scanner and activator with menu interface
--- tags: utility,containers,magic items,spells,miu
---
--- Changelog (from Lich5):
---   v1.0.3 (2026-03-19): Lua conversion certified — charge tracking, column alignment
---   v1.0.2 (2025-10-29): Reformatted menu, added options for concise display
---   v1.0.1 (2025-09-10): Refactored into module architecture
---   v1.0.0 (2025-09-09): Initial release
---
--- Usage:
---   ;trix scan <container>      - scan a container for magic items
---   ;trix                       - display menu of saved magic items
---   ;trix -bonus                - display menu with spell bonuses
---   ;trix -name                 - display menu with item names
---   ;trix <menu number>         - activate that magic item
---   ;trix <menu number> -f      - force activate even with 1 charge
---   ;trix clear                 - delete all saved data

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local EXCLUDED_ITEMS = {
    "small statue", "blue wand", "flask", "quartz orb", "golden wand",
    "twisted wand", "cube", "coin", "gold ring", "crystal amulet",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function pad_right(s, w)
    if #s >= w then return s end
    return s .. string.rep(" ", w - #s)
end

local function str_lower(s) return s and string.lower(s) or "" end

local function is_excluded(item_name)
    local lower = str_lower(item_name)
    for _, excl in ipairs(EXCLUDED_ITEMS) do
        if string.find(lower, str_lower(excl), 1, true) then return true end
    end
    return false
end

local function has_flag(args, flag)
    for _, a in ipairs(args) do
        if a == flag then return true end
    end
    return false
end

local function non_flag_args(args)
    local result = {}
    for _, a in ipairs(args) do
        if not string.match(a, "^%-") then
            table.insert(result, a)
        end
    end
    return result
end

local function get_spell_info(spell_name)
    if not spell_name or spell_name == "Unknown" then
        return { num = nil, bonuses = {} }
    end
    local spell = Spell[spell_name]
    if not spell then return { num = nil, bonuses = {} } end
    local num = spell.num
    local bonuses = {}

    local checks = {
        { "bolt_as", "bAS" }, { "physical_as", "pAS" },
        { "bolt_ds", "bDS" }, { "physical_ds", "pDS" },
        { "elemental_cs", "elemCS" }, { "mental_cs", "mentCS" },
        { "spirit_cs", "spirCS" }, { "sorcerer_cs", "sorcCS" },
        { "elemental_td", "elemTD" }, { "mental_td", "mentTD" },
        { "spirit_td", "spirTD" }, { "sorcerer_td", "sorcTD" },
        { "strength", "str" }, { "constitution", "con" },
        { "health", "health" }, { "dodging", "dodge" },
        { "combatmaneuvers", "CM" }, { "damagefactor", "% DF" },
        { "block", "% block" }, { "unarmed_af", "UAF" }, { "asg", "AsG" },
    }

    local ok, _ = pcall(function()
        for _, chk in ipairs(checks) do
            local val = spell[chk[1]]
            if val and tonumber(val) and tonumber(val) ~= 0 then
                table.insert(bonuses, tostring(val) .. " " .. chk[2])
            end
        end
    end)

    return { num = num, bonuses = bonuses }
end

--------------------------------------------------------------------------------
-- Item Scanner
--------------------------------------------------------------------------------

local function scan_container(container_name, show_bonuses, show_names)
    local container_obj = nil
    for _, obj in ipairs(GameObj.inv()) do
        if string.find(str_lower(obj.name), str_lower(container_name), 1, true)
            or string.find(str_lower(obj.noun), str_lower(container_name), 1, true) then
            container_obj = obj
            break
        end
    end

    if not container_obj then
        echo("Error: Container '" .. container_name .. "' not found in your inventory")
        return
    end

    echo("Operating on container: " .. container_obj.name)

    local container_items = container_obj.contents
    if not container_items or #container_items == 0 then
        echo("The " .. container_obj.name .. " appears to be empty or closed, attempting to open...")
        local result = dothistimeout("open #" .. container_obj.id, 2, "You open|already open|can't be opened|What were you")
        if result and Regex.test("You open|already open", result) then
            echo("Successfully opened " .. container_obj.name .. ", checking contents again...")
            dothistimeout("look in #" .. container_obj.id, 2, "In the .* you see|There is nothing|The .* is empty")
            pause(0.5)
            container_items = container_obj.contents
            if not container_items or #container_items == 0 then
                echo("The " .. container_obj.name .. " is empty")
                return
            else
                echo("Found items in " .. container_obj.name .. " after opening")
            end
        else
            echo("Could not open " .. container_obj.name .. " - it may not be openable or you may not have access")
            return
        end
    end

    -- Filter for magic/jewelry items
    local magic_items = {}
    for _, item in ipairs(container_items) do
        local item_types = item.type
        if item_types then
            for t in string.gmatch(item_types, "[^,]+") do
                t = string.match(t, "^%s*(.-)%s*$")
                if t == "magic" or t == "jewelry" then
                    table.insert(magic_items, item)
                    break
                end
            end
        end
    end

    if #magic_items == 0 then
        echo("No magic or jewelry items detected in " .. container_obj.name)
        return
    end

    echo("Analyzing magic and jewelry items with loresong...")
    silence_me()

    local detailed_items = {}
    for i, item in ipairs(magic_items) do
        echo("Analyzing " .. item.name .. "... (" .. i .. "/" .. #magic_items .. ")")

        if is_excluded(item.name) then goto continue end

        clear()
        put("recall #" .. item.id)
        local loresong_data = ""
        local unable_to_recall = false
        local deadline = os.time() + 3
        while os.time() < deadline do
            local line = get_noblock()
            if line then
                loresong_data = loresong_data .. line .. "\n"
                if string.find(line, "You are unable to recall the") then
                    unable_to_recall = true
                    break
                end
                if string.find(line, "You recall") or string.find(line, "contains no") then
                    break
                end
                if string.find(line, "It is estimated to be worth") then
                    break
                end
            else
                pause(0.05)
            end
        end

        if unable_to_recall then goto continue end

        local spell_name = nil
        local activation = nil
        local charges = nil
        local empowered_charges = nil

        local m = string.match(loresong_data, "imbedded with the (.+) spell")
        if m then spell_name = m end
        if not spell_name then
            m = string.match(loresong_data, "spell of (.+)[%.%s]")
            if m then spell_name = m end
        end
        if not spell_name then
            m = string.match(loresong_data, "(.+) spell")
            if m then spell_name = m end
        end

        m = string.match(loresong_data, "activated by (%w+)ing it")
        if m then
            local verb = str_lower(m)
            if verb == "wav" then activation = "WAVE"
            elseif verb == "tap" or verb == "tapp" then activation = "TAP"
            elseif verb == "rais" then activation = "RAISE"
            elseif verb == "rubb" then activation = "RUB"
            else activation = string.upper(verb) end
        end
        if not activation then
            local re_match = Regex.match("WAVE|INVOKE|RUB|RAISE|TOUCH|TURN|TAP", loresong_data)
            if re_match then activation = string.upper(re_match) end
        end

        m = string.match(loresong_data, "(%d+) charges?")
        if m then charges = tonumber(m) end
        if not charges then
            m = string.match(loresong_data, "(%d+) uses?")
            if m then charges = tonumber(m) end
        end

        m = string.match(loresong_data, "It is empowered and can be charged for an additional (%d+)")
        if m then empowered_charges = tonumber(m) end

        table.insert(detailed_items, {
            id = item.id,
            name = item.name,
            spell = spell_name or "Unknown",
            activation = activation or "Unknown",
            charges = charges or "Unknown",
            empowered_charges = empowered_charges or "not",
            container_id = container_obj.id,
            container_name = container_obj.name,
        })

        ::continue::
    end

    silence_me()

    echo("")
    echo("Magic & Jewelry Items Menu:")
    echo("===========================")

    display_menu(detailed_items, 1, show_bonuses, show_names)

    -- Save to CharSettings
    local cache_key = "trix_" .. string.gsub(str_lower(container_obj.name), " ", "_") .. "_items"
    CharSettings[cache_key] = Json.encode(detailed_items)
    echo("Scan results saved for " .. container_obj.name)
end

--------------------------------------------------------------------------------
-- Display helpers
--------------------------------------------------------------------------------

function display_menu(detailed_items, starting_number, show_bonuses, show_names)
    if not detailed_items or #detailed_items == 0 then return end

    starting_number = starting_number or 1

    -- Sort by spell number
    table.sort(detailed_items, function(a, b)
        local sa = get_spell_info(a.spell)
        local sb = get_spell_info(b.spell)
        local na = sa.num or 9999
        local nb = sb.num or 9999
        return na < nb
    end)

    -- Pre-calculate column widths for alignment
    local max_num_width = math.max(#tostring(starting_number + #detailed_items - 1), 2)
    local max_name_width = 4
    if show_names then
        for _, d in ipairs(detailed_items) do
            if #d.name > max_name_width then max_name_width = #d.name end
        end
    end
    local max_spell_width = 5
    for _, d in ipairs(detailed_items) do
        local si = get_spell_info(d.spell)
        local spell_display = si.num and ("[" .. si.num .. "] " .. d.spell) or d.spell
        if #spell_display > max_spell_width then max_spell_width = #spell_display end
    end
    local max_activation_width = 10
    for _, d in ipairs(detailed_items) do
        if #tostring(d.activation) > max_activation_width then max_activation_width = #tostring(d.activation) end
    end
    local max_charges_width = 7
    for _, d in ipairs(detailed_items) do
        if #tostring(d.charges) > max_charges_width then max_charges_width = #tostring(d.charges) end
    end
    local max_empowered_width = 9
    for _, d in ipairs(detailed_items) do
        if #tostring(d.empowered_charges) > max_empowered_width then max_empowered_width = #tostring(d.empowered_charges) end
    end

    -- Header
    if show_names then
        echo("| " .. pad_right("#", max_num_width) .. " | " .. pad_right("Item", max_name_width) .. " | " .. pad_right("Spell", max_spell_width) .. " | " .. pad_right("Activation", max_activation_width) .. " | " .. pad_right("Charges", max_charges_width) .. " | " .. pad_right("Empowered", max_empowered_width) .. " |")
        echo("|-" .. string.rep("-", max_num_width) .. "-|-" .. string.rep("-", max_name_width) .. "-|-" .. string.rep("-", max_spell_width) .. "-|-" .. string.rep("-", max_activation_width) .. "-|-" .. string.rep("-", max_charges_width) .. "-|-" .. string.rep("-", max_empowered_width) .. "-|")
    else
        echo("| " .. pad_right("#", max_num_width) .. " | " .. pad_right("Spell", max_spell_width) .. " | " .. pad_right("Activation", max_activation_width) .. " | " .. pad_right("Charges", max_charges_width) .. " | " .. pad_right("Empowered", max_empowered_width) .. " |")
        echo("|-" .. string.rep("-", max_num_width) .. "-|-" .. string.rep("-", max_spell_width) .. "-|-" .. string.rep("-", max_activation_width) .. "-|-" .. string.rep("-", max_charges_width) .. "-|-" .. string.rep("-", max_empowered_width) .. "-|")
    end

    for i, details in ipairs(detailed_items) do
        local si = get_spell_info(details.spell)
        local spell_display = si.num and ("[" .. si.num .. "] " .. details.spell) or details.spell

        local num_part = pad_right(tostring(starting_number + i - 1), max_num_width)
        local spell_part = pad_right(spell_display, max_spell_width)
        local activation_part = pad_right(tostring(details.activation), max_activation_width)
        local charges_part = pad_right(tostring(details.charges), max_charges_width)
        local empowered_part = pad_right(tostring(details.empowered_charges), max_empowered_width)

        if show_names then
            local name_part = pad_right(details.name, max_name_width)
            echo("| " .. num_part .. " | " .. name_part .. " | " .. spell_part .. " | " .. activation_part .. " | " .. charges_part .. " | " .. empowered_part .. " |")
        else
            echo("| " .. num_part .. " | " .. spell_part .. " | " .. activation_part .. " | " .. charges_part .. " | " .. empowered_part .. " |")
        end

        if show_bonuses and si.bonuses and #si.bonuses > 0 then
            local bonus_text = "Bonuses: " .. table.concat(si.bonuses, ", ")
            local content_width
            if show_names then
                content_width = max_name_width + max_spell_width + max_activation_width + max_charges_width + max_empowered_width + 12
            else
                content_width = max_spell_width + max_activation_width + max_charges_width + max_empowered_width + 9
            end
            echo("| " .. string.rep(" ", max_num_width) .. " | " .. pad_right(bonus_text, content_width) .. " |")
        end
    end
end

--------------------------------------------------------------------------------
-- Saved data access
--------------------------------------------------------------------------------

local function get_all_saved_items()
    local all_items = {}
    local keys = CharSettings.keys and CharSettings.keys() or {}
    for _, key in ipairs(keys) do
        if string.match(key, "^trix_.*_items$") then
            local raw = CharSettings[key]
            if raw then
                local ok, items = pcall(Json.decode, raw)
                if ok and type(items) == "table" then
                    for _, item in ipairs(items) do
                        table.insert(all_items, item)
                    end
                end
            end
        end
    end

    table.sort(all_items, function(a, b)
        local sa = get_spell_info(a.spell)
        local sb = get_spell_info(b.spell)
        return (sa.num or 9999) < (sb.num or 9999)
    end)

    return all_items
end

local function display_saved_items(show_bonuses, show_names)
    local keys = CharSettings.keys and CharSettings.keys() or {}
    local found_any = false
    local item_counter = 1

    echo("Saved Magic & Jewelry Items:")
    echo("============================")
    echo("")

    for _, key in ipairs(keys) do
        if string.match(key, "^trix_.*_items$") then
            local container_name = string.gsub(
                string.gsub(string.gsub(key, "^trix_", ""), "_items$", ""),
                "_", " ")
            local raw = CharSettings[key]
            if raw then
                local ok, items = pcall(Json.decode, raw)
                if ok and type(items) == "table" and #items > 0 then
                    found_any = true
                    echo(string.upper(container_name) .. ":")
                    echo(string.rep("-", #container_name + 1))
                    display_menu(items, item_counter, show_bonuses, show_names)
                    item_counter = item_counter + #items
                    echo("")
                end
            end
        end
    end

    if not found_any then
        echo("No saved scan results found. Use 'scan <container>' to analyze items first.")
    end
end

local function clear_all_saved_data()
    local cleared = 0
    local deleted_containers = {}
    local keys = CharSettings.keys and CharSettings.keys() or {}
    for _, key in ipairs(keys) do
        if string.match(key, "^trix_.*_items$") then
            local container_name = string.gsub(
                string.gsub(string.gsub(key, "^trix_", ""), "_items$", ""),
                "_", " ")
            table.insert(deleted_containers, container_name)
            CharSettings[key] = nil
            cleared = cleared + 1
        end
    end
    if cleared == 0 then
        echo("No trix data found to clear.")
    else
        echo("Cleared trix data for containers: " .. table.concat(deleted_containers, ", "))
        echo("Total containers cleared: " .. cleared)
    end
end

--------------------------------------------------------------------------------
-- Activation
--------------------------------------------------------------------------------

local function activate_item(menu_number, force)
    local all_items = get_all_saved_items()
    if #all_items == 0 then
        echo("No saved scan results found. Use 'scan <container>' to analyze items first.")
        return
    end

    if menu_number < 1 or menu_number > #all_items then
        echo("Error: Invalid menu number. Please choose between 1 and " .. #all_items)
        return
    end

    local selected = all_items[menu_number]
    local verb = str_lower(selected.activation)
    local item_id = selected.id
    local container_id = selected.container_id

    if type(selected.charges) == "number" and selected.charges < 2 and not force then
        echo("Error: Low charges, use with -f if you really want to use the charge")
        return
    end

    echo("Activating " .. selected.name .. " with " .. verb .. "...")
    fput("get #" .. item_id .. " from #" .. container_id)

    local pre_rt, post_rt
    if verb == "tap" or verb == "rub" then
        fput("wear #" .. item_id)
        pre_rt = checkcastrt()
        dothistimeout(verb .. " #" .. item_id, 3, ".")
        post_rt = checkcastrt()
        fput("remove #" .. item_id)
    elseif verb == "raise" or verb == "wave" then
        pre_rt = checkcastrt()
        dothistimeout(verb .. " #" .. item_id, 3, ".")
        post_rt = checkcastrt()
    else
        echo("Error: invalid activation type")
        fput("put #" .. item_id .. " in #" .. container_id)
        return
    end

    local activation_successful = post_rt > pre_rt
    fput("put #" .. item_id .. " in #" .. container_id)

    -- Update charge count in saved data if activation was successful
    if activation_successful and type(selected.charges) == "number" then
        local new_charge_count = selected.charges - 1
        local keys = CharSettings.keys and CharSettings.keys() or {}
        for _, key in ipairs(keys) do
            if string.match(key, "^trix_.*_items$") then
                local raw = CharSettings[key]
                if raw then
                    local ok, items = pcall(Json.decode, raw)
                    if ok and type(items) == "table" then
                        local updated = false
                        for idx, item in ipairs(items) do
                            if item.id == selected.id then
                                items[idx].charges = new_charge_count
                                updated = true
                                break
                            end
                        end
                        if updated then
                            CharSettings[key] = Json.encode(items)
                            echo("Updated charges for " .. selected.name .. " to " .. new_charge_count)
                            break
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main CLI
--------------------------------------------------------------------------------

local raw_args = {}
local full = Script.vars[0] or ""
for word in string.gmatch(full, "%S+") do
    table.insert(raw_args, word)
end

local show_bonuses = has_flag(raw_args, "-bonus") or has_flag(raw_args, "--bonus")
local show_names = has_flag(raw_args, "-name") or has_flag(raw_args, "--name")
local nf = non_flag_args(raw_args)

if #nf == 0 and not show_bonuses and not show_names then
    display_saved_items(false, false)
elseif #nf == 0 then
    display_saved_items(show_bonuses, show_names)
elseif nf[1] and string.match(nf[1], "^%d+$") then
    local menu_num = tonumber(nf[1])
    local force_flag = has_flag(raw_args, "-f") or has_flag(raw_args, "-force")
    activate_item(menu_num, force_flag)
elseif str_lower(nf[1]) == "clear" then
    clear_all_saved_data()
elseif str_lower(nf[1]) == "scan" then
    if not nf[2] or nf[2] == "" then
        echo("Usage: ;trix scan <container>")
    else
        scan_container(nf[2], show_bonuses, show_names)
    end
else
    respond("Usage:")
    respond("  ;trix                          - Display saved magic items")
    respond("  ;trix -bonus                   - Display saved magic items with bonuses")
    respond("  ;trix -name                    - Display saved magic items with item names")
    respond("  ;trix -bonus -name             - Display with both bonuses and names")
    respond("  ;trix scan <container>         - Scan container for magic items")
    respond("  ;trix scan <container> -bonus  - Scan container and display bonuses")
    respond("  ;trix scan <container> -name   - Scan container and display item names")
    respond("  ;trix <number>                 - Activate item by menu number")
    respond("  ;trix <number> -f              - Force activate even with 1 charge")
    respond("  ;trix clear                    - Delete all saved trix magic item data")
    respond("")
    respond("Examples:")
    respond("  ;trix scan backpack")
    respond("  ;trix scan backpack -bonus -name")
    respond("  ;trix -bonus -name")
    respond("  ;trix 1")
    respond("  ;trix 1 -f")
    respond("  ;trix clear")
end
