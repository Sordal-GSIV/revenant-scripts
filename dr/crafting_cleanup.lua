--- @revenant-script
--- name: crafting_cleanup
--- version: 0.4
--- author: NBSL
--- game: dr
--- description: Discard trash crafting components and sort tools back to correct containers/belts
--- tags: crafting, cleanup, trash, sorting
---
--- Ported from crafting-cleanup.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;crafting_cleanup            - Passive mode (watch for remedy script)
---   ;crafting_cleanup trash      - Trash items from containers
---   ;crafting_cleanup sort       - Sort crafting items back to correct locations
---   ;crafting_cleanup trash sort - Do both
---   ;crafting_cleanup help       - Show help
---   ;crafting_cleanup yaml       - Show YAML settings info
---
--- YAML Settings:
---   trash_room, trash_containers, trash_items, trash_clear,
---   crafting_container, crafting_items_in_container,
---   forging_belt, alchemy_belt, engineering_belt, outfitting_belt

local args = Script.vars or {}
local arg1 = args[1] and args[1]:lower() or nil

local settings = get_settings()
local trash_room = settings.trash_room
local trash_containers = settings.trash_containers or {}
local trash_clear = settings.trash_clear or false
local trash_items = settings.trash_items or {}
local bag = settings.crafting_container
local bag_items = settings.crafting_items_in_container or {}

local belts = {}
if settings.forging_belt then table.insert(belts, settings.forging_belt) end
if settings.alchemy_belt then table.insert(belts, settings.alchemy_belt) end
if settings.engineering_belt then table.insert(belts, settings.engineering_belt) end
if settings.outfitting_belt then table.insert(belts, settings.outfitting_belt) end

local function show_help()
    echo("=== Crafting Cleanup v0.4 ===")
    echo("Author: NBSL")
    echo("")
    echo("Usage:")
    echo("  ;crafting_cleanup            - Passive mode")
    echo("  ;crafting_cleanup trash      - Trash items")
    echo("  ;crafting_cleanup sort       - Sort items back")
    echo("  ;crafting_cleanup trash sort - Both")
    echo("  ;crafting_cleanup help       - This help")
    echo("  ;crafting_cleanup yaml       - Show settings info")
end

local function show_yaml()
    echo("YAML Settings:")
    echo("  trash_room: <room_id>")
    echo("  trash_containers:")
    echo("    - haversack")
    echo("  trash_items:")
    echo("    - blister cream")
    echo("    - dried nemoih")
    echo("  trash_clear: false")
    echo("  crafting_container: <container>")
    echo("  crafting_items_in_container:")
    echo("    - <item>")
end

local function find_trash()
    DRCI.stow_hands()
    if trash_room then
        DRCT.walk_to(trash_room)
    end
    for _, container in ipairs(trash_containers) do
        for _, item in ipairs(trash_items) do
            while true do
                local result = DRC.bput("get my " .. item .. " from my " .. container,
                    {"You get", "What were you referring to"})
                if result:find("You get") then
                    DRCI.dispose_trash(item)
                else
                    break
                end
            end
        end
    end
    if trash_clear then fput("dump junk") end
end

local function sort_items()
    DRCI.stow_hands()
    for _, belt in ipairs(belts) do
        if belt.name and belt.items then
            local look_result = DRC.bput("look on my " .. belt.name,
                {"On the .* you see", "could not find"})
            if look_result:find("On the") then
                for _, item in ipairs(belt.items) do
                    if not look_result:find(item) then
                        local tap = DRC.bput("tap my " .. item,
                            {"atop your", "inside your", "could not find"})
                        if not tap:find("atop your") and not tap:find("could not find") then
                            fput("get my " .. item)
                            DRCC.stow_crafting_item(item, bag, belt)
                        end
                    end
                end
            end
        end
    end

    if bag then
        local in_bag = DRC.bput("look in my " .. bag,
            {"In the .* you see", "could not find"})
        if in_bag:find("In the") then
            for _, item in ipairs(bag_items) do
                if not in_bag:find(item) then
                    local tap = DRC.bput("tap my " .. item,
                        {"inside your", "atop your", "could not find"})
                    if not tap:find("inside your " .. bag) and not tap:find("could not find") then
                        fput("get my " .. item)
                        fput("put my " .. item .. " in my " .. bag)
                    end
                end
            end
        end
    end
end

local function passive_mode()
    echo("Starting in passive mode... watching for remedy script.")
    local running_flag = false
    while true do
        local line = get()
        if line then
            if (line:find("Lich: .*remedy active") or line:find("%[remedy")) and not running_flag then
                echo("Remedy detected. Waiting for workorders to finish...")
                running_flag = true
            end
        end
        if running_flag then
            if not Script.running("workorders") then
                if Script.running("crossing-training") then
                    pause_script("crossing-training")
                end
                find_trash()
                sort_items()
                running_flag = false
                if Script.running("crossing-training") then
                    unpause_script("crossing-training")
                end
            end
        end
        pause(0.5)
    end
end

before_dying(function()
    echo("Exiting crafting cleanup.")
    if Script.running("crossing-training") then
        unpause_script("crossing-training")
    end
end)

-- Main dispatch
if arg1 == "help" then
    show_help()
elseif arg1 == "yaml" then
    show_yaml()
else
    local do_trash = false
    local do_sort = false
    for _, a in ipairs(args) do
        if a and a:lower() == "trash" then do_trash = true end
        if a and a:lower() == "sort" then do_sort = true end
    end
    if do_trash then find_trash() end
    if do_sort then sort_items() end
    if not do_trash and not do_sort then
        passive_mode()
    end
end
