local config = require("config")

local M = {}

function M.run(positional, flags)
    local installed = config.load_installed()
    local cfg = config.load_config()

    local count = 0
    for _ in pairs(installed) do count = count + 1 end

    if count == 0 then
        respond("No scripts installed via pkg.")
        return
    end

    respond(string.format("%-20s %-10s %-8s %-8s %s", "Name", "Version", "Channel", "Type", "Registry"))
    respond(string.rep("-", 70))

    -- Sort by name
    local names = {}
    for name in pairs(installed) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local info = installed[name]
        local effective_ch = config.get_channel(cfg, name)
        respond(string.format("%-20s %-10s %-8s %-8s %s",
            name,
            info.version or "?",
            effective_ch,
            info.type or "?",
            info.registry or "?"
        ))
    end

    respond("")
    respond(count .. " script(s) installed")
end

return M
