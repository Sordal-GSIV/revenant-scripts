--- @revenant-script
--- name: chrism_maker
--- version: 3.0.0
--- author: Timbalt
--- game: gs
--- tags: cleric, chrism, gems, automation
--- description: Automate chrism creation from orb gems with tracking
---
--- Original Lich5 authors: Timbalt, Aethor (original)
--- Ported to Revenant Lua from chrism-maker.lic v3.0.0
---
--- Usage:
---   ;chrism_maker              - process gems from orbsack
---   ;chrism_maker chrismarium  - put chrisms into chrismarium
---   ;chrism_maker help         - show setup help
--- Requires: ;vars set orbsack, chrismsack, lootsack

local function bold(text)
    put("<pushBold/>" .. text .. "<popBold/>")
end

if Script.current.vars[1] and Script.current.vars[1]:match("help") then
    bold("You need orbsack, chrismsack, and lootsack set via ;vars")
    bold(";chrism_maker chrismarium - use chrismarium mode")
    return
end

local orbsack = UserVars.get("orbsack")
local chrismsack = UserVars.get("chrismsack")
local lootsack = UserVars.get("lootsack")

if not orbsack or not chrismsack or not lootsack then
    respond("First time? Set up your containers:")
    respond(";vars set orbsack = <container>")
    respond(";vars set chrismsack = <container>")
    respond(";vars set lootsack = <container>")
    return
end

if Char.prof ~= "Cleric" then
    bold("You're not a Cleric, so this script does not apply to you.")
    return
end

local use_chrismarium = Script.current.vars[1] and Script.current.vars[1]:match("chrismarium")

before_dying(function()
    if use_chrismarium then
        if checkleft() == "chrismarium" or checkright() == "chrismarium" then
            fput("put my chrismarium in my " .. (UserVars.get("chrismariumsack") or lootsack))
        end
    else
        empty_hands()
    end
end)

if use_chrismarium then
    bold("Chrism Maker: Chrismarium mode enabled")
    fput("get my chrismarium from my " .. (UserVars.get("chrismariumsack") or lootsack))
    fput("swap")
end

-- Refresh gem list
bold("Refreshing list of orb gems")
wait(0.5)

-- Find container
local container = nil
for _, obj in ipairs(GameObj.inv()) do
    if obj.noun:lower() == orbsack:lower() then
        container = obj
        break
    end
end

if not container then
    bold("Error: Can't find container '" .. orbsack .. "'")
    return
end

fput("look in #" .. container.id)
wait(1)

local gem_list = {}
if container.contents then
    for _, obj in ipairs(container.contents) do
        if obj.type and obj.type:find("gem") then
            gem_list[#gem_list + 1] = obj
        end
    end
end

if #gem_list == 0 then
    bold("Error: No orb gems found in container '" .. container.noun .. "'")
    return
end

local start_time = os.time()
local successful = 0
local failures = 0
local total_mana = 0

bold("Total Orbs: " .. #gem_list)

for _, gem in ipairs(gem_list) do
    if checkmana() < 150 then
        bold("Waiting for mana...")
        wait_until(function() return checkmana() >= 150 end)
    end

    local initial_mana = checkmana()
    waitrt()
    waitcastrt()

    dothistimeout("get #" .. gem.id, 5, "^You remove")
    fput("prep 325")
    local result = dothistimeout("cast my " .. gem.noun, 5, "spiritual bond|shudders in your hand|blows away in the form")
    waitcastrt()

    if result and result:find("spiritual bond") then
        local check = dothistimeout("bless deity common 4", 3, "cobalt liquid")
        waitrt()
        waitcastrt()
        total_mana = total_mana + math.max(initial_mana - checkmana(), 0)

        if check and check:find("cobalt liquid") then
            successful = successful + 1
            wait(2)
            if use_chrismarium then
                fput("push my chrismarium")
            else
                fput("put " .. gem.noun .. " in my " .. chrismsack)
                wait(3)
            end
            bold("Chrismed " .. successful .. " out of " .. #gem_list)
        end
    else
        total_mana = total_mana + math.max(initial_mana - checkmana(), 0)
        fput("put " .. gem.noun .. " in my " .. lootsack)
        failures = failures + 1
        if failures > 0 then
            bold("Failed " .. failures .. " out of " .. #gem_list)
        end
    end
end

local elapsed = os.time() - start_time
local minutes = math.floor(elapsed / 60)
local seconds = elapsed % 60

bold("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
bold("Chrism Maker")
bold("Successful: " .. successful .. " out of " .. #gem_list)
if failures > 0 then bold("Failed: " .. failures) end
bold("Total mana used: " .. total_mana)
bold("Total time: " .. minutes .. " minutes and " .. seconds .. " seconds")
bold("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
