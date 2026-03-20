--- GUI module for treasurewindow.
--- Creates and manages the loot/treasure display window using Revenant's
--- Gui widget system. Replaces the GTK3 window from Lich5 treasurewindow.lic.

local M = {}

local win = nil

--- Strip leading article from item name.
local function strip_article(name)
    return name
        :gsub("^[Aa]n?%s+", "")
        :gsub("^[Ss]ome%s+", "")
        :gsub("^[Tt]he%s+", "")
end

--- Build a clickable button that sends "get #id" when clicked.
local function make_treasure_button(t)
    local name = strip_article(t.name or t.noun or "?")
    local btn = Gui.button(name)
    btn:on_click(function()
        put("get #" .. t.id)
    end)
    return btn
end

--- Create the treasure window. No-op if already open.
function M.create()
    if win then return end

    win = Gui.window("Treasure", { width = 350, height = 450, resizable = true })
    win:on_close(function() win = nil end)

    local root = Gui.vbox()
    root:add(Gui.label("Waiting for loot data..."))
    win:set_root(Gui.scroll(root))
    win:show()
end

--- Close and destroy the window.
function M.close()
    if win then
        win:close()
        win = nil
    end
end

--- Returns true if the window is currently open.
function M.is_open()
    return win ~= nil
end

--- Update the window with current treasure list and killtracker summary.
--- @param treasures table   array of GameObj loot items passing the filter
--- @param kt_lines  table   killtracker summary lines (may be empty)
--- @param show_actions boolean whether to show Loot Room / Eloot action buttons
function M.update(treasures, kt_lines, show_actions)
    if not win then return end

    local root = Gui.vbox()

    -- ── Killtracker summary ───────────────────────────────────────────────────
    if kt_lines and #kt_lines > 0 then
        for _, line in ipairs(kt_lines) do
            if line:find("^%-%-%-") then
                root:add(Gui.separator())
            else
                root:add(Gui.label(line))
            end
        end
        root:add(Gui.separator())
    end

    -- ── Quick-action buttons ──────────────────────────────────────────────────
    if show_actions then
        local action_row = Gui.hbox()

        local loot_btn = Gui.button("Loot Room")
        loot_btn:on_click(function()
            put("loot room")
        end)
        action_row:add(loot_btn)

        local eloot_btn = Gui.button("Run Eloot")
        eloot_btn:on_click(function()
            if not Script.running("eloot") then
                Script.run("eloot")
            end
        end)
        action_row:add(eloot_btn)

        root:add(action_row)
        root:add(Gui.separator())
    end

    -- ── Treasure list ─────────────────────────────────────────────────────────
    root:add(Gui.section_header("Treasures: " .. #treasures))

    if #treasures == 0 then
        root:add(Gui.label("(none)"))
    else
        for _, t in ipairs(treasures) do
            root:add(make_treasure_button(t))
        end
    end

    win:set_root(Gui.scroll(root))
end

return M
