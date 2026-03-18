--------------------------------------------------------------------------------
-- FletchIt - Bundling Module
--
-- Bundle management: inspect quiver contents, count arrows per bundle,
-- group by description, combine partial bundles, handle splitting at 100.
--
-- Original author: elanthia-online (Dissonance)
-- Lua conversion preserves all original functionality.
--------------------------------------------------------------------------------

local M = {}

--- Bundle all arrows/bolts in quiver.
-- Finds all bundles, analyzes counts and descriptions, combines partial
-- bundles of the same type into full 100-count bundles.
-- Handles splitting when combining would exceed 100.
-- @param settings table
-- @param stow_fn function(hand, container, debug_log) stow helper from crafting
-- @param debug_log function
function M.bundle_arrows(settings, stow_fn, debug_log)
    debug_log("bundle_arrows called with quiver: " .. settings.quiver)

    local bundle_ids = {}
    local bundle_amount = {}
    local bundle_desc = {}

    -- Find the quiver container
    local quiver = nil
    local inv = GameObj.inv() or {}
    for _, obj in ipairs(inv) do
        if string.find(obj.name or "", settings.quiver, 1, true) then
            quiver = obj
            break
        end
    end

    if not quiver then
        echo("ERROR: Could not find quiver: " .. settings.quiver)
        error("no_quiver")
    end

    -- Open quiver if needed
    if not quiver.contents then
        waitrt()
        dothistimeout("open #" .. quiver.id, 10, "You open|already open")

        if not quiver.contents then
            waitrt()
            dothistimeout("look in #" .. quiver.id, 10, "In the .* you see")

            if not quiver.contents then
                echo("ERROR: Failed to find the contents of your quiver")
                error("no_quiver_contents")
            end
        end
    end

    -- Collect bundle IDs
    for _, item in ipairs(quiver.contents) do
        if string.find(item.name or "", "bundle", 1, true) then
            table.insert(bundle_ids, item.id)
        end
    end

    if #bundle_ids == 0 then
        echo("No bundles found in quiver.")
        return
    end

    -- Set up downstream hook to collect bundle details
    local hook_name = "fletch_bundle_check_" .. tostring(os.time())

    DownstreamHook.add(hook_name, function(server_string)
        -- Match arrow bundle count
        local arrow_count = string.match(server_string, "You count out (%d+) arrows in your .* bundle and note that")
        if arrow_count then
            table.insert(bundle_amount, arrow_count)
            return nil -- squelch
        end

        -- Match bolt bundle count
        local bolt_count = string.match(server_string, "You count out (%d+) bolts in your .* bundle and note that")
        if bolt_count then
            table.insert(bundle_amount, bolt_count)
            return nil
        end

        -- Match bundle description
        local desc = string.match(server_string, "Each individual projectile appears to be (.+) of fine quality%.$")
        if desc then
            table.insert(bundle_desc, desc)
            return nil
        end

        -- Squelch the "will be" line
        if string.find(server_string, 'Each individual projectile will be "') then
            return nil
        end

        -- Squelch prompt lines
        if string.find(server_string, '<prompt time="%d+">&gt;</prompt>') then
            return nil
        end

        -- Let longer lines through, squelch very short ones
        if #server_string > 2 then
            return server_string
        end
        return nil
    end)

    -- Look at each bundle to get its info
    for _, id in ipairs(bundle_ids) do
        fput("look #" .. id)
    end

    -- Wait for all bundle info to arrive
    local endtime = os.time() + 6
    wait_until(function()
        return #bundle_ids == #bundle_desc or os.time() > endtime
    end)

    DownstreamHook.remove(hook_name)

    if #bundle_ids ~= #bundle_desc then
        echo("ERROR: Failed to get bundle info, stopping")
        error("bundle_info_failed")
    end

    -- Build bundle data structure
    local bundles = {}
    for idx, id in ipairs(bundle_ids) do
        table.insert(bundles, {
            id    = id,
            count = tonumber(bundle_amount[idx]) or 0,
            desc  = bundle_desc[idx],
        })
    end

    -- Get unique descriptions
    local seen_desc = {}
    local uniq_descs = {}
    for _, b in ipairs(bundles) do
        if not seen_desc[b.desc] then
            seen_desc[b.desc] = true
            table.insert(uniq_descs, b.desc)
        end
    end

    -- Combine bundles by description
    for _, desc in ipairs(uniq_descs) do
        local total = 0
        local last_bundle_id = nil

        for _, bundle in ipairs(bundles) do
            if bundle.desc == desc and bundle.count ~= 100 then
                if total == 0 then
                    -- First bundle of this type
                    total = bundle.count
                    last_bundle_id = bundle.id
                elseif total > 0 then
                    -- Found another bundle of same type
                    total = total + bundle.count

                    if total <= 100 then
                        -- Can combine completely
                        waitrt()
                        fput("get #" .. bundle.id)
                        matchtimeout(1, "You remove")
                        local lh = GameObj.left_hand()
                        if not lh then
                            fput("get #" .. last_bundle_id)
                        end
                        fput("bundle")

                        if total == 100 then
                            stow_fn("right", settings.quiver, debug_log)
                            total = 0
                        else
                            last_bundle_id = bundle.id
                        end
                    else
                        -- Need to split
                        local amount_over = total - 100
                        local amount_to_get = bundle.count - amount_over

                        waitrt()
                        fput("get " .. amount_to_get .. " #" .. bundle.id)
                        matchtimeout(1, "You remove")
                        local lh = GameObj.left_hand()
                        if not lh then
                            fput("get #" .. last_bundle_id)
                        end
                        fput("bundle")
                        stow_fn("right", settings.quiver, debug_log)

                        -- Update bundle count and re-add to process later
                        bundle.count = bundle.count - amount_to_get
                        table.insert(bundles, bundle)
                        total = 0
                    end
                end
            end
        end

        -- Stow any remaining partial bundle
        waitrt()
        local rh = GameObj.right_hand()
        if rh then
            stow_fn("right", settings.quiver, debug_log)
        end
    end

    echo("Bundling complete.")
end

return M
