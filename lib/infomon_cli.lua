--- Infomon CLI command routing.
--- Loaded by builtins to intercept ;infomon commands.

UpstreamHook.add("__infomon_cli", function(line)
    local cmd = line:match("^;infomon%s*(.*)$")
    if not cmd then return line end

    cmd = cmd:match("^%s*(.-)%s*$")  -- trim

    if cmd == "" or cmd == "help" then
        respond("Usage: ;infomon [sync | reset | show [full] | effects [true|false]]")
    elseif cmd == "sync" then
        respond("Infomon: syncing...")
        Infomon.sync()
        respond("Infomon: sync complete.")
    elseif cmd == "reset" then
        respond("Infomon: resetting database and syncing...")
        Infomon.reset()
        respond("Infomon: reset complete.")
    elseif cmd == "show" then
        Infomon.show(false)
    elseif cmd == "show full" then
        Infomon.show(true)
    elseif cmd:match("^effects") then
        local val = cmd:match("^effects%s+(%w+)")
        if val == "true" then
            Infomon.set_effects(true)
            respond("Infomon: effect durations enabled.")
        elseif val == "false" then
            Infomon.set_effects(false)
            respond("Infomon: effect durations disabled.")
        else
            local current = Infomon.effects()
            Infomon.set_effects(not current)
            respond("Infomon: effect durations " .. (not current and "enabled" or "disabled") .. ".")
        end
    else
        respond("Unknown infomon command: " .. cmd)
    end

    return ""  -- swallow the command
end)
