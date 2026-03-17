--- @revenant-script
--- name: hazardwindow
--- version: 1.0.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Dedicated window displaying room hazards with clickable spell actions
--- tags: wrayth, frontend, mod, window, hazards, apparatus, voids, rifts, clouds, vines, webs, spell cleave, point, click

hide_me()

put("<closeDialog id='HazardWindow'/><openDialog type='dynamic' id='HazardWindow' title='Hazards' target='HazardWindow' scroll='manual' location='main' justify='3' height='100' resident='true'><dialogData id='HazardWindow'></dialogData></openDialog>")

local last_hazard_ids = {}

local HAZARD_PATTERN = "acidic cloud of mist|glimmering boltstone apparatus|cloud|unearthly silvery blue globe|spiraling ghostly rift|sandstorm|vine|black void|windy vortex|web|whirlwind"
local DISPEL_PATTERN = "cloud|sandstorm|vine|web|whirlwind|unearthly silvery blue globe|spiraling ghostly rift"
local FULL_DISPEL_PATTERN = "cloud|sandstorm|vine|web|glimmering boltstone apparatus|unearthly silvery blue globe|spiraling ghostly rift"

local function matches_pattern(name, pattern)
    for word in pattern:gmatch("[^|]+") do
        if name:lower():find(word:lower(), 1, true) then
            return true
        end
    end
    return false
end

local function hazard_ids_key(hazards)
    local ids = {}
    for _, h in ipairs(hazards) do
        table.insert(ids, tostring(h.id))
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function push_hazards_to_window(hazards)
    local output = "<dialogData id='HazardWindow' clear='t'>"
    output = output .. "<label id='total' value='Hazards: " .. #hazards .. "' fontSize='32' />"

    for index, hazard in ipairs(hazards) do
        local hname = hazard.name
        local hid = hazard.id
        local i = index - 1

        if CMan.known("Spell Cleave") and matches_pattern(hname, DISPEL_PATTERN) then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if CMan.affordable('Spell Cleave') then fput('cman scleave #" .. hid .. "') end\" />"
        elseif Spell[209] and Spell[209].known and hname:lower():find("web") then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[209].affordable and Spell[209].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 209'); fput('cast #" .. hid .. "') end\" />"
        elseif Spell[602] and Spell[602].known and hname:lower():find("glimmering boltstone apparatus") then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[602].affordable and Spell[602].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 602'); fput('cast #" .. hid .. "') end\" />"
        elseif Spell[1218] and Spell[1218].known and matches_pattern(hname, FULL_DISPEL_PATTERN) then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[1218].affordable and Spell[1218].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 1218'); fput('cast #" .. hid .. "') end\" />"
        elseif Spell[1013] and Spell[1013].known and matches_pattern(hname, FULL_DISPEL_PATTERN) then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[1013].affordable and Spell[1013].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 1013'); fput('cast #" .. hid .. "') end\" />"
        elseif Spell[119] and Spell[119].known and matches_pattern(hname, FULL_DISPEL_PATTERN) then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[119].affordable and Spell[119].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 119'); fput('cast #" .. hid .. "') end\" />"
        elseif Spell[418] and Spell[418].known and matches_pattern(hname, FULL_DISPEL_PATTERN) then
            output = output .. "<link id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' cmd=\";e if Spell[418].affordable and Spell[418].known then if checkprep() ~= 'None' then fput('release') end; fput('prep 418'); fput('cast #" .. hid .. "') end\" />"
        else
            output = output .. "<label id='hazard_" .. i .. "' value='" .. hname .. "' justify='bottom' left='0' top='" .. (20 * (i + 1)) .. "' fontSize='32' />"
        end
    end

    output = output .. "</dialogData>"
    put(output)
end

-- Main update loop
while true do
    local loot = GameObj.loot() or {}
    local current_hazards = {}
    for _, obj in ipairs(loot) do
        if matches_pattern(obj.name, HAZARD_PATTERN) then
            table.insert(current_hazards, obj)
        end
    end

    local key = hazard_ids_key(current_hazards)
    local last_key = hazard_ids_key(last_hazard_ids)
    if key ~= last_key then
        last_hazard_ids = current_hazards
        push_hazards_to_window(current_hazards)
    end
    pause(0.025)
end
