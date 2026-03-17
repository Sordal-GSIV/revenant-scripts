--- @revenant-script
--- name: star_lore
--- version: 1.1.0
--- author: Starsworn
--- original: Ashraam
--- game: gs
--- description: Loop through items in left-hand container for loresinging (requires star_sing)
--- tags: lore,loresong,singing,container
---
--- Skips items already loresung. Fixes mixed sung/unsung containers,
--- interrupting a container, and imperfect container attempts.

local container = GameObj.left_hand()
if not container then
    echo("star_lore: nothing in your left hand")
    return
end

echo(tostring(container.name))
fput("look in my " .. container.noun)
pause(0.5)

local contents = container.contents
if not contents or #contents == 0 then
    echo("star_lore: container is empty")
    return
end

for _, item in ipairs(contents) do
    fput("get #" .. item.id)

    -- check if loresong still needs revealing
    local result = dothistimeout("recall #" .. item.id, 0.5,
        { "You must reveal the entire loresong of the" })

    if not result or not result:find("You must reveal the entire loresong of the") then
        fput("put #" .. item.id .. " in #" .. container.id)
    else
        -- needs singing
        Script.run("star_sing", "log")
        wait_while(function() return running("star_sing") end)
        fput("put #" .. item.id .. " in #" .. container.id)
    end
end
