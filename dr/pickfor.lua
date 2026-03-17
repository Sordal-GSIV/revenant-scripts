--- @revenant-script
--- name: pickfor
--- version: 1.0.0
--- author: Gizmo
--- game: dr
--- description: Pick boxes for other people - accepts offered boxes, disarms/picks, returns them
--- tags: lockpicking, thief, service, boxes
---
--- Ported from pickfor.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;pickfor   - Wait for someone to offer you a box, then disarm/pick/return it

local person = nil

-- Difficulty assessment patterns
local too_hard = {
    "Prayer would be a good start",
    "You really don't have any chance",
    "You could just jump off a cliff",
    "You probably have the same shot as a snowball",
    "A pitiful snowball encased in the Flames",
}

local function is_too_hard(result)
    for _, pat in ipairs(too_hard) do
        if result:find(pat) then return true end
    end
    return false
end

local function disarm_box()
    waitrt()
    local result = DRC.bput("disarm id", {
        "aged grandmother could defeat this trap in her sleep",
        "laughable matter, you could do it blindfolded",
        "trivially constructed gadget",
        "simple matter for you to disarm",
        "should not take long with your skills",
        "precisely at your skill level",
        "with only minor troubles",
        "edge on you, but you've got a good shot",
        "You have some chance of being able to disarm",
        "odds are against you",
        "would be a longshot",
        "amazingly minimal chance",
        "Prayer would be a good start",
        "really don't have any chance",
        "jump off a cliff",
        "same shot as a snowball",
        "pitiful snowball",
        "fails to reveal to you",
    })

    if is_too_hard(result) then return false end
    if result:find("fails to reveal") then return disarm_box() end

    -- Choose disarm speed based on difficulty
    local speed = ""
    if result:find("grandmother") or result:find("blindfolded") then
        speed = "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") then
        speed = "quick"
    elseif result:find("some chance") or result:find("odds are against") or result:find("longshot") or result:find("minimal chance") then
        speed = "care"
    end

    -- Disarm loop
    while true do
        waitrt()
        local dr = DRC.bput("disarm " .. speed, {
            "proves too difficult",
            "not yet fully disarmed",
            "did not disarm",
            "caused something to shift",
            "unable to make any progress",
            "Roundtime",
        })
        if dr:find("Roundtime") then break end
        if dr:find("proves too difficult") or dr:find("not yet fully disarmed") then
            -- retry
        end
    end

    -- Analyze and harvest
    waitrt()
    DRC.bput("disarm anal", {"unable to determine", "Roundtime"})
    waitrt()
    local harvest_result = DRC.bput("disarm harvest", {
        "fumble around",
        "too much for it to be successfully harvested",
        "Roundtime",
    })
    if harvest_result:find("Roundtime") then
        waitrt()
        fput("stow left")
    end

    return true
end

local function pick_box()
    -- Analyze lock
    waitrt()
    DRC.bput("pick anal", {"unable to determine", "Roundtime"})

    -- Identify lock
    waitrt()
    local result = DRC.bput("pick id", {
        "fails to teach you anything",
        "laughable matter, you could do it blindfolded",
        "aged grandmother could",
        "trivially constructed",
        "should not take long",
        "simple matter for you to unlock",
        "with only minor troubles",
        "got a good shot at",
        "odds are against you",
        "some chance of being able to pick",
        "would be a longshot",
        "amazingly minimal chance",
        "Prayer would be a good start",
        "really don't have any chance",
        "jump off a cliff",
        "same shot as a snowball",
        "pitiful snowball",
    })

    if is_too_hard(result) then return false end
    if result:find("fails to teach") then return pick_box() end

    local speed = ""
    if result:find("grandmother") or result:find("blindfolded") then
        speed = "blind"
    elseif result:find("trivially") or result:find("simple matter") or result:find("should not take long") or result:find("minor troubles") then
        speed = "quick"
    elseif result:find("longshot") or result:find("minimal chance") then
        speed = "care"
    end

    -- Pick loop
    while true do
        waitrt()
        local pr = DRC.bput("pick " .. speed, {
            "unable to make any progress",
            "You discover another lock",
            "Roundtime",
        })
        if pr:find("Roundtime") then break end
        if pr:find("another lock") then
            return pick_box()
        end
    end
    return true
end

-- Main loop
while true do
    echo("*** WAITING FOR OFFER ***")
    waitfor(" offers you ")

    if checkright() then fput("stow right") end
    if checkleft() then fput("stow left") end

    fput("accept")
    pause(0.5)

    -- Try to identify who offered
    local line = get()
    if line then
        person = line:match("You accept (.+)'s offer")
    end

    if not person then
        echo("Could not determine who offered the box.")
        person = "unknown"
    end

    echo("Received box from: " .. person)

    -- Disarm
    local disarm_ok = disarm_box()
    if not disarm_ok then
        echo("*** THIS BOX IS VERY HARD ***")
        waitrt()
        fput("say }" .. person .. " Sorry, this box is beyond my skills")
        fput("give " .. person)
        -- Wait for them to accept
        waitfor("has accepted your offer")
    else
        -- Pick
        local pick_ok = pick_box()
        if not pick_ok then
            echo("*** LOCK TOO HARD ***")
            fput("say }" .. person .. " Sorry, this lock is beyond my skills")
        end
        waitrt()
        fput("give " .. person)
        -- Wait for accept or re-offer
        while true do
            local line2 = get()
            if line2 then
                if line2:find("has accepted your offer") then
                    break
                elseif line2:find("offers you") then
                    fput("say I am currently waiting for " .. person .. " to accept this box.")
                    fput("decline")
                end
            end
        end
    end
end
