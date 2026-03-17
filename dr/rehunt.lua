--- @revenant-script
--- name: rehunt
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Notify when HUNT is available again (75 second cooldown)
--- tags: hunt, tracking, timer

while true do
    waitfor("You take note of all the tracks in the area, so that you can hunt anything nearby down")
    pause(75)
    echo("******************************")
    echo("*** You can use HUNT again ***")
    echo("******************************")
end
