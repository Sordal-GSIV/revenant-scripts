--- @revenant-script
--- name: purifyl
--- version: 1.9
--- author: Leafiara
--- contributors: Aethor, Gibreficul, Shaelun
--- game: gs
--- description: Bard gem purification - sings to increase gem value, tracks boosts, sorts orbs
--- tags: bard, gems, purification, loresong
--- @lic-certified: complete 2026-03-19
---
--- Usage:
---   ;purifyl                                           -- purify gems in unsungcontainer
---   ;purifyl transfer <from_container> <to_container>  -- move worthy gems between containers
---
--- Setup (run once, include the quotes):
---   ;e UserVars.PurifyL.unsungcontainer = "pouch"
---   ;e UserVars.PurifyL.sungcontainer   = "sack"
---   ;e UserVars.PurifyL.orbcontainer    = "case"
---
--- Original: PurifyL.lic by Leafiara; previous versions by Aethor, Gibreficul, Shaelun
--- Changelog:
---   Jan 29, 2026 - Added new Hive gems post-loot changes
---   Jan 17, 2026 - Update for modern Ruby syntax
---   Oct 07, 2025 - Added Sailor's Grief gems
---   May 07, 2025 - Fix for more accurate regex
---   Mar 29, 2025 - Removed low-yield gems; cleaned up redundancies
---   May 28, 2018 - Original release (Leafiara, after Aethor, Gibreficul, Shaelun)

-- Gem nouns worth purifying (3k+ potential at capped bard level)
local GEMNOUNS = {
    "aetherstone", "alexandrite", "auboraline", "azel", "beryl", "blazestar",
    "bloodjewel", "bluerock", "caederine", "carnelian", "cinderstone", "despanal",
    "diamond", "doomstone", "duskjewel", "emerald", "eostone", "faenor",
    "feystone", "firedrop", "firestone", "galena", "goldstone", "heliotrope",
    "jacinth", "lichstone", "mekret", "nightstone", "pearl", "prehnite",
    "rhimar", "riftshard", "riftstone", "rivertear", "roestone", "rosepar",
    "sandruby", "saewehna", "shadowglass", "smoldereye", "snowstone", "spherine",
    "tanzanite", "thunderstone", "waterweb", "wraithaline", "wyrdshard",
}

-- Specific gem names worth purifying where the noun alone would be too broad
-- (conflicts with non-gems, or shares a noun with lower-value variants)
local GEMNAMES = {
    "aster opal", "azure salt sapphire", "black opal", "black-cored emerald orb",
    "blackened feystone core", "blue-green glacial core", "blue green lagoon opal",
    "blue sapphire", "blue shimmarglin sapphire", "blue sky opal",
    "blue-veined volcanic obsidian", "bluish black razern-bloom",
    "brilliant lilac glimaerstone", "brilliant wyrm's-tooth amethyst",
    "cabochon of striated grape jade", "carmine cinnabar stone",
    "cerulean glimaerstone", "chameleon agate", "chunk of pale blue ice stone",
    "chunk of snowy white ice stone", "cloud opal", "cloudy alexandrite shard",
    "craggy orb of coppery blue azurite", "cushion-cut vibrant carmine ruby",
    "dark blue tempest stone", "dark-forked ivory dendritic agate",
    "dark ivory aranthium-bloom", "deep blue mermaid's-tear sapphire",
    "deep blue tide's-heart opal", "dragon's-fang quartz", "dragon's-tear ruby",
    "dragonfire opal", "dragonsbreath sapphire", "dragonseye sapphire",
    "droplet of honey amber", "ebon winternight sapphire",
    "ebon-washed carnelian red ammolite", "faceted teal sapphire",
    "faceted wyrm's heart sapphire", "fiery gold-flecked sunstone",
    "flickering snowfire ruby", "fossilized bessho lizard spur",
    "fragment of pale green-blue aquamarine", "gilt-sprouted icy white quartz",
    "golden glimaerstone", "golden moonstone", "golden rhimar-bloom",
    "gold-haloed pale dragonseye sapphire", "gold-suffused resinous honey opal",
    "green alexandrite stone", "grooved burnt orange sea star",
    "indigo-cored stormy violet amethyst", "lavender shimmarglin sapphire",
    "lilac-crested molten gold ametrine", "misty grey deathstone",
    "misty silver crystalline spiral", "moonglae opal",
    "nearly black pomegranate red garnet", "nival everfrost shard",
    "niveous snowdrop", "opaline moonstone", "pale green moonstone",
    "pastel-hued wintersbite pearl", "peach glimaerstone",
    "pear-shaped greenish yellow citrine", "pearly grey ice stone",
    "Phoen's eye topaz", "piece of dusky blue sapphire", "pink sapphire",
    "plum-flecked ruby zoisite", "polished dark blue amber",
    "prismatic rose gold fire agate", "purple black thunderhead opal",
    "rainbow-swept royal blue moonstone", "raw chunk of titian orange sunstone",
    "red-clouded black moonstone", "red starstone", "red sunstone",
    "rich cerulean mermaid's-tear sapphire", "rough-edged matte white soulstone",
    "rutilated frostbite amethyst", "sanguine pyrope teardrop",
    "scaled indigo ammolite", "scintillating fiery scarlet starstone",
    "shadow amethyst", "shard of rainbow quartz", "silver-cored vortex stone",
    "silvery moonstone", "smooth dolphin stone disc",
    "sparkling ice blue dreamstone", "sylvarraend ruby",
    "tangerine wulfenite crystal", "thin blade of verdant sea glass",
    "tigerfang crystal", "twilight blue azurite crystal",
    "ultramarine glimaerstone", "uncut ruby", "uncut sunstone",
    "variegated mushroom-hued jasper", "verdigris Kai Toka tradebar",
    "versicolored sharp crimson crystal", "vinous gigasblood ruby",
    "vivid cobalt blue spinel", "volcanic blue larimar stone",
    "white sunstone", "yellow sunstone",
}

