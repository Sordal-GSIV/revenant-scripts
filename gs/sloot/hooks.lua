--- sloot/hooks.lua
-- Downstream hooks for disk tracking and search/loot GameObj watcher.
-- Mirrors install_hooks proc and DownstreamHook usage from sloot.lic v3.5.2.

local M = {}

-- Shared disk state (accessed by items.lua / sell.lua)
M.has_disk  = false
M.disk_full = false
M.searched  = false
local hooks_installed = {}

--- Install or remove hooks based on settings.
function M.install_hooks(settings)
    -- ── Disk tracking hook ─────────────────────────────────────────────────
    if settings.enable_disking then
        if not hooks_installed.disk then
            hooks_installed.disk = true
            local char_name = Char.name
            DownstreamHook.add("SLootDisk", function(server_string)
                local s = server_string or ""
                if s:find("from in the") and s:find(char_name .. " disk") then
                    M.has_disk  = true
                    M.disk_full = false
                elseif s:find(char_name .. " disk in a dismissing gesture") then
                    M.has_disk  = false
                    M.disk_full = false
                elseif s:find("Your.*disk.*arrives") or s:find("A small circular container suddenly appears") then
                    M.has_disk  = true
                    M.disk_full = false
                elseif s:find("won't fit in the") and s:find("disk") then
                    M.has_disk  = true
                    M.disk_full = true
                end
                return server_string
            end)
        end
    elseif hooks_installed.disk then
        DownstreamHook.remove("SLootDisk")
        hooks_installed.disk = nil
    end

    -- ── Search/loot GameObj watcher hook ───────────────────────────────────
    -- Watches for search results so newly-found loot is tracked.
    if not hooks_installed.watcher then
        hooks_installed.watcher = true
        DownstreamHook.add("SLootGameObjWatcher", function(server_string)
            local s = server_string or ""
            if s:find("You .-search") then
                M.searched = true
            elseif M.searched and (s:find("had nothing else of value")
                                or s:find("had nothing of interest")
                                or s:find("body shimmers slightly")
                                or s:find("prompt")) then
                M.searched = false
            elseif M.searched and not s:find("prompt") then
                -- Parse any <a exist="..." noun="...">...</a> links and register as loot
                for exist, noun, name in s:gmatch('<a exist="(%d+)" noun="([^"]+)">([^<]+)</a>') do
                    -- Skip pronouns and possessives
                    if not name:match("^(?:he|she|it|her|his|him|its|itself)$")
                       and not name:match("'s$") then
                        -- Only add if not already in loot or inv
                        local already = false
                        for _, obj in ipairs(GameObj.loot()) do
                            if obj.id == exist then already = true; break end
                        end
                        if not already then
                            for _, obj in ipairs(GameObj.inv()) do
                                if obj.id == exist then already = true; break end
                            end
                        end
                        if not already then
                            GameObj.new_loot(exist, noun, name)
                        end
                    end
                end
            end
            return server_string
        end)
    end
end

--- Remove all installed hooks (call on script exit).
function M.remove_hooks()
    DownstreamHook.remove("SLootDisk")
    DownstreamHook.remove("SLootGameObjWatcher")
    hooks_installed = {}
end

return M
