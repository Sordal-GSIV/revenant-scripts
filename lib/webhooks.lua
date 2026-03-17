-- lib/webhooks.lua
-- Game-agnostic webhook notification system (Discord, Slack, Telegram, raw HTTP)

local M = {}
local endpoints = {}

-- ── Persistence ─────────────────────────────────────────────────────────────

local function save()
    local data = {}
    for name, ep in pairs(endpoints) do
        data[name] = { url = ep.url, format = ep.format, enabled = ep.enabled }
        if ep.chat_id then data[name].chat_id = ep.chat_id end
        if ep.token then data[name].token = ep.token end
    end
    CharSettings["webhooks"] = Json.encode(data)
end

local function load_config()
    local raw = CharSettings["webhooks"]
    if not raw then return end
    local ok, data = pcall(Json.decode, raw)
    if not ok or type(data) ~= "table" then return end
    for name, ep in pairs(data) do
        endpoints[name] = {
            url = ep.url,
            format = ep.format or "raw",
            enabled = ep.enabled ~= false,
            chat_id = ep.chat_id,
            token = ep.token,
            last_sent = 0,
            queue = {},
        }
    end
end

-- ── Format Adapters ─────────────────────────────────────────────────────────

local function format_discord(char, event, message, ts)
    return Json.encode({
        username = "Revenant",
        embeds = {{
            title = char,
            description = message,
            color = 3447003,
            footer = { text = event or "notification" },
            timestamp = ts,
        }}
    }), "application/json"
end

local function format_slack(char, event, message, ts)
    return Json.encode({
        text = char .. ": " .. message,
        username = "Revenant",
    }), "application/json"
end

local function format_telegram(char, event, message, ts)
    return Json.encode({
        text = char .. ": " .. message,
        parse_mode = "HTML",
    }), "application/json"
end

local function format_raw(char, event, message, ts)
    return char .. ": " .. message, "text/plain"
end

local formatters = {
    discord = format_discord,
    slack = format_slack,
    telegram = format_telegram,
    raw = format_raw,
}

-- ── Config API ──────────────────────────────────────────────────────────────

function M.add(name, config)
    if not config or not config.url then return false, "url required" end
    endpoints[name] = {
        url = config.url,
        format = config.format or "raw",
        enabled = config.enabled ~= false,
        chat_id = config.chat_id,
        token = config.token,
        last_sent = 0,
        queue = {},
    }
    save()
    return true
end

function M.remove(name)
    if not endpoints[name] then return false, "not found" end
    endpoints[name] = nil
    save()
    return true
end

function M.list()
    local result = {}
    for name, ep in pairs(endpoints) do
        result[name] = {
            url = ep.url,
            format = ep.format,
            enabled = ep.enabled,
        }
    end
    return result
end

function M.get(name)
    return endpoints[name]
end

function M.enable(name)
    if not endpoints[name] then return false end
    endpoints[name].enabled = true
    save()
    return true
end

function M.disable(name)
    if not endpoints[name] then return false end
    endpoints[name].enabled = false
    save()
    return true
end

-- ── Sending ─────────────────────────────────────────────────────────────────

local RATE_LIMIT = 5
local MAX_QUEUE = 50

function M.send_to(name, message, event)
    local ep = endpoints[name]
    if not ep or not ep.enabled then return false, "not found or disabled" end

    local char = GameState.name or "Unknown"
    local ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local formatter = formatters[ep.format] or formatters.raw
    local body, content_type = formatter(char, event or "notification", message, ts)

    local now = os.time()
    if now - ep.last_sent < RATE_LIMIT then
        if #ep.queue < MAX_QUEUE then
            ep.queue[#ep.queue + 1] = { body = body, content_type = content_type }
        end
        return true, "queued"
    end

    ep.last_sent = now

    -- Build URL (telegram needs bot token in URL)
    local url = ep.url
    if ep.format == "telegram" and ep.token then
        url = "https://api.telegram.org/bot" .. ep.token .. "/sendMessage"
        local tg_body = Json.encode({
            chat_id = ep.chat_id or ep.url,
            text = char .. ": " .. message,
            parse_mode = "HTML",
        })
        body = tg_body
    end

    local ok, resp = pcall(Http.post, url, body, { ["Content-Type"] = content_type })
    if not ok then return false, tostring(resp) end
    return true
end

function M.send(message, event)
    for name, ep in pairs(endpoints) do
        if ep.enabled then M.send_to(name, message, event) end
    end
end

function M.notify(event, message)
    M.send(message, event)
end

-- ── Convenience ─────────────────────────────────────────────────────────────

function M.death_alert()
    M.notify("death", (GameState.name or "Character") .. " has died!")
end

function M.disconnect_alert()
    M.notify("disconnect", (GameState.name or "Character") .. " disconnected")
end

function M.custom(text)
    M.notify("custom", text)
end

-- ── Event System ────────────────────────────────────────────────────────────

local event_handlers = {}

function M.on(event, callback)
    event_handlers[event] = event_handlers[event] or {}
    event_handlers[event][#event_handlers[event] + 1] = callback
end

function M.emit(event, data)
    M.notify(event, data or event)
    if event_handlers[event] then
        for _, cb in ipairs(event_handlers[event]) do pcall(cb, data) end
    end
end

-- ── Built-in Death Detection ────────────────────────────────────────────────

local was_dead = false
DownstreamHook.add("__webhooks_events", function(line)
    local dead_now = GameState.dead
    if dead_now and not was_dead then
        M.emit("death", (GameState.name or "Character") .. " has died!")
    end
    was_dead = dead_now
    return line
end)

-- ── Init ────────────────────────────────────────────────────────────────────

load_config()

return M
