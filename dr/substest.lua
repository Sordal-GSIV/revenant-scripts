--- @revenant-script
--- name: substest
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Downstream hook substitution test script
--- tags: testing, hooks, substitution

local substitute = function(server_string)
    if not server_string or server_string:match("^%s*$") then
        return nil
    end
    if server_string:match("THIS IS A TEST FOR SUBS") then
        return "TEXT HAS BEEN CHANGED"
    end
    return server_string
end

DownstreamHook.remove("substest")
DownstreamHook.add("substest", substitute)
before_dying(function()
    DownstreamHook.remove("substest")
end)
