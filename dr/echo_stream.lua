--- @revenant-script
--- name: echo_stream
--- version: 1.0
--- author: Jymamon
--- contributors: Tarjan
--- game: dr
--- description: Echo the raw game stream into the front-end client for debug purposes.
--- tags: debug, stream, raw

no_pause_all()

DownstreamHook.add("echo_stream_hook", function(line)
    respond(line)
    return line
end)

before_dying(function()
    DownstreamHook.remove("echo_stream_hook")
end)

while true do
    pause(1)
end