-- Reference: gem nouns/names deliberately excluded (kept for documentation)
-- "agate", "amber", "ambergris", "amethyst", "azurite", "bauxite", "bismuth",
-- "bloodstone", "brilliant red firebird stone", "carbuncle", "chalcedony",
-- "chrysoberyl", "chrysoprase", "coral", "cordierite", "crescent",
-- "dark grey dreamstone fragment", "deathstone", "diopside", "dreamstone",
-- "faenor-bloom", "feldspar", "fluorite", "fragment", "garnet", "gem",
-- "geode", "glacialite", "gypsum", "heliodor", "hematite", "hoarstone",
-- "honey-washed violet water sapphire", "hyacinth", "idocrase", "ivory",
-- "jade", "jasper", "labradorite", "lapis", "lazuli", "obsidian", "onyx",
-- "peridot", "pyrite", "quartz", "quartz crystal", "rainbowed ammolite shard",
-- "rainbow-hued oval abalone shell", "rock crystal",
-- "rust-speckled ivory slipper shell",
-- "scarlet-shot lustrous black bloodstone", "spinel", "stone", "starstone",
-- "teardrop of murky sanguine ruby", "tooth", "topaz", "tourmaline",
-- "turquoise", "tusk", "viridine", "wyrmwood", "zircon"

-- Build noun/name lookup sets for O(1) lookup
local NOUN_SET = {}
for _, v in ipairs(GEMNOUNS) do NOUN_SET[v] = true end
local NAME_SET = {}
for _, v in ipairs(GEMNAMES) do NAME_SET[v] = true end

local function is_worthy_gem(name, noun)
    if name:match("smooth stone") then return false end
    return NOUN_SET[noun] == true or NAME_SET[name] == true
end

-- Find first inventory container whose noun matches a plain substring
local function find_container(pattern)
    for _, obj in ipairs(GameObj.inv()) do
        if obj.noun and obj.noun:find(pattern, 1, true) then
            return obj
        end
    end
    return nil
end

-- True if the character cannot sing (muzzled by any status effect)
local function muckled()
    return stunned() or webbed() or bound() or silenced()
end

-- True if wounds are severe enough to need healing before singing
local function needs_healing()
    local function maxof(...)
        local m = 0
        for _, v in ipairs({...}) do if v > m then m = v end end
        return m
    end
    -- Head or nerve damage interferes with song
    if maxof(Wounds.head, Scars.head, Wounds.nsys, Scars.nsys) >= 2 then
        return true
    end
    -- Both arms/hands severely injured
    if maxof(Wounds.rightHand, Wounds.rightArm, Scars.rightHand, Scars.rightArm) >= 2
        and maxof(Wounds.leftHand, Wounds.leftArm, Scars.leftHand, Scars.leftArm) >= 2 then
        return true
    end
    -- Any hand/arm at critical level
    if maxof(Wounds.rightArm, Wounds.leftArm, Wounds.rightHand, Wounds.leftHand,
             Scars.rightArm, Scars.leftArm, Scars.rightHand, Scars.leftHand) == 3 then
        return true
    end
    return false
end

-- Wait for RT + cast RT to clear, then a brief anti-spam pause
local function wait_rt_all()
    wait_while(function() return checkrt() > 0 or checkcastrt() > 0 end)
    pause(0.9)
end

