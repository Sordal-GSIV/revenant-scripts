-- lib/frontend_focus.lua
-- Platform-specific frontend window refocus helper.
-- Stores the frontend PID and can bring it to the foreground.

local M = {}
local frontend_pid = nil

function M.set_pid(pid)
    frontend_pid = pid
end

function M.get_pid()
    return frontend_pid
end

-- Bring the frontend window to the foreground
-- Platform-specific: Linux uses xdotool, macOS uses osascript
function M.refocus()
    if not frontend_pid then
        respond("[focus] No frontend PID set")
        return false
    end

    -- Detect platform
    local f = io.popen("uname -s")
    if not f then return false end
    local os_name = f:read("*l") or ""
    f:close()

    if os_name == "Linux" then
        os.execute("xdotool search --pid " .. frontend_pid .. " windowactivate 2>/dev/null")
        return true
    elseif os_name == "Darwin" then
        -- macOS: bring process to front
        os.execute("osascript -e 'tell application \"System Events\" to set frontmost of (first process whose unix id is " .. frontend_pid .. ") to true' 2>/dev/null")
        return true
    end

    return false
end

return M
