--- lockpick-maker/gui.lua
-- Four-tab GUI for Lockpick Maker.
-- Tabs: Customization | Broken Lockpicks | Make New Lockpicks | Containers
-- Returns a result table (or nil if the user closed without starting).

local M = {}

-- ── Static data ──────────────────────────────────────────────────────────────

local COLORS = {
    "ale brown", "alabaster", "amber", "amaranth pink", "amethyst", "amethyst purple",
    "apricot", "apple green", "ashen", "ash grey", "auburn", "azure", "azure blue",
    "azure green", "azure mist", "azure violet", "baby blue", "banana yellow", "berry red",
    "bile green", "black", "black cherry", "black opal", "black pearl", "blue",
    "blue-black", "blue-green", "blue-grey", "blue-violet", "blush", "blush pink", "bone",
    "bone white", "brick red", "bright golden", "bright green", "bright pink", "bright red",
    "bright white", "brilliant white", "bronze", "bronze brown", "brown",
    "brown camouflage", "burgundy", "burnished gold", "burnt umber", "caramel-hued",
    "cardinal red", "carrot orange", "celadon", "celestial blue", "cerise", "cerulean",
    "champagne", "charcoal", "charcoal black", "chartreuse", "cherry red",
    "chestnut brown", "chrome", "cinereous", "cobalt", "cobalt blue", "coal black",
    "copper", "coppery brown", "coppery gold", "coral", "coral pink", "coral red",
    "cream", "creamy white", "crimson", "crimson red", "cucumber green", "cyan",
    "dapple grey", "dappled", "dark", "dark azure", "dark blue", "dark brown",
    "dark cerulean", "dark crimson", "dark cyan", "dark green", "dark grey",
    "dark purple", "dark red", "deep black", "deep blue", "deep brown", "deep chrome",
    "deep cordovan", "deep crimson", "deep ebony", "deep pink", "deep purple", "deep red",
    "deep violet", "denim", "dingy grey", "dove-colored", "drab grey", "dull black",
    "dull grey", "dun", "dusky black", "dusky blue", "dusky rose", "dusty rose",
    "earthen brown", "ebon", "ebon black", "ebony", "ecru", "emerald", "emerald green",
    "fiery orange", "fiery red", "flame red", "flaxen", "forest green", "fuschia",
    "ghostly white", "ginger", "glacial blue", "glacial white", "gleaming white",
    "glossy black", "glossy blue", "golden", "goldenrod", "grape", "grass green",
    "green", "green camouflage", "green-layered camouflage", "grey", "grey-blue",
    "grey-green", "greyish blue", "hazel", "hazel-brown", "hemlock green", "henna",
    "honey gold", "honey-colored", "hot pink", "hunter green", "ice", "ice blue",
    "ice green", "ice white", "icy blue", "indigo", "inky black", "iron grey",
    "iridescent black", "ivory", "ivory white", "ivy green", "jade", "jade green",
    "jet black", "kelp", "lavender", "lemon", "lemon yellow", "light blue", "light brown",
    "light green", "light grey", "light orange", "light pink", "light purple", "light red",
    "lilac", "lily white", "linen", "magenta", "mahogany", "mahogany brown",
    "malachite green", "maroon", "matte black", "midnight", "midnight black",
    "midnight blue", "midnight ebon", "mint", "mint green", "mist", "misty grey",
    "moonlight silver", "moonshade black", "moss", "moss green", "mottled black",
    "mottled green", "mulberry", "murky black", "murky indigo", "mushroom grey", "navy",
    "navy blue", "nightshade purple", "nut brown", "oak brown", "obsidian",
    "obsidian black", "ochre", "ocher", "ocean", "ocean blue", "olive", "olive green",
    "onyx", "onyx black", "opal", "opaline", "orange", "orchid", "orchid pink",
    "pale blue", "pale golden", "pale green", "pale grey", "pale jade", "pale pink",
    "pale violet", "pale white", "pale yellow", "peach", "peach-colored", "peacock",
    "peacock blue", "pearlescent", "pearl", "pearl grey", "pearly white", "periwinkle",
    "persimmon", "pink", "pink-layered camouflage", "pitch black", "platinum",
    "platinum grey", "plum", "plum-colored", "powder blue", "pristine white", "puce",
    "pure white", "pumpkin", "pumpkin orange", "radiant white", "rainbow", "raspberry",
    "raspberry red", "raven black", "red", "red-orange", "red-speckled black",
    "red-tinged", "rich cream", "roan", "rose", "rose pink", "rose red", "rose-colored",
    "roseate", "rosy pink", "rosy red", "royal blue", "royal purple", "ruby", "ruby red",
    "ruddy crimson", "rust", "rust-colored", "russet", "sable", "sage", "sage green",
    "salmon", "salmon pink", "sand", "sand-colored", "sandstone", "sanguine", "sapphire",
    "sapphire blue", "scarlet", "scorched black", "sea", "sea blue", "sea green",
    "seaweed green", "shadow", "shadowy", "shadowy black", "shamrock", "shamrock green",
    "shell", "silvery", "silvery blue", "silvery green", "silvery white", "sky",
    "sky blue", "slate", "slate-colored", "smalt blue", "smoke", "smoky", "smoky grey",
    "snow", "snow white", "sooty black", "sorrel", "spring green", "spruce",
    "stark white", "steel blue", "steel grey", "stone", "stone grey", "storm",
    "storm grey", "stormy blue", "stormy grey", "straw", "sun", "sun yellow", "sunset",
    "sunset orange", "sunshine", "tan", "tan brown", "tangerine", "taupe", "taupe grey",
    "tawny", "tawny sable", "tawny yellow", "teal", "teal blue", "thistle", "tomato",
    "twilight", "twilight black", "twilight blue", "twilight grey", "ultramarine",
    "umber", "verdant", "verdant green", "veridian", "vermilion", "vermilion red",
    "violet", "violet blue", "violet red", "viridian", "viridian green", "void black",
    "wheat", "white", "white gold", "wine", "wine red", "winter", "wisteria",
    "woodland camouflage", "yellow", "yellow-green", "yellow orange",
}

