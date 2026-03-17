--- @revenant-script
--- name: moonbot
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Walk to moon observation room, start moonwatch, and idle with TDP checks
--- tags: moonmage, moon, afk, training

DRCT.walk_to(820)
stop_script("moonwatch")
start_script("moonwatch", {"correct", "debug"})
fput("awake")
fput("sleep")
fput("avoid !drag")
fput("avoid !hold")
fput("avoid !join")
fput("avoid !dancing")

while true do
    pause(120)
    fput("tdp")
end
