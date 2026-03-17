--- @revenant-script
--- name: terror_watch
--- version: 1.2.5
--- author: Ensayn
--- game: gs
--- description: Monitor eerie cry effects and display enemy IDs with SSR results and TTL
--- tags: monitoring, combat, targeting, terror
---
--- Usage: ;terror_watch [help|cleanup]

if script.vars[1] == "help" then
    respond("terror_watch - Monitor eerie cry terror effects")
    respond(";terror_watch       - Start monitoring")
    respond(";terror_watch help  - Show help")
    respond(";kill terror_watch  - Stop")
    exit()
end

local watching = false
local terror_start = 0
local terror_times = {}
local terror_ssr = {}

echo("Terror Watch started")

add_hook("downstream", "terror_watch", function(xml)
    if xml:match("You let loose an eerie, modulating cry") then
        watching = true
        terror_start = os.time()
    end

    -- Clean old entries
    local now = os.time()
    for id, t in pairs(terror_times) do
        if now - t > 60 then terror_times[id] = nil; terror_ssr[id] = nil end
    end

    if watching and now - terror_start > 10 then watching = false end

    -- Capture SSR
    local ssr = xml:match("%[SSR result: (%d+)")

    -- Terror effect
    if xml:match("looks at you in utter terror") then
        local id = xml:match('exist="(%d+)"')
        if id then
            terror_times[id] = terror_times[id] or now
            if ssr then terror_ssr[id] = ssr end
            local suffix = "(ID:" .. id .. ")"
            if ssr then suffix = suffix .. "(SSR:" .. ssr .. ")" end
            -- Enhance display
            local name = xml:match('>([^<]+)</a>.*looks at you')
            if name then
                xml = xml:gsub('>' .. name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. '</a>',
                    '>' .. name .. ' ' .. suffix .. '</a>')
            end
        end
    end

    -- Fear wearing off
    if xml:match("shakes off the fear") then
        local id = xml:match('exist="(%d+)"')
        if id and terror_times[id] then
            local ttl = string.format("%.1f", now - terror_times[id])
            local suffix = "(TTL:" .. ttl .. "s)"
            if terror_ssr[id] then suffix = "(SSR:" .. terror_ssr[id] .. ")" .. suffix end
            terror_times[id] = nil; terror_ssr[id] = nil
        end
    end

    return xml
end)

before_dying(function() remove_hook("downstream", "terror_watch") end)
while true do pause(1) end
