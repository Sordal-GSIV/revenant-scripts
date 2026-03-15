local M = {}

M.my_disk = nil
M.disk_full = {}

function M.detect()
    -- Check for character's floating disk
    local loot = GameObj.loot()
    for _, item in ipairs(loot) do
        if item.noun == "disk" and item.name:lower():find("disk") then
            M.my_disk = item
            return item
        end
    end
    return nil
end

function M.stow_to_disk(item)
    if not M.my_disk then return false end
    if M.disk_full[M.my_disk.id] then return false end

    fput("put #" .. item.id .. " on #" .. M.my_disk.id)
    -- Check for full message
    -- If full, mark it
    return true
end

function M.mark_full(disk_id)
    M.disk_full[disk_id or (M.my_disk and M.my_disk.id)] = true
end

function M.install_monitor()
    DownstreamHook.add("eloot_disk_monitor", function(line)
        if line:find("disintegrates") and line:find("disk") then
            M.my_disk = nil
        end
        if line:find("arrives, following you") and line:find("disk") then
            M.detect()
        end
        return line
    end)
end

function M.remove_monitor()
    DownstreamHook.remove("eloot_disk_monitor")
end

return M