local EDGE_MATERIALS = {
    "copper", "brass", "bronze", "iron", "steel", "silver", "gold", "mithril", "ora",
    "alum", "imflass", "vultite", "vaalorn", "mithglin", "invar", "veniom", "laje", "rhimar",
}

local EDGE_WARNINGS = {
    veniom  = "Warning: Veniom edging only available in Wehnimer's Landing Guild!",
    mithglin = "Warning: Mithglin edging only available in Ta'Illistim Guild!",
    invar   = "Warning: Invar edging only available in Zul Logoth Guild!",
    laje    = "Warning: Laje edging only available in Solhaven Guild!",
    rhimar  = "Warning: Rhimar edging only available in Icemule Trace Guild!",
    vaalorn = "Warning: Vaalorn edging only available in Ta'Vaalor Guild!",
}

local ALL_MATERIALS = {
    "silver", "gold", "steel", "copper", "brass", "ora", "mithril", "laje",
    "alum", "vultite", "rolaren", "veniom", "kelyn", "invar", "golvern", "vaalin",
}

-- ── Helper: split comma-separated string into a set ──────────────────────────

local function csv_to_set(s)
    local t = {}
    if not s or s == "" then return t end
    for item in (s .. ","):gmatch("([^,]+),") do
        t[item:match("^%s*(.-)%s*$")] = true
    end
    return t
end

