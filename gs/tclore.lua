--- @revenant-script
--- name: tclore
--- version: 1.1.0
--- author: Tatterclaws
--- original: Ashraam
--- game: gs
--- description: Loop through items in left-hand container for loresinging (requires isingmin)
--- tags: lore,loresong,singing,container
---
--- Skips items already loresung. Fixes mixed sung/unsung containers,
--- interrupting a container, and imperfect container attempts.

local container = GameObj.left_hand()
if not container then
    echo("tclore: nothing in your left hand")
    return
end

echo(tostring(container.name))
fput("look in my " .. container.noun)
pause(0.5)

local contents = container.contents
if not contents or #contents == 0 then
    echo("tclore: container is empty")
    return
end

for _, item in ipairs(contents) do
    fput("get #" .. item.id)

    -- check if loresong still needs revealing
    local result = dothistimeout("recall #" .. item.id, 5,
        { "You must reveal the entire loresong of the" })

    if not result or not result:find("You must reveal the entire loresong of the") then
        fput("put #" .. item.id .. " in #" .. container.id)
    else
        -- needs singing
        Script.run("isingmin", "log")
        wait_while(function() return running("isingmin") end)
        fput("put #" .. item.id .. " in #" .. container.id)
    end
end
