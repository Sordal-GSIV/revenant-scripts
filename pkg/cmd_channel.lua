local config = require("config")

local M = {}

local VALID_CHANNELS = { stable = true, beta = true, dev = true }

function M.run(positional, flags)
    local cfg = config.load_config()

    if #positional == 0 then
        -- Show current global channel
        respond("Global channel: " .. (cfg.channel or "stable"))
        if cfg.overrides then
            local has_overrides = false
            for name, ch in pairs(cfg.overrides) do
                if not has_overrides then
                    respond("")
                    respond("Per-script overrides:")
                    has_overrides = true
                end
                respond("  " .. name .. " = " .. ch)
            end
        end
        return
    end

    if #positional == 1 then
        -- Set global channel
        local ch = positional[1]
        if not VALID_CHANNELS[ch] then
            respond("Error: invalid channel '" .. ch .. "'. Use: stable, beta, or dev")
            return
        end
        cfg.channel = ch
        config.save_config(cfg)
        respond("Global channel set to: " .. ch)

    elseif #positional == 2 then
        -- Set per-script override
        local name = positional[1]
        local ch = positional[2]
        if not VALID_CHANNELS[ch] then
            respond("Error: invalid channel '" .. ch .. "'. Use: stable, beta, or dev")
            return
        end
        if not cfg.overrides then cfg.overrides = {} end
        cfg.overrides[name] = ch
        config.save_config(cfg)
        respond("Channel for " .. name .. " set to: " .. ch)

    else
        respond("Usage: ;pkg channel [<channel>] or ;pkg channel <name> <channel>")
    end
end

return M
