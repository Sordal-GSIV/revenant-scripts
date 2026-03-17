--- @revenant-script
--- name: enchant
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Enchanting helper - checks suffusion, casts 925, and reports resources
--- tags: enchant,925,magic

local function check_resources()
    fput("sense")
    fput("resource")
end

local function cast_enchant()
    local item = GameObj.right_hand()
    if not item then
        echo("enchant: nothing in your right hand")
        return
    end
    fput("prepare 925")
    local result = dothistimeout("channel " .. item.noun, 5, { "Success!" })
    if result and result:find("Success!") then
        waitrt()
        echo("Enchant was successful!")
        check_resources()
        local rh = GameObj.right_hand()
        if rh then fput("recall " .. rh.noun) end
    end
end

local function suffuse_estimate()
    local result = dothistimeout("suffuse estimate", 5,
        { "The service does not require any additional suffused energy." })
    if result and result:find("The service does not require any additional suffused energy.") then
        echo("It is safe to cast!")
        cast_enchant()
    else
        echo("It is NOT safe to cast!")
        Script.pause(Script.name)
    end
end

check_resources()
suffuse_estimate()