local function set_to_csv(t)
    local parts = {}
    for k, _ in pairs(t) do
        parts[#parts + 1] = k
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- ── Main show function ────────────────────────────────────────────────────────

--- Show the 4-tab GUI.
-- @param settings  Current settings table (from settings.lua).
-- @param broken_picks  Table mapping material -> count of broken picks found.
-- @param inventory_summary  Array of display strings from inventory scan.
-- @return result table on success, nil if user closed without starting:
--   result.action           = "remake" | "new" | "exit"
--   result.selected_remake  = table of material names to remake from broken
--   result.selected_new     = table of material names to make fresh
--   result.settings         = updated settings table (always saved on any button press)
function M.show(settings, broken_picks, inventory_summary)
    local win = Gui.window("Lockpick Maker v2.3", { width = 560, height = 520, resizable = true })
    local root = Gui.vbox()

    -- ── Tab bar ──────────────────────────────────────────────────────────────
    local tabs = Gui.tab_bar({ "Customization", "Broken Lockpicks", "Make New Lockpicks", "Containers" })
    root:add(tabs)

    -- Result state communicated back from callbacks
    local result = nil

    ---------------------------------------------------------------------------
    -- Tab 1: Customization
    ---------------------------------------------------------------------------
    local pg1 = Gui.vbox()
    pg1:add(Gui.section_header("Customization Options"))
    pg1:add(Gui.separator())

    -- Color / edging / gem combos in a horizontal row
    local row_combos = Gui.hbox()

    local combo_color = Gui.editable_combo({
        text    = settings.custom_color or "",
        hint    = "Dye color",
        options = COLORS,
    })
    local combo_edge = Gui.editable_combo({
        text    = settings.custom_material or "copper",
        hint    = "Edging material",
        options = EDGE_MATERIALS,
    })

    -- Build gem list from inventory_summary
    local gem_items = { "" }
    for _, line in ipairs(inventory_summary or {}) do
        local name, _ = line:match("^(.+):%s*(%d+)")
        if name then
            gem_items[#gem_items + 1] = name:match("^%s*(.-)%s*$"):lower()
        end
    end
    local combo_gem = Gui.editable_combo({
        text    = settings.custom_gem or "",
        hint    = "Inset gem",
        options = gem_items,
    })

    row_combos:add(Gui.label("Color:"))
    row_combos:add(combo_color)
    row_combos:add(Gui.label("Edge:"))
    row_combos:add(combo_edge)
    row_combos:add(Gui.label("Inset:"))
    row_combos:add(combo_gem)
    pg1:add(row_combos)

    -- Checkboxes
    local chk_dye    = Gui.checkbox("Enable Dye",    settings.customizing_dye   or false)
    local chk_edge   = Gui.checkbox("Enable Edging", settings.customizing_edge  or false)
    local chk_inset  = Gui.checkbox("Enable Inset",  settings.customizing_inset or false)
    local chk_keyring = Gui.checkbox(
        "Keyring Mode (place exceptional picks on keyring)",
        settings.use_keyring or false)
    local row_cbs = Gui.hbox()
    row_cbs:add(chk_dye)
    row_cbs:add(chk_edge)
    row_cbs:add(chk_inset)
    pg1:add(row_cbs)
    pg1:add(chk_keyring)

    -- Bank note
    pg1:add(Gui.separator())
    local chk_banknote = Gui.checkbox(
        "Withdraw bank note for bars",
        settings.enable_withdraw_note or false)
    pg1:add(chk_banknote)
    local row_note = Gui.hbox()
    row_note:add(Gui.label("Bank Note Amount:"))
    local inp_note_amount = Gui.input({
        text        = tostring(settings.bank_note_amount or ""),
        placeholder = "e.g. 100000",
    })
    row_note:add(inp_note_amount)
    pg1:add(row_note)
    pg1:add(Gui.label("Note is used to buy lockpick material bars at the guild."))

    -- Edge warning label (updated dynamically)
    local lbl_edge_warning = Gui.label("")

    local function update_edge_warning()
        local mat = combo_edge:get_text():lower():match("^%s*(.-)%s*$")
        local warning = EDGE_WARNINGS[mat] or ""
        lbl_edge_warning:set_text(warning)
    end
    combo_edge:on_change(function() update_edge_warning() end)
    pg1:add(lbl_edge_warning)
    update_edge_warning()

    -- Save customization button
    local btn_save_cust = Gui.button("Save Customization")
    local lbl_cust_status = Gui.label("")
    btn_save_cust:on_click(function()
        settings.custom_color        = combo_color:get_text()
        settings.custom_material     = combo_edge:get_text()
        settings.custom_gem          = combo_gem:get_text()
        settings.customizing_dye     = chk_dye:get_checked()
        settings.customizing_edge    = chk_edge:get_checked()
        settings.customizing_inset   = chk_inset:get_checked()
        settings.use_keyring         = chk_keyring:get_checked()
        settings.enable_withdraw_note = chk_banknote:get_checked()
        settings.bank_note_amount    = inp_note_amount:get_text()
        local label_color = settings.customizing_dye   and settings.custom_color    or "none"
        local label_mat   = settings.customizing_edge  and settings.custom_material or "none"
        local label_gem   = settings.customizing_inset and settings.custom_gem      or "none"
        lbl_cust_status:set_text(
            "Saved: Color=" .. label_color ..
            " Edge=" .. label_mat ..
            " Inset=" .. label_gem ..
            " Keyring=" .. (settings.use_keyring and "yes" or "no"))
    end)
    pg1:add(btn_save_cust)
    pg1:add(lbl_cust_status)

    tabs:set_tab_content(1, Gui.scroll(pg1))

    ---------------------------------------------------------------------------
    -- Tab 2: Broken Lockpicks
    ---------------------------------------------------------------------------
    local pg2 = Gui.vbox()
    pg2:add(Gui.section_header("Broken Lockpicks"))
    pg2:add(Gui.label("Select which broken lockpicks to remake:"))
    pg2:add(Gui.separator())

    local remake_cbs = {}  -- material -> checkbox widget
    local prev_remake_set = csv_to_set(settings.selected_materials or "")
    local has_broken = false
    for _, mat in ipairs(ALL_MATERIALS) do
        local count = broken_picks[mat] or 0
        if count > 0 then
            has_broken = true
            local cb = Gui.checkbox(
                string.format("%d broken %s lockpick%s", count, mat, count == 1 and "" or "s"),
                prev_remake_set[mat] == true)
            remake_cbs[mat] = cb
            pg2:add(cb)
        end
    end
    if not has_broken then
        pg2:add(Gui.label("(No broken lockpicks found in your broken sack.)"))
    end

    local btn_remake = Gui.button("Start Remaking Selected")
    btn_remake:on_click(function()
        -- Collect customization from tab 1 widgets
        settings.custom_color        = combo_color:get_text()
        settings.custom_material     = combo_edge:get_text()
        settings.custom_gem          = combo_gem:get_text()
        settings.customizing_dye     = chk_dye:get_checked()
        settings.customizing_edge    = chk_edge:get_checked()
        settings.customizing_inset   = chk_inset:get_checked()
        settings.use_keyring         = chk_keyring:get_checked()
        settings.enable_withdraw_note = chk_banknote:get_checked()
        settings.bank_note_amount    = inp_note_amount:get_text()

        local selected_set = {}
        local selected = {}
        for mat, cb in pairs(remake_cbs) do
            if cb:get_checked() then
                selected_set[mat] = true
                selected[#selected + 1] = mat
            end
        end
        settings.selected_materials = set_to_csv(selected_set)
        result = {
            action          = "remake",
            selected_remake = selected,
            selected_new    = {},
            settings        = settings,
        }
        win:close()
    end)
    pg2:add(btn_remake)

    tabs:set_tab_content(2, Gui.scroll(pg2))

    ---------------------------------------------------------------------------
    -- Tab 3: Make New Lockpicks
    ---------------------------------------------------------------------------
    local pg3 = Gui.vbox()
    pg3:add(Gui.section_header("Make New Lockpicks"))
    pg3:add(Gui.label("Select which new lockpicks to craft from scratch:"))
    pg3:add(Gui.separator())

    -- Build previous selection set for pre-checking boxes
    local prev_new_set = csv_to_set(settings.selected_materials2 or "")

    -- Two-column layout
    local half = math.ceil(#ALL_MATERIALS / 2)
    local new_cbs = {}
    local cols = Gui.hbox()
    local col_left  = Gui.vbox()
    local col_right = Gui.vbox()
    for i, mat in ipairs(ALL_MATERIALS) do
        local cb = Gui.checkbox("Make " .. mat .. " lockpick", prev_new_set[mat] == true)
        new_cbs[mat] = cb
        if i <= half then
            col_left:add(cb)
        else
            col_right:add(cb)
        end
    end
    cols:add(col_left)
    cols:add(col_right)
    pg3:add(cols)

    local btn_new = Gui.button("Start Making New")
    btn_new:on_click(function()
        settings.custom_color        = combo_color:get_text()
        settings.custom_material     = combo_edge:get_text()
        settings.custom_gem          = combo_gem:get_text()
        settings.customizing_dye     = chk_dye:get_checked()
        settings.customizing_edge    = chk_edge:get_checked()
        settings.customizing_inset   = chk_inset:get_checked()
        settings.use_keyring         = chk_keyring:get_checked()
        settings.enable_withdraw_note = chk_banknote:get_checked()
        settings.bank_note_amount    = inp_note_amount:get_text()

        local selected_set = {}
        local selected_list = {}
        for mat, cb in pairs(new_cbs) do
            if cb:get_checked() then
                selected_set[mat] = true
                selected_list[#selected_list + 1] = mat
            end
        end
        settings.selected_materials2 = set_to_csv(selected_set)
        result = {
            action          = "new",
            selected_remake = {},
            selected_new    = selected_list,
            settings        = settings,
        }
        win:close()
    end)
    pg3:add(btn_new)

    tabs:set_tab_content(3, Gui.scroll(pg3))

    ---------------------------------------------------------------------------
    -- Tab 4: Containers
    ---------------------------------------------------------------------------
    local pg4 = Gui.vbox()
    pg4:add(Gui.section_header("Container Settings"))
    pg4:add(Gui.label("Set the noun (single word) of each container. These are saved per character."))
    pg4:add(Gui.separator())

    local function cont_row(parent, lbl, key)
        local row = Gui.hbox()
        row:add(Gui.label(lbl .. ":"))
        local inp = Gui.input({ text = settings[key] or "", placeholder = lbl })
        row:add(inp)
        parent:add(row)
        return inp
    end

    local inp_broken     = cont_row(pg4, "Broken Sack",     "broken_sack")
    local inp_gem        = cont_row(pg4, "Gem Sack",        "gem_sack")
    local inp_inset      = cont_row(pg4, "Inset Sack",      "inset_sack")
    local inp_average    = cont_row(pg4, "Average Sack",    "average_sack")
    local inp_exceptional = cont_row(pg4, "Exceptional Sack", "exceptional_sack")

    local lbl_cont_status = Gui.label("")
    local btn_save_cont = Gui.button("Save Containers")
    btn_save_cont:on_click(function()
        settings.broken_sack      = inp_broken:get_text():match("^%s*(.-)%s*$")
        settings.gem_sack         = inp_gem:get_text():match("^%s*(.-)%s*$")
        settings.inset_sack       = inp_inset:get_text():match("^%s*(.-)%s*$")
        settings.average_sack     = inp_average:get_text():match("^%s*(.-)%s*$")
        settings.exceptional_sack = inp_exceptional:get_text():match("^%s*(.-)%s*$")
        lbl_cont_status:set_text(
            "Saved! Restart the script to apply new container names.")
    end)
    pg4:add(btn_save_cont)
    pg4:add(lbl_cont_status)

    tabs:set_tab_content(4, Gui.scroll(pg4))

    ---------------------------------------------------------------------------
    -- Bottom: Close and Exit
    ---------------------------------------------------------------------------
    local btn_row  = Gui.hbox()
    local btn_exit = Gui.button("Close and Exit")
    btn_exit:on_click(function()
        -- Save whatever is currently in containers tab before closing
        settings.broken_sack      = inp_broken:get_text():match("^%s*(.-)%s*$")
        settings.gem_sack         = inp_gem:get_text():match("^%s*(.-)%s*$")
        settings.inset_sack       = inp_inset:get_text():match("^%s*(.-)%s*$")
        settings.average_sack     = inp_average:get_text():match("^%s*(.-)%s*$")
        settings.exceptional_sack = inp_exceptional:get_text():match("^%s*(.-)%s*$")
        settings.custom_color        = combo_color:get_text()
        settings.custom_material     = combo_edge:get_text()
        settings.custom_gem          = combo_gem:get_text()
        settings.customizing_dye     = chk_dye:get_checked()
        settings.customizing_edge    = chk_edge:get_checked()
        settings.customizing_inset   = chk_inset:get_checked()
        settings.use_keyring         = chk_keyring:get_checked()
        settings.enable_withdraw_note = chk_banknote:get_checked()
        settings.bank_note_amount    = inp_note_amount:get_text()
        result = { action = "exit", settings = settings }
        win:close()
    end)
    btn_row:add(btn_exit)
    root:add(btn_row)

    win:set_root(root)
    win:show()

    win:on_close(function()
        if not result then
            result = { action = "exit", settings = settings }
        end
    end)

    Gui.wait(win, "close")
    return result
end

return M
