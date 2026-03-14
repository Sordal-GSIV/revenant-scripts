local config = require("config")

local M = {}

function M.run(positional, flags)
    if #positional == 0 then
        respond("Usage: ;pkg remove <name>")
        return
    end

    local name = positional[1]
    local installed = config.load_installed()

    if not installed[name] then
        respond("Error: " .. name .. " is not installed")
        return
    end

    local info = installed[name]

    if info.type == "package" then
        if File.is_dir(name) then
            File.remove(name)
        end
    else
        local filename = name .. ".lua"
        if File.exists(filename) then
            File.remove(filename)
        end
    end

    installed[name] = nil
    config.save_installed(installed)
    respond("Removed " .. name)
end

return M
