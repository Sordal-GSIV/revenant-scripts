--- @revenant-script
--- name: mend
--- version: 0.0.2
--- author: Ondreian
--- game: gs
--- description: Heal the wounds of another player via transfer/cure
--- tags: healing,beta
---
--- Usage: ;mend Player1 Player2 ... PlayerN

if dead() then return end

--------------------------------------------------------------------------------
-- Wound classification patterns
--------------------------------------------------------------------------------

local APPRAISE_NOOP_RX = Regex.new("has no apparent injuries")
local APPRAISE_WOUNDS_RX = Regex.new("You take a quick appraisal of .+? and find that (?:he|she) has (.+?)\\.")
local APPRAISE_NOT_FOUND_RX = Regex.new("Appraise what\\?")
local APPRAISE_SCARS_RX = Regex.new("^(?:He|She) has")

local TRANSFER_SUCCESS_RX = Regex.new("wound gradually fades|nervous system damage gradually fades")
local TRANSFER_NOT_FOUND_RX = Regex.new("Transfer from whom\\?")
local TRANSFER_RETRY_RX = Regex.new("simply attempt the healing process again")

local TRANSFER_BLOOD_SOME_RX = Regex.new("You take some")
local TRANSFER_BLOOD_ALL_RX  = Regex.new("You take all")
local TRANSFER_BLOOD_NOOP_RX = Regex.new("Nothing happens")

-- Wound patterns by severity level
local WOUND_PATTERNS = {
    -- Level 1
    {
        { rx = Regex.new("a bruised (.+)"), loc = 1 },
        { rx = Regex.new("minor bruises about the head"), loc = "head" },
        { rx = Regex.new("minor bruises on (?:his|her) neck"), loc = "neck" },
        { rx = Regex.new("minor cuts and bruises on (?:his|her) (chest|abdom|back)"), loc = 1 },
        { rx = Regex.new("minor cuts and bruises on (?:his|her) ((left|right) (arm|hand|leg))"), loc = 1 },
        { rx = Regex.new("a strange case of muscle twitching"), loc = "nerves" },
    },
    -- Level 2
    {
        { rx = Regex.new("a swollen (.+)"), loc = 1 },
        { rx = Regex.new("minor lacerations about the head"), loc = "head" },
        { rx = Regex.new("moderate bleeding from (?:his|her) neck"), loc = "neck" },
        { rx = Regex.new("deep lacerations across (?:his|her) (chest|abdom|back)"), loc = 1 },
        { rx = Regex.new("a fractured and bleeding ((left|right) (arm|hand|leg))"), loc = 1 },
        { rx = Regex.new("a case of sporadic convulsions"), loc = "nerves" },
    },
    -- Level 3
    {
        { rx = Regex.new("a blinded (.+)"), loc = 1 },
        { rx = Regex.new("severe head trauma"), loc = "head" },
        { rx = Regex.new("snapped bones and serious bleeding from the neck"), loc = "neck" },
        { rx = Regex.new("deep gashes and serious bleeding from (?:his|her) (chest|abdom|back)"), loc = 1 },
        { rx = Regex.new("a completely severed ((left|right) (arm|hand|leg))"), loc = 1 },
        { rx = Regex.new("a case of uncontrollable convulsions"), loc = "nerves" },
    },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function find_pc(name)
    local pcs = GameObj.pcs()
    for _, pc in ipairs(pcs) do
        if pc.noun and pc.noun:lower():find(name:lower(), 1, true) == 1 then
            return pc
        end
    end
    return nil
end

local function parse_wounds(wound_str)
    local wounds = {}
    for severity, patterns in ipairs(WOUND_PATTERNS) do
        for _, p in ipairs(patterns) do
            local m = p.rx:match(wound_str)
            if m then
                local location
                if type(p.loc) == "number" then
                    location = m[p.loc] or "unknown"
                else
                    location = p.loc
                end
                wounds[#wounds + 1] = { location = location, severity = severity }
            end
        end
    end
    return wounds
end

local function transfer_wound(target, location)
    waitrt()
    waitcastrt()
    local result = dothistimeout("transfer #" .. target.id .. " " .. location, 3, {
        "wound gradually fades",
        "nervous system damage gradually fades",
        "Transfer from whom",
        "simply attempt the healing process again",
    })

    if result and result:find("simply attempt") then
        return transfer_wound(target, location)
    end
end

local function cure_blood()
    wait_while(function() return Char.mana < 10 end)
    while Char.percent_health < 100 do
        fput("cure")
        pause(3)
        waitcastrt()
        waitrt()
    end
end

local function transfer_blood(target)
    cure_blood()
    local result = dothistimeout("transfer #" .. target.id, 3, {
        "You take some",
        "You take all",
        "Nothing happens",
    })
    if result and result:find("You take some") then
        return transfer_blood(target)
    end
end

--------------------------------------------------------------------------------
-- Scan and heal a target
--------------------------------------------------------------------------------

local function scan_target(name)
    local target = find_pc(name)
    if not target then
        echo("Could not find " .. name)
        return
    end

    local result = dothistimeout("appraise #" .. target.id, 5, {
        "has no apparent injuries",
        "You take a quick appraisal",
        "Appraise what",
    })

    if not result then
        echo("No response from appraise")
        return
    end

    if APPRAISE_NOOP_RX:test(result) then
        echo(target.noun .. " is not injured")
        return
    end

    if APPRAISE_NOT_FOUND_RX:test(result) then
        echo(target.noun .. " is not here")
        return
    end

    local m = APPRAISE_WOUNDS_RX:match(result)
    if m then
        local wounds = parse_wounds(m[1])
        for _, wound in ipairs(wounds) do
            transfer_wound(target, wound.location)
        end

        -- Transfer blood if alive
        if not target.status or not target.status:find("dead") then
            transfer_blood(target)
        end

        -- Heal self
        cure_blood()
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

if running("healself") then Script.pause("healself") end

for i = 1, #Script.vars do
    local target_name = Script.vars[i]
    if target_name and target_name ~= "" then
        scan_target(target_name)
    end
end

if running("healself") then Script.unpause("healself") end
