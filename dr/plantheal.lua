--- @revenant-script
--- name: plantheal
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Empath plant healing trainer - transfer wounds via EV, heal plant, train Empathy
--- tags: empath, healing, empathy, training, vela'tohr
---
--- Ported from plantheal.lic (Lich5) to Revenant Lua
---
--- Requires: common, common-items, events, common-arcana, common-healing, common-travel, drinfomon
---
--- YAML Settings:
---   plant_adc: true/false
---   plant_total_touch_count: 3
---   plant_custom_room: <room_id>
---   plant_heal_past_ML: false
---   plant_healing_room: <room_id>
---   plant_empathy_threshold: 24
---   plant_prep_room: <room_id>
---   waggle_sets.ev: { ... }
---   waggle_sets.plant_heal: { ... }

if not DRStats.empath then
    echo("Must be an Empath with Embrace of the Vela'Tohr to run this!")
    return
end

local settings = get_settings()
local adc = tostring(settings.plant_adc or false)
local total_touch = settings.plant_total_touch_count or 3
local custom_room = settings.plant_custom_room
local heal_past_ml = tostring(settings.plant_heal_past_ML or false)
local healing_room = settings.plant_healing_room or settings.safe_room
local threshold = settings.plant_empathy_threshold or 24
local prep_room = settings.plant_prep_room or 0
local ev_set = settings.waggle_sets and settings.waggle_sets["ev"]
local plant_heal_set = settings.waggle_sets and settings.waggle_sets["plant_heal"]

local plant_room = custom_room or nil
if not plant_room then
    local town_data = get_data("town")
    local ht = settings.force_healer_town or settings.hometown
    if town_data[ht] and town_data[ht].npc_empath then
        plant_room = town_data[ht].npc_empath.id
    end
end

if not ev_set then
    echo("Missing ev waggle_set in YAML!")
    return
end

if adc == "true" and not plant_heal_set then
    echo("ADC is true but missing plant_heal waggle_set!")
    return
end

Flags.add("heal-expire", "You feel the warmth in your flesh gradually subside.")

local plant_nouns = {"plant", "thicket", "bush", "briar", "shrub", "thornbush"}

local function find_plant()
    local objs = DRRoom.room_objs or {}
    for _, noun in ipairs(plant_nouns) do
        for _, obj in ipairs(objs) do
            if obj:find("vela.tohr " .. noun) then
                return noun
            end
        end
    end
    return nil
end

local function touch_plant(noun)
    return DRC.bput("touch " .. noun, {
        "Roundtime",
        "has no need of healing",
        "you have no empathic bond",
        "Touch what",
    })
end

local function mindstate_check()
    if heal_past_ml == "true" then return true end
    local xp = DRSkill.getxp("Empathy") or 0
    if xp >= threshold then
        echo("Empathy at target mind state. Exiting.")
        return false
    end
    return true
end

echo("=== Plant Heal ===")
echo("Training Empathy via Vela'Tohr plant healing.")
echo("Touch count: " .. total_touch .. ", ADC: " .. adc)
echo("Threshold: " .. threshold .. ", Heal past ML: " .. heal_past_ml)

DRCI.stow_hands()

-- Main loop
while true do
    if adc == "true" then
        DRC.wait_for_script_to_complete("buff", {"plant_heal"})
    end

    if plant_room then DRCT.walk_to(plant_room) end

    -- Cast EV
    DRC.wait_for_script_to_complete("buff", {"ev"})

    -- Touch plant
    local noun = find_plant()
    if noun then
        local count = 0
        while count < total_touch do
            local r = touch_plant(noun)
            if r:find("Roundtime") then
                count = count + 1
                waitrt()
            elseif r:find("no need of healing") then
                echo("Plant fully healed!")
                break
            elseif r:find("no empathic bond") then
                fput("release ev")
                DRC.wait_for_script_to_complete("buff", {"ev"})
                noun = find_plant()
                if not noun then break end
            elseif r:find("Touch what") then
                DRC.wait_for_script_to_complete("buff", {"ev"})
                noun = find_plant()
                if not noun then break end
            end
        end
    else
        echo("No plant found in room!")
    end

    -- Go heal self
    if healing_room then DRCT.walk_to(healing_room) end
    DRC.wait_for_script_to_complete("healme")

    if not mindstate_check() then break end
end

before_dying(function()
    Flags.delete("heal-expire")
end)
