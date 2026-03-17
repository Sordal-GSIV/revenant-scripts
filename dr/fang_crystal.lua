--- @revenant-script
--- name: fang_crystal
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Automate fang crystal summon/redeem/read process
--- tags: magic, summon, crystal

DRC.bput("get my summon", "You get")
DRC.bput("break my summon", "You remove")
DRC.bput("stow other summon", "You put")
DRC.bput("redeem summon", "Once you redeem")
DRC.bput("redeem summon", "The shadowy")
fput("read crystal")

while true do
    local line = get()
    if line then
        waitrt()
        if line:match("^The image is too dim to make out clearly") then
            fput("push crystal")
        elseif line:match("^The image is blurry and vague%.") then
            fput("rub crystal")
        elseif line:match("^The image is partially obscured by streaks of jittery color") then
            fput("tap crystal")
        elseif line:match("^You have earned merit") then
            return
        end
    end
end
