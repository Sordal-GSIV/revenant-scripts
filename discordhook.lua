--- @revenant-script
--- name: discordhook
--- version: 1.0.0
--- author: elanthia-online
--- description: Discord webhook integration — send messages from any game to Discord
--- tags: discord,webhooks,utility
---
--- Setup:
---   ;discordhook set <webhook_url>    save your Discord webhook URL
---   ;discordhook test                 send a test message
---   ;discordhook send <message>       send a custom message
---   ;discordhook clear                remove stored webhook URL
---
--- Lua API (from other scripts):
---   local hook = require("discordhook")
---   hook.msg("Alert!", { title = "GS:Sordal", description = "Something happened" })

local Webhooks = require("lib/webhooks")

local M = {}

-- ── CLI ────────────────────────────────────────────────────────────────────

local function build_description()
    local parts = {}
    local room_title = GameState.room_title or "Unknown Room"
    local room_id = Map.current_room()
    parts[#parts + 1] = room_title .. (room_id and (" (#" .. room_id .. ")") or "")

    local npcs = GameObj.npcs()
    if npcs and #npcs > 0 then
        local names = {}
        for _, npc in ipairs(npcs) do names[#names + 1] = npc.name end
        parts[#parts + 1] = "NPCs: " .. table.concat(names, ", ")
    end

    local pcs = GameObj.pcs()
    if pcs and #pcs > 0 then
        local names = {}
        for _, pc in ipairs(pcs) do names[#names + 1] = pc.noun end
        parts[#parts + 1] = "Also here: " .. table.concat(names, ", ")
    end

    return table.concat(parts, "\n")
end

function M.msg(message, opts)
    opts = opts or {}
    local title = opts.title or ((GameState.game or "??") .. ":" .. (GameState.name or "??"))
    local description = opts.description or build_description()

    -- Use the Webhooks library to send
    local ok, err = Webhooks.send(message .. "\n" .. title .. "\n" .. description, "discord")
    if not ok then
        echo("discordhook: send failed: " .. tostring(err))
    end
end

-- ── Main ───────────────────────────────────────────────────────────────────

local action = Script.vars[1]

if not action or action == "" or action == "help" then
    echo("Usage:")
    echo("  ;discordhook set <url>   — save webhook URL")
    echo("  ;discordhook test        — send test message")
    echo("  ;discordhook send <msg>  — send custom message")
    echo("  ;discordhook clear       — remove webhook")

elseif action == "set" then
    local url = Script.vars[2]
    if not url or url == "" then
        echo("Usage: ;discordhook set <webhook_url>")
        return
    end
    Webhooks.add("discord_default", { url = url, format = "discord", enabled = true })
    echo("Discord webhook URL saved.")

elseif action == "clear" then
    Webhooks.remove("discord_default")
    echo("Discord webhook URL cleared.")

elseif action == "test" then
    local desc = build_description()
    Webhooks.send_to("discord_default", "Test message from Revenant\n" .. desc, "test")
    echo("Test message sent.")

elseif action == "send" then
    local parts = {}
    for i = 2, 20 do
        if Script.vars[i] and Script.vars[i] ~= "" then
            parts[#parts + 1] = Script.vars[i]
        end
    end
    local msg = table.concat(parts, " ")
    if msg == "" then
        echo("Usage: ;discordhook send <message>")
        return
    end
    Webhooks.send_to("discord_default", msg, "custom")
    echo("Message sent.")

else
    echo("Unknown command: " .. action .. " — use ;discordhook help")
end

return M
