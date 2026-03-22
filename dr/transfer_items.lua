--- @revenant-script
--- name: transfer_items
--- version: 2.0
--- game: dr
--- description: Transfer items between containers, with optional noun filter and trash mode.
--- tags: items, container, transfer
--- original-authors: dr-scripts contributors (https://elanthipedia.play.net/Lich_script_repository#transfer-items)
--- @lic-certified: complete 2026-03-19
---
--- Usage: ;transfer_items <source> <destination> [noun]
---
--- Arguments:
---   source      - Source container name (e.g. "backpack", "leather sack")
---   destination - Destination container name, or "trash" to discard items
---   noun        - Optional: only transfer items whose noun matches this word
---
--- Examples:
---   ;transfer_items backpack sack
---   ;transfer_items sack backpack dagger
---   ;transfer_items backpack trash arrow

local source      = Script.vars[1]
local destination = Script.vars[2]
local noun        = Script.vars[3]  -- optional noun filter

if not source or not destination then
    DRC.message("Usage: ;transfer_items <source> <destination> [noun]")
    return
end

-- Release any active invisibility spells that could block item manipulation.
DRC.release_invisibility()

--- Put an item into the destination, returning it to source on failure.
local function move_item(item)
    if not DRCI.put_away_item(item, destination) then
        DRC.message("Unable to put " .. item .. " in your " .. destination ..
                    ". The container may be full or too small.")
        DRCI.put_away_item(item, source)
    end
end

--- Transfer all matching items from source to destination.
-- Handles overfull containers ("lot of other stuff") by recursing.
local function transfer_items()
    -- If a noun filter is set, sort matching items to the visible top of the
    -- container before looking, so we can process them even in full containers.
    if noun then
        DRC.bput("sort " .. noun .. " in my " .. source,
            "are now at the top",
            "What were you referring to",
            "Please rephrase that command",
            "You may only sort items in your inventory")
    end

    local items = DRCI.get_item_list(source, "look")

    for _, full_name in ipairs(items) do
        -- Detect overflow sentinel: container has more items than LOOK can show.
        -- Recurse to process the next visible batch, then stop this pass.
        if full_name:find("lot of other stuff") then
            transfer_items()
            break
        end

        -- Extract noun (last word) from full item description.
        local item_noun = DRC.get_noun(full_name)
        if not item_noun then goto continue end

        -- Apply optional noun filter (exact noun match).
        if noun and item_noun ~= noun then goto continue end

        -- Attempt to pick up the item.
        if not DRCI.get_item(item_noun, source) then
            DRC.message("Unable to get " .. item_noun .. " from " .. source .. ".")
            if DRC.left_hand() and DRC.right_hand() then
                DRC.message("Your hands are full!")
            end
            return
        end

        -- Coins auto-go to the coin purse on GET; skip trying to store them.
        if item_noun:match("^coins?$") then goto continue end

        -- Dispose or move the item.
        if destination == "trash" then
            DRCI.dispose_trash(item_noun)
        else
            move_item(item_noun)
        end

        ::continue::
    end
end

transfer_items()
