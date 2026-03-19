--- eforgery settings module
-- Load/save/display per-character settings via CharSettings.
local M = {}

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------

local DEFAULTS = {
    average_container = nil,
    keeper_container  = nil,
    oil_container     = nil,
    block_container   = nil,
    slab_container    = nil,
    scrap_container   = nil,
    glyph_container   = nil,
    material_noun     = nil,
    material_name     = nil,
    material_no       = nil,
    glyph_name        = nil,
    glyph_no          = nil,
    glyph_material    = nil,
    make_hammers      = false,
    surge             = false,
    squelch           = false,
    safe_keepers      = false,
    note_size         = 100000,
    debug             = false,
    first_run         = nil,
}

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------

function M.load()
    local s = {}
    for k, default in pairs(DEFAULTS) do
        local val = CharSettings[k]
        if val == "" then val = nil end
        if val ~= nil then
            -- coerce booleans stored as strings
            if val == "true" then val = true
            elseif val == "false" then val = false
            end
            s[k] = val
        else
            s[k] = default
        end
    end
    -- coerce numeric fields
    if s.material_no then s.material_no = tonumber(s.material_no) or 0 end
    if s.glyph_no then s.glyph_no = tonumber(s.glyph_no) or 0 end
    if s.note_size then s.note_size = tonumber(s.note_size) or 100000 end
    return s
end

---------------------------------------------------------------------------
-- Save
---------------------------------------------------------------------------

function M.save(s)
    for k, _ in pairs(DEFAULTS) do
        local val = s[k]
        if val == nil then
            CharSettings[k] = nil
        elseif type(val) == "boolean" then
            CharSettings[k] = tostring(val)
        else
            CharSettings[k] = tostring(val)
        end
    end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

function M.display(s)
    local function val_or(v) return v and tostring(v) or "(not set)" end
    respond("")
    respond("Current Forger Settings:")
    respond("  average             =>  " .. val_or(s.average_container))
    respond("  oil                 =>  " .. val_or(s.oil_container))
    respond("  keepers             =>  " .. val_or(s.keeper_container))
    respond("  slabs               =>  " .. val_or(s.slab_container))
    respond("  blocks  (slab cuts) =>  " .. val_or(s.block_container))
    respond("  scraps              =>  " .. val_or(s.scrap_container))
    respond("  glyph (name, container, order #, material)  =>  "
        .. val_or(s.glyph_name) .. " " .. val_or(s.glyph_container)
        .. " " .. val_or(s.glyph_no) .. " " .. val_or(s.glyph_material))
    respond("  material  (name, noun, order #)  =>  "
        .. val_or(s.material_name) .. " " .. val_or(s.material_noun)
        .. " " .. val_or(s.material_no))
    respond("  make_hammers        =>  " .. tostring(s.make_hammers))
    respond("  surge               =>  " .. tostring(s.surge))
    respond("  squelch             =>  " .. tostring(s.squelch))
    respond("  safe_keepers        =>  " .. tostring(s.safe_keepers))
    respond("  note_size           =>  " .. tostring(s.note_size))
    respond("  debug               =>  " .. tostring(s.debug))
    respond("")
    respond("IMPORTANT:")
    respond("   ;eforgery set <setting> <whatever>    for details type  ;eforgery help")
    respond("   Keepers, slabs, blocks, and scraps container must be different, but only the first 3 are required.")
    respond("   Leaving the average and scrap settings blank will cause those things to be thrown away!")
    respond("")
end

---------------------------------------------------------------------------
-- Handle set command
---------------------------------------------------------------------------

function M.handle_set(s, args)
    local key = args[2]
    if not key then
        respond("[eforgery] Usage: ;eforgery set <key> [value]")
        return
    end

    if key == "average" then
        s.average_container = args[3]
    elseif key == "keepers" then
        s.keeper_container = args[3]
    elseif key == "blocks" then
        s.block_container = args[3]
    elseif key == "oil" then
        s.oil_container = args[3]
    elseif key == "slabs" then
        s.slab_container = args[3]
    elseif key == "material" then
        s.material_name = args[3]
        s.material_noun = args[4]
        s.material_no = tonumber(args[5])
    elseif key == "glyph" then
        s.glyph_name = args[3]
        s.glyph_container = args[4]
        s.glyph_no = tonumber(args[5])
        s.glyph_material = args[6]
    elseif key == "make_hammers" then
        s.make_hammers = (args[3] == "true")
    elseif key == "scraps" then
        s.scrap_container = args[3]
    elseif key == "surge" then
        s.surge = (args[3] == "true")
    elseif key == "squelch" then
        s.squelch = (args[3] == "true")
    elseif key == "safe_keepers" then
        s.safe_keepers = (args[3] == "true")
    elseif key == "note_size" then
        s.note_size = tonumber(args[3]) or 100000
    elseif key == "debug" then
        s.debug = (args[3] == "true")
    else
        respond("[eforgery] Unknown setting: " .. key)
        return
    end

    M.save(s)
    respond("[eforgery] Settings saved!")
end

return M