-- Format integer seconds as MM:SS
local function fmt_time(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

-- ── Setup ────────────────────────────────────────────────────────────────────

UserVars.PurifyL = UserVars.PurifyL or {}

if not UserVars.PurifyL.unsungcontainer
    or not UserVars.PurifyL.sungcontainer
    or not UserVars.PurifyL.orbcontainer then
    respond("\nFirst time running the script? Here's how to set it up!\n")
    respond(';e UserVars.PurifyL.unsungcontainer = "pouch"')
    respond(';e UserVars.PurifyL.sungcontainer   = "sack"')
    respond(';e UserVars.PurifyL.orbcontainer    = "case"')
    respond('\nInclude the quotes; just change the example container nouns to your own.')
    respond('unsungcontainer = unsung gems, sungcontainer = purified non-orbs,')
    respond('orbcontainer = orbs. (Sung and orb containers can be the same if you want,')
    respond('but all three fields must be set or the script will not run.)')
    respond('\nAfter setting the variables, open your containers and empty your right hand, then run again!')
    exit()
end

-- ── Transfer sub-command ─────────────────────────────────────────────────────

if Script.vars[1] and Script.vars[1]:match("transfer") then
    local from_noun = Script.vars[2]
    local to_noun   = Script.vars[3]
    if not from_noun or not to_noun then
        echo("Usage: ;purifyl transfer <from_container> <to_container>")
        exit()
    end
    local from_cont = find_container(from_noun)
    local to_cont   = find_container(to_noun)
    if not from_cont then echo("Cannot find container: " .. from_noun); exit() end
    if not to_cont   then echo("Cannot find container: " .. to_noun);   exit() end
    if from_cont.contents then
        for _, gem in ipairs(from_cont.contents) do
            if is_worthy_gem(gem.name, gem.noun) then
                put("_drag #" .. gem.id .. " #" .. to_cont.id)
                matchtimeout(1, "You put")
            end
        end
    end
    exit()
end

-- ── Pre-flight checks ────────────────────────────────────────────────────────

if GameObj.right_hand() ~= nil then
    echo("Ya got something in your right hand. Please put that away and then run this script again!")
    exit()
end

local unsung_cont = find_container(UserVars.PurifyL.unsungcontainer)
local mygems = {}
if unsung_cont and unsung_cont.contents then
    for _, gem in ipairs(unsung_cont.contents) do
        if is_worthy_gem(gem.name, gem.noun) then
            table.insert(mygems, gem.id)
        end
    end
end

local howmany = #mygems
if howmany == 0 then
    respond("Looks like you have no gems of high value to purify!\n")
    respond("(You might have some gems, but by default this script only purifies gems that a capped")
    respond("bard could generally take to at least 3000 silvers. Alternatively, if you're sure you")
    respond("have gems worth purifying, try LOOKing in your " .. UserVars.PurifyL.unsungcontainer)
    respond("and then run this script again.)")
    exit()
end

-- ── Run state ────────────────────────────────────────────────────────────────

local purified    = 0
local orbs        = 0
local shattered   = 0
local alreadyorbs = 0
local totalboost  = 0
local mytime      = os.time()

-- ── Main loop ────────────────────────────────────────────────────────────────

for _, gem_id in ipairs(mygems) do
    local processed = purified + shattered + orbs + alreadyorbs

    -- Progress banner (first gem: intro; subsequent: running stats)
    if processed == 0 then
        respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
        respond("~ PurifyL by Leafiara")
        respond("~ Looks like there are " .. howmany .. " gems in your " .. UserVars.PurifyL.unsungcontainer .. "!")
        respond("~ (Not counting junky ones we're not purifying.)")
        respond("~ Purified gems will go into your " .. UserVars.PurifyL.sungcontainer .. "...")
        respond("~ And orbs will go into your " .. UserVars.PurifyL.orbcontainer .. "!")
        respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
    else
        local runtime   = os.time() - mytime
        local remaining = howmany - processed
        local avgtime   = math.max(1, math.floor(runtime + 0.5) / processed)
        respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
        respond("~ PurifyL by Leafiara")
        respond("~ Purified " .. purified .. ", orbified " .. orbs .. ", shattered " .. shattered .. "!")
        respond("~ Sorted " .. alreadyorbs .. " gems that were already orbs.")
        respond("~ " .. remaining .. " gems to go!")
        respond("~ Total time " .. fmt_time(runtime) .. " / " .. string.format("%d", math.floor(avgtime)) .. " seconds per gem")
        respond("~ Estimated time left: " .. fmt_time(remaining * avgtime))
        if (purified + orbs) > 0 then
            respond("~ " .. totalboost .. "% Total Boost / " .. string.format("%d", math.floor(totalboost / (purified + orbs))) .. "% Average Boost")
        end
        respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
    end

    wait_rt_all()

    -- Heal right hand if critically wounded before picking up the gem
    if Wounds.rightHand == 3 then
        Script.run("useherbs")
        wait_until(function() return not running("useherbs") end)
    end

    put("_drag #" .. gem_id .. " right")

    local orbed       = false
    local preorbed    = false
    local done        = false
    local pct_boost   = 0
    local smoothercount = 0

    while not done do
        wait_until("Need some mana!", function() return mana() >= 20 end)
        wait_while(function() return muckled() end)
        wait_while(function() return needs_healing() end)
        wait_rt_all()

        multifput("prep 1004", "sing #" .. gem_id)
        local result = matchwait(
            "turn as the very essence",
            "gem becomes more perfect",
            "shatter",
            "crack",
            "must be holding",
            "what were you",
            "appearing smoother and more pure",
            "improves somewhat",
            "cannot be",
            "Sing Roundtime",
            "Spell Hindrance",
            "song misfires"
        )

        -- Already-orb: gem resonates and reports it can't be purified further
        if result:match("resonates") and result:match("cannot be purified") then
            preorbed = true
            done     = true

        -- Max value reached: gem vibrates and reports it can't be purified further
        elseif result:match("vibrates") and result:match("cannot be purified") then
            purified = purified + 1
            done     = true

        -- Improvement or risky-stop messages (all increment boost before deciding fate)
        elseif result:match("more perfect") or result:match("what were you")
            or result:match("improves somewhat") or result:match("crack")
            or result:match("shatter") or result:match("must be holding")
            or result:match("smoother and more pure") or result:match("song misfires") then

            if result:match("smoother and more pure") then
                smoothercount = smoothercount + 1
            end

            pct_boost  = pct_boost + 5
            totalboost = totalboost + 5

            if pct_boost == 5 then
                respond(" Bonus: +" .. pct_boost .. "% of max value")
            else
                respond(" Bonus: +" .. pct_boost .. "%")
            end

            -- Check the very next game line to catch the orb-conversion message
            local nextline = get()
            if nextline and nextline:match("very essence") then
                orbed = true
                done  = true
            elseif result:match("shatter") then
                respond(" ...if it hadn't blown up, anyway. So close!")
                shattered  = shattered + 1
                totalboost = totalboost - pct_boost
                pct_boost  = 0
                wait_while(function() return stunned() end)
                done = true
            elseif result:match("smoother and more pure") then
                -- Stop on the second "smoother" (too risky to continue)
                if smoothercount == 2 then
                    purified      = purified + 1
                    pct_boost     = 0
                    smoothercount = 0
                    done          = true
                end
                -- First "smoother": continue singing
            elseif result:match("crack") or result:match("improves somewhat")
                or result:match("what were you") or result:match("cannot")
                or result:match("must be holding") or result:match("song misfires") then
                purified      = purified + 1
                pct_boost     = 0
                smoothercount = 0
                done          = true
            end

        -- Direct orb message (no prior improvement line in the same result)
        elseif result:match("very essence") then
            orbed = true
            done  = true
        end

        -- Safety exit: unhandled result that signals we should stop
        if not done and result then
            if result:match("what were you") or result:match("cannot")
                or result:match("must be holding") or result:match("shatter")
                or result:match("song misfires") then
                done = true
            end
        end
    end  -- while not done

    -- Sort the gem into its destination container
    if orbed then
        fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.orbcontainer)
        orbs          = orbs + 1
        pct_boost     = 0
        smoothercount = 0
    end

    if preorbed then
        fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.orbcontainer)
        alreadyorbs   = alreadyorbs + 1
        pct_boost     = 0
        smoothercount = 0
    end

    -- If still holding the gem (purified / cracked / stopped), stow it
    if GameObj.right_hand() ~= nil then
        fput("put #" .. gem_id .. " in my " .. UserVars.PurifyL.sungcontainer)
        pct_boost     = 0
        smoothercount = 0
    end

    wait_while(function() return stunned() end)
end  -- for each gem

-- ── Final summary ─────────────────────────────────────────────────────────────

local runtime   = os.time() - mytime
local processed = purified + shattered + orbs + alreadyorbs

if processed == 0 then
    respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
else
    local remaining = howmany - processed
    local avgtime   = math.max(1, math.floor(runtime + 0.5) / processed)
    respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
    respond("~ PurifyL by Leafiara")
    respond("~ Purified " .. purified .. ", orbified " .. orbs .. ", shattered " .. shattered .. "!")
    respond("~ Sorted " .. alreadyorbs .. " gems that were already orbs.")
    respond("~ Total time " .. fmt_time(runtime) .. " / " .. string.format("%d", math.floor(avgtime)) .. " seconds per gem")
    respond("~ Estimated time left: " .. fmt_time(remaining * avgtime))
    if (purified + orbs) > 0 then
        respond("~ Total Boost / Average Boost: " .. totalboost .. "% / " .. string.format("%d", math.floor(totalboost / (purified + orbs))) .. "%")
    end
    respond("~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~")
end
