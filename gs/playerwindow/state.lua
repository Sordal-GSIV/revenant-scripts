-- Shared mutable state for playerwindow
-- Required by all submodules; cached by Lua require, so all modules
-- share the same table instance.

local M = {
    -- Filter toggles
    filter_spam          = true,
    filter_animals       = false,
    filter_flares        = false,
    filter_combat_math   = false,

    -- Display settings
    single_column        = false,
    show_filter_buttons  = true,
    show_movement        = true,

    -- Group state
    group_display        = nil,
    group_dirty          = true,

    -- Loaded flare patterns (table of Regex objects, populated by init)
    flare_patterns       = {},

    -- Debug toggle
    debug_filter_enabled = false,

    -- Movement tracking (managed by filter module)
    pending_joins        = {},   -- { name = timestamp }
    confirmed_players    = {},   -- list of names announced as entered
    pending_leavers      = {},   -- list of names queued to announce leaving
    last_seen_players    = {},   -- names from last room-players component

    recent_self_movement               = false,
    skip_next_line                     = false,
    skip_next_after_player_component   = false,
}

return M
