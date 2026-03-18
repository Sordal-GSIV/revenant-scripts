local herbs_db = require("lib/herbs")

local M = {}

local CANT_BUNDLE = "tart|feather|special|blubber|pie|porridge|soup|fruit"

function M.can_bundle(herb_name)
    return not herb_name:lower():find(CANT_BUNDLE)
end

--- Get all unique herb names from the container contents
local function get_container_herbs(container_noun)
    fput("look in my " .. container_noun)
    local contents = {}
    local seen_names = {}

    -- Read game output to collect container items
    for i = 1, 40 do
        local line = get()
        if not line then break end
        -- Parse item links from container output
        -- Match patterns like: <a exist="12345" noun="leaf">some acantha leaf</a>
        for item_id, item_noun, item_name in line:gmatch('exist="(%d+)" noun="(%w+)">([^<]+)</a>') do
            -- Check if this is a known herb
            for _, herb in ipairs(herbs_db.database) do
                if item_name:lower():find(herb.short:lower(), 1, true) then
                    contents[#contents + 1] = {
                        id = item_id,
                        noun = item_noun,
                        name = item_name,
                        herb = herb,
                    }
                    if not seen_names[item_name] then
                        seen_names[item_name] = true
                    end
                    break
                end
            end
        end
        if line:find("Roundtime") or line == "" or line:find("^$") then break end
    end

    return contents, seen_names
end

--- Bundle all duplicate herbs in a container
function M.bundle_all(container_noun, specific_herb)
    container_noun = container_noun or "herbsack"
    respond("[eherbs] Bundling herbs in " .. container_noun .. "...")
    local bundled = 0

    -- Get unique herb names from the database
    local herb_names = {}
    if specific_herb then
        herb_names[#herb_names + 1] = specific_herb
    else
        local seen = {}
        for _, herb in ipairs(herbs_db.database) do
            if not seen[herb.name] then
                seen[herb.name] = true
                -- Skip herbs that can't be bundled
                if M.can_bundle(herb.name) then
                    herb_names[#herb_names + 1] = herb.name
                end
            end
        end
    end

    -- For each herb type, find duplicates in container and bundle them
    local contents, _ = get_container_herbs(container_noun)

    -- Group contents by herb name (stripped of quantity prefixes)
    local groups = {}
    for _, item in ipairs(contents) do
        local key = item.herb.name
        if not groups[key] then groups[key] = {} end
        groups[key][#groups[key] + 1] = item
    end

    local ignore_list = {}

    for herb_name, items in pairs(groups) do
        if #items <= 1 then goto continue_herb end
        if not M.can_bundle(herb_name) then goto continue_herb end

        -- Get the first item to right hand as the bundle base
        local bundle = items[1]
        ignore_list[bundle.id] = true
        fput("get #" .. bundle.id .. " from my " .. container_noun)

        local full = false

        for idx = 2, #items do
            local item = items[idx]
            if ignore_list[item.id] then goto continue_item end

            -- Get second item to other hand
            fput("get #" .. item.id .. " from my " .. container_noun)

            if herbs_db.is_drinkable(item.noun) then
                -- Pour drinkable herbs together
                local pour_done = false
                for attempt = 1, 10 do
                    local pour_result = fput("pour #" .. item.id .. " in #" .. bundle.id)
                    waitrt()
                    -- Check for "You can" (full) or success
                    local rh = GameObj.right_hand()
                    local lh = GameObj.left_hand()
                    if not lh or lh.name == "Empty" then
                        pour_done = true
                        break
                    end
                    -- If the bundle is full, stop
                    if not rh or rh.id ~= bundle.id then
                        full = true
                        break
                    end
                end
            else
                -- Bundle edible herbs
                local bundle_result = fput("bundle")
                waitrt()

                -- Check result - the bundle command combines right and left hand
                local rh = GameObj.right_hand()
                if rh then
                    bundle = { id = rh.id, noun = rh.noun, name = rh.name, herb = bundle.herb }
                end

                -- If left hand still has something, bundling may have failed
                local lh = GameObj.left_hand()
                if lh and lh.name ~= "Empty" then
                    -- Bundling failed (full or incompatible)
                    -- Measure and put back
                    fput("measure #" .. item.id)
                    fput("put #" .. item.id .. " in my " .. container_noun)
                    ignore_list[item.id] = true
                    full = true
                else
                    bundled = bundled + 1
                end
            end

            if full then
                -- Measure the full bundle and put it back
                fput("measure #" .. bundle.id)
                fput("put #" .. bundle.id .. " in my " .. container_noun)
                -- Start a new bundle with the current item if it's still in hand
                local lh = GameObj.left_hand()
                if lh and lh.id == item.id then
                    bundle = item
                    fput("swap")  -- move to right hand
                else
                    bundle = nil
                end
                full = false
            end

            ignore_list[item.id] = true
            ::continue_item::
        end

        -- Put the final bundle back
        if bundle then
            fput("measure #" .. bundle.id)
            fput("put #" .. bundle.id .. " in my " .. container_noun)
        end

        ::continue_herb::
    end

    respond("[eherbs] Bundling complete. " .. bundled .. " herbs consolidated.")
    return bundled
end

--- Bundle two herbs already in hand
function M.bundle_two(item1_noun, item2_noun)
    if herbs_db.is_drinkable(item1_noun) then
        fput("pour my " .. item2_noun .. " in my " .. item1_noun)
    else
        fput("bundle")
    end
    waitrt()
end

return M
