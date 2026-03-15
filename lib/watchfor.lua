--- Watchfor: pattern → callback registration (Lich5 compatible).
--- Uses DownstreamHook internally. Callbacks are fire-and-forget observers
--- that never modify the game stream.

local M = {}
local _counter = 0
local _hooks = {}  -- script_name → {hook_name, ...}
local _cleanup_registered = {}  -- script_name → true

local function current_script()
    return Script.name or "_unknown"
end

local function ensure_cleanup(script_name)
    if _cleanup_registered[script_name] then return end
    _cleanup_registered[script_name] = true
    before_dying(function()
        M.clear()
    end)
end

function M.new(pattern, callback)
    local script_name = current_script()
    _counter = _counter + 1
    local hook_name = "__watchfor_" .. script_name .. "_" .. _counter

    DownstreamHook.add(hook_name, function(line)
        -- Test pattern and call callback, but ALWAYS return line unchanged
        if type(pattern) == "string" then
            if string.find(line, pattern) then
                local success, err = pcall(callback, line)
                if not success then
                    echo("Watchfor callback error: " .. tostring(err))
                end
            end
        end
        return line  -- never squelch
    end)

    if not _hooks[script_name] then _hooks[script_name] = {} end
    table.insert(_hooks[script_name], hook_name)
    ensure_cleanup(script_name)
end

function M.clear()
    local script_name = current_script()
    local hooks = _hooks[script_name]
    if hooks then
        for _, name in ipairs(hooks) do
            DownstreamHook.remove(name)
        end
        _hooks[script_name] = nil
    end
end

return M
