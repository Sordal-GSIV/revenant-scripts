--- lockpick-maker/settings.lua
-- Persistent settings for lockpick-maker using CharSettings (per-character).
-- Container sack names are stored in UserVars so they persist per-character but are
-- shared if someone re-uses the same character across devices.

local M = {}

local DEFAULTS = {
    -- Container names
    broken_sack    = "",
    gem_sack       = "",
    inset_sack     = "",
    average_sack   = "",
    exceptional_sack = "",

    -- Customization
    custom_color      = "",
    custom_material   = "copper",
    custom_gem        = "",
    customizing_dye   = false,
    customizing_edge  = false,
    customizing_inset = false,
    use_keyring       = false,

    -- Bank note
    enable_withdraw_note = false,
    bank_note_amount     = "",

    -- Last GUI tab selections (materials arrays stored as comma-separated strings)
    selected_materials   = "",   -- remake broken picks
    selected_materials2  = "",   -- make new picks
}

--- Load settings from CharSettings, filling in defaults for missing keys.
function M.load()
    local s = {}
    for k, v in pairs(DEFAULTS) do
        local stored = CharSettings[k]
        if stored ~= nil then
            -- CharSettings stores everything as strings; coerce booleans back
            if type(v) == "boolean" then
                s[k] = (stored == true or stored == "true")
            else
                s[k] = stored
            end
        else
            s[k] = v
        end
    end
    return s
end

--- Save settings table back to CharSettings.
function M.save(s)
    for k, _ in pairs(DEFAULTS) do
        CharSettings[k] = s[k]
    end
end

return M
