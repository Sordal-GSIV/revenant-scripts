--- @revenant-script
--- name: webhooks
--- version: 1.0.0
--- author: Sordal
--- game: any
--- tags: utility, notifications, webhooks, discord
--- description: Webhook endpoint management — add, remove, enable, disable, test, and send to Discord/Slack/Telegram/raw HTTP endpoints
---
--- Revenant-native script. No Lich5 equivalent.
---
--- Usage:
---   ;webhooks                          List configured endpoints
---   ;webhooks list                     List configured endpoints
---   ;webhooks add <name> <url>         Add endpoint (default format: raw)
---   ;webhooks add <name> <url> --format=discord|slack|telegram|raw
---   ;webhooks remove <name>            Remove endpoint
---   ;webhooks enable <name>            Enable endpoint
---   ;webhooks disable <name>           Disable endpoint
---   ;webhooks test <name>              Send a test notification
---   ;webhooks send <message>           Send message to all enabled endpoints

local input = Script.vars[0] or ""
local first = input:match("^%s*(%S+)") or ""

if first == "" or first == "list" then
    local eps = Webhooks.list()
    local count = 0
    for name, ep in pairs(eps) do
        count = count + 1
        local status = ep.enabled and "enabled" or "disabled"
        respond(string.format("  %-15s %-8s %-8s %s", name, ep.format, status, ep.url))
    end
    if count == 0 then
        respond("No webhooks configured. Use: ;webhooks add <name> <url> [--format=discord]")
    end

elseif first == "add" then
    local rest = input:match("^%s*add%s+(.+)$")
    if not rest then
        respond("Usage: ;webhooks add <name> <url> [--format=discord|slack|telegram|raw]")
        return
    end
    local format = rest:match("%-%-format=(%S+)") or "raw"
    rest = rest:gsub("%s*%-%-format=%S+", "")
    local name, url = rest:match("^(%S+)%s+(%S+)")
    if not name or not url then
        respond("Usage: ;webhooks add <name> <url> [--format=discord|slack|telegram|raw]")
        return
    end
    local ok, err = Webhooks.add(name, { url = url, format = format })
    if ok then
        respond("Added webhook: " .. name .. " (" .. format .. ")")
    else
        respond("Error: " .. tostring(err))
    end

elseif first == "remove" or first == "delete" then
    local name = input:match("^%s*%S+%s+(%S+)")
    if not name then
        respond("Usage: ;webhooks remove <name>")
        return
    end
    local ok, err = Webhooks.remove(name)
    if ok then respond("Removed: " .. name)
    else respond("Error: " .. tostring(err)) end

elseif first == "test" then
    local name = input:match("^%s*test%s+(%S+)")
    if not name then
        respond("Usage: ;webhooks test <name>")
        return
    end
    respond("Sending test to " .. name .. "...")
    local ok, err = Webhooks.send_to(name, "Test notification from Revenant", "test")
    if ok then respond("Sent!") else respond("Failed: " .. tostring(err)) end

elseif first == "enable" then
    local name = input:match("^%s*enable%s+(%S+)")
    if name and Webhooks.enable(name) then respond("Enabled: " .. name)
    else respond("Usage: ;webhooks enable <name>") end

elseif first == "disable" then
    local name = input:match("^%s*disable%s+(%S+)")
    if name and Webhooks.disable(name) then respond("Disabled: " .. name)
    else respond("Usage: ;webhooks disable <name>") end

elseif first == "send" then
    local msg = input:match("^%s*send%s+(.+)$")
    if not msg then
        respond("Usage: ;webhooks send <message>")
        return
    end
    Webhooks.send(msg)
    respond("Sent to all enabled webhooks.")

else
    respond("Usage: ;webhooks [list|add|remove|test|enable|disable|send]")
end
