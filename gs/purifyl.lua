--- @revenant-script
--- name: purifyl
--- version: 1.9
--- author: Leafiara
--- contributors: Aethor, Gibreficul, Shaelun
--- game: gs
--- description: Bard gem purification script - sings to gems to increase their value
--- tags: bard, gems, purification, loresong
---
--- Usage: ;purifyl
--- Setup: Set UserVars.PurifyL.unsungcontainer, sungcontainer, orbcontainer

UserVars.PurifyL = UserVars.PurifyL or {}

if not UserVars.PurifyL.unsungcontainer or not UserVars.PurifyL.sungcontainer or not UserVars.PurifyL.orbcontainer then
    respond("First time? Set up containers:")
    respond(";e UserVars.PurifyL.unsungcontainer = 'pouch'")
    respond(";e UserVars.PurifyL.sungcontainer = 'sack'")
    respond(";e UserVars.PurifyL.orbcontainer = 'case'")
    exit()
end

local GEMNOUNS = {"aetherstone","alexandrite","blazestar","bloodjewel","diamond","doomstone","emerald","feystone","firedrop","firestone","jacinth","lichstone","nightstone","pearl","riftshard","riftstone","roestone","sandruby","shadowglass","snowstone","tanzanite","thunderstone","wraithaline","wyrdshard"}

local function is_worthy_gem(name, noun)
    for _, gn in ipairs(GEMNOUNS) do
        if noun == gn then return true end
    end
    return false
end

if not GameObj.right_hand.name:match("empty") then
    echo("Right hand must be empty!")
    exit()
end

-- Gather gems from container
local mygems = {}
local container = GameObj.inv_find(UserVars.PurifyL.unsungcontainer)
if container and container.contents then
    for _, gem in ipairs(container.contents) do
        if is_worthy_gem(gem.name, gem.noun) and not gem.name:match("smooth stone") then
            table.insert(mygems, gem.id)
        end
    end
end

if #mygems == 0 then
    respond("No gems of high value to purify!")
    exit()
end

local purified, orbs, shattered = 0, 0, 0
local start_time = os.time()

respond("~ PurifyL by Leafiara ~")
respond("~ " .. #mygems .. " gems in your " .. UserVars.PurifyL.unsungcontainer .. " ~")

for _, gem_id in ipairs(mygems) do
    waitrt(); waitcastrt()
    put("_drag #" .. gem_id .. " right")

    local done = false
    while not done do
        wait_until(function() return checkmana() >= 20 end)
        waitrt()
        fput("prep 1004")
        fput("sing #" .. gem_id)
        local result = matchwait("very essence", "cannot be purified", "shatter", "improves somewhat", "smoother and more pure", "Sing Roundtime")

        if result:match("very essence") then
            fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.orbcontainer)
            orbs = orbs + 1; done = true
        elseif result:match("cannot be purified") then
            fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.sungcontainer)
            purified = purified + 1; done = true
        elseif result:match("shatter") then
            shattered = shattered + 1; done = true
        elseif result:match("improves somewhat") or result:match("smoother") then
            purified = purified + 1
            if not GameObj.right_hand.name:match("empty") then
                fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.sungcontainer)
            end
            done = true
        end
    end
end

local runtime = os.time() - start_time
respond("~ Purified " .. purified .. ", orbified " .. orbs .. ", shattered " .. shattered .. " ~")
respond("~ Time: " .. string.format("%02d:%02d", runtime / 60, runtime % 60) .. " ~")
