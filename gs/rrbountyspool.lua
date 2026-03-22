--- @revenant-script
--- name: rrbountyspool
--- version: 0.40
--- author: Kaldonis
--- game: gs
--- description: River's Rest bounty spooler - moves to Adv Guild and gets preferred bounties
--- tags: RR, bounty
---
--- Usage:
---   ;rrbountyspool       - check for one bounty
---   ;rrbountyspool spool - use BOOST BOUNTY to keep checking
---   ;rrbountyspool stay  - leave you at bounty checkpoint

local foraging = true
local gems = false
local skinning = false
local bandits = false

local boost = script.vars[0] and script.vars[0]:lower() == "spool"
local return_origin = not (script.vars[0] and script.vars[0]:lower() == "stay")
local start_spot = Room.id

Script.run("go2", "advguild")

while true do
    local spool = false
    fput("ask Taskmaster about bounty")
    local result = matchwait("You have already been assigned", "creature problem", "gem dealer", "alchemist", "furrier", "Come back in about", "your thoughts drift")

    if result:match("your thoughts drift") then
        echo("Need to wait...quitting!"); exit()
    elseif result:match("Come back in about %d+ minutes") then
        if boost then
            fput("boost bounty")
            local br = matchwait("You do not have any Bounty Boosts", "You have activated")
            if br:match("You do not have any") then echo("No more boosts!"); exit() end
        else
            if return_origin then Script.run("go2", tostring(start_spot)) end
            fput("bounty"); exit()
        end
    elseif result:match("You have already been assigned") or result:match("creature problem") then
        fput("ask Taskmaster about remo"); fput("ask Taskmaster about remo")
    elseif result:match("gem dealer") and gems then
        Script.run("go2", "gemshop"); fput("ask dealer about bounty")
        if return_origin then Script.run("go2", tostring(start_spot)) end
        fput("bounty"); exit()
    elseif result:match("alchemist") and foraging then
        Script.run("go2", "alchemist"); fput("ask Lomara about bounty")
        if return_origin then Script.run("go2", tostring(start_spot)) end
        fput("bounty"); exit()
    elseif result:match("furrier") and skinning then
        Script.run("go2", "furrier"); fput("ask furrier about bounty")
        if return_origin then Script.run("go2", tostring(start_spot)) end
        fput("bounty"); exit()
    else
        fput("ask Taskmaster about remo"); fput("ask Taskmaster about remo")
        spool = true
    end
    if not spool then break end
end
fput("bounty")
