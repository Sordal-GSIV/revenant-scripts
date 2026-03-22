--- eforgery GUI setup module
-- Revenant Gui-based configuration window replacing Lich5 GTK GUI.
-- Original layout: single "Setup" page with two side-by-side frames:
--   Left: "Storage Options", Right: "Forging Options"
local settings_mod = require("eforgery/settings")
local M = {}

function M.show(state)
    local win = Gui.window("eForgery", { width = 680, height = 560, resizable = true })
    local root = Gui.vbox()

    local function add_entry(parent, label_text, value, tooltip)
        local row = Gui.hbox()
        local lbl = Gui.label(label_text)
        row:add(lbl)
        local inp = Gui.input({ text = value or "", placeholder = tooltip or "" })
        row:add(inp)
        parent:add(row)
        return inp
    end

    ---------------------------------------------------------------------------
    -- Split view: Storage (left) | Forging (right)
    ---------------------------------------------------------------------------
    local split = Gui.split_view({ direction = "horizontal", fraction = 0.5 })

    -- Left side: Storage Options
    local storage = Gui.vbox()
    storage:add(Gui.section_header("Storage Options"))
    storage:add(Gui.label("*MOUSE OVER FIELDS FOR INFORMATION*"))
    storage:add(Gui.separator())

    local inp_average   = add_entry(storage, "Average Container:",         state.average_container,
        "Container for average pieces (blank = trash)")
    local inp_keeper    = add_entry(storage, "Keeper Container:",          state.keeper_container,
        "Container for perfect pieces")
    local inp_oil       = add_entry(storage, "Oil Container:",             state.oil_container,
        "Container for tempering oil (blank for bronze/iron)")
    local inp_block     = add_entry(storage, "Cut Slab Container:",        state.block_container,
        "Container for cut slab blocks")
    local inp_slab      = add_entry(storage, "Fresh Slab Container:",      state.slab_container,
        "Container for raw slabs")
    local inp_scrap     = add_entry(storage, "Leftover Cut Container:",    state.scrap_container,
        "Container for scrap (blank = trash)")
    local inp_glyph_ct  = add_entry(storage, "Glyph Container:",          state.glyph_container,
        "Container for forging glyph")

    split:set_first(Gui.scroll(storage))

    -- Right side: Forging Options
    local forging = Gui.vbox()
    forging:add(Gui.section_header("Forging Options"))

    local inp_mat_name  = add_entry(forging, "Material Name:",      state.material_name, "e.g. bronze, steel, imflass")
    local inp_mat_noun  = add_entry(forging, "Material Noun:",      state.material_noun, "e.g. slab, bar, block")
    local inp_mat_no    = add_entry(forging, "Material Order #:",   state.material_no and tostring(state.material_no), "Order number from merchant")

    forging:add(Gui.separator())
    local inp_glyph_nm  = add_entry(forging, "Glyph Name:",        state.glyph_name, "e.g. blade-glyph")
    local inp_glyph_mat = add_entry(forging, "Glyph Material:",    state.glyph_material, "e.g. wax (blank for hammer glyphs)")
    local inp_glyph_no  = add_entry(forging, "Glyph Order #:",     state.glyph_no and tostring(state.glyph_no), "Order # (99 for custom, blank for hammer)")

    forging:add(Gui.separator())
    local chk_hammers = Gui.checkbox("Make FORGING-HAMMER pieces (workshop glyph)", state.make_hammers or false)
    forging:add(chk_hammers)
    local chk_surge   = Gui.checkbox("Use CMan Surge of Strength", state.surge or false)
    forging:add(chk_surge)
    local chk_squelch = Gui.checkbox("Squelch Forging Screen Scroll", state.squelch or false)
    forging:add(chk_squelch)
    local chk_safe = Gui.checkbox("MARK Best Pieces as Unsellable", state.safe_keepers or false)
    forging:add(chk_safe)

    split:set_second(Gui.scroll(forging))
    root:add(split)

    ---------------------------------------------------------------------------
    -- Save / Close buttons
    ---------------------------------------------------------------------------
    local btn_row = Gui.hbox()
    local btn_save  = Gui.button("Save & Close")
    local btn_close = Gui.button("Exit")
    btn_row:add(btn_save)
    btn_row:add(btn_close)
    root:add(btn_row)

    win:set_root(root)
    win:show()

    local saved = false

    btn_save:on_click(function()
        -- Read all values back
        state.average_container  = (inp_average:get_text() ~= "")   and inp_average:get_text()   or nil
        state.keeper_container   = (inp_keeper:get_text() ~= "")    and inp_keeper:get_text()    or nil
        state.oil_container      = (inp_oil:get_text() ~= "")       and inp_oil:get_text()       or nil
        state.block_container    = (inp_block:get_text() ~= "")     and inp_block:get_text()     or nil
        state.slab_container     = (inp_slab:get_text() ~= "")      and inp_slab:get_text()      or nil
        state.scrap_container    = (inp_scrap:get_text() ~= "")     and inp_scrap:get_text()     or nil
        state.glyph_container    = (inp_glyph_ct:get_text() ~= "")  and inp_glyph_ct:get_text()  or nil
        state.material_name      = (inp_mat_name:get_text() ~= "")  and inp_mat_name:get_text()  or nil
        state.material_noun      = (inp_mat_noun:get_text() ~= "")  and inp_mat_noun:get_text()  or nil
        state.material_no        = tonumber(inp_mat_no:get_text())
        state.glyph_name         = (inp_glyph_nm:get_text() ~= "")  and inp_glyph_nm:get_text()  or nil
        state.glyph_material     = (inp_glyph_mat:get_text() ~= "") and inp_glyph_mat:get_text() or nil
        state.glyph_no           = tonumber(inp_glyph_no:get_text())
        state.make_hammers       = chk_hammers:get_checked()
        state.surge              = chk_surge:get_checked()
        state.squelch            = chk_squelch:get_checked()
        state.safe_keepers       = chk_safe:get_checked()

        settings_mod.save(state)
        respond("[eforgery] Settings saved")
        saved = true
        win:close()
    end)

    btn_close:on_click(function()
        respond("[eforgery] Closed without saving")
        win:close()
    end)

    Gui.wait(win, "close")
    return saved
end

return M
