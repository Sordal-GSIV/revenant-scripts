--- @revenant-script
--- name: recall_enhancives
--- version: 1.0.0
--- author: Daedeus
--- game: gs
--- tags: enhancives, recall, inventory, report
--- description: Recall all worn enhancive items and generate a tabular bonus report
---
--- Original Lich5 authors: Daedeus
--- Ported to Revenant Lua from recall-enhancives.lic v1
---
--- Usage:
---   ;recall_enhancives           - run with squelched output
---   ;recall_enhancives verbose   - show all recall output

local verbose = Script.current.vars[1] and Script.current.vars[1]:match("verb")
local HOOK_ID = "recall_squelch"

if not verbose then
    silence_me()
    DownstreamHook.add(HOOK_ID, function(s)
        if Regex.test(s, "<prompt") then return s end
        return nil
    end)
    before_dying(function() DownstreamHook.remove(HOOK_ID) end)
end

echo("Scanning inventory for loresung enhancive items...")

local items_to_recall = {}

fput("inventory enhancive list")
waitfor("You are wearing")

while true do
    local line = get()
    if Regex.test(line, "For more information|<prompt") then break end
    local raw_name, charges = line:match("^%s+(.-)%s+%((%d+/%d+ charges)%)")
    if raw_name then
        local name = raw_name:gsub("^a pair of%s+", ""):gsub("^an%s+", ""):gsub("^a%s+", "")
        items_to_recall[#items_to_recall + 1] = { name = name, charges = charges }
    end
end

local inventory_objects = GameObj.inv()
local processed_items = {}
local totals = {}

for _, item_info in ipairs(items_to_recall) do
    local obj = nil
    for _, o in ipairs(inventory_objects) do
        if o.name == item_info.name then
            local already = false
            for _, p in ipairs(processed_items) do
                if p.id == o.id then already = true; break end
            end
            if not already then obj = o; break end
        end
    end

    if obj then
        local item_data = {
            id = obj.id,
            name = obj.name,
            charges = item_info.charges,
            crumbly = false,
            bonuses = {},
        }

        fput("recall #" .. obj.id)

        while true do
            local line = get()
            if Regex.test(line, "permanently unlocked loresong|You are unable to recall") then break end
            local bonus, stat = line:match("provides a %w+ of (%d+) to (?:the )?(.-).?$")
            if bonus then
                bonus = tonumber(bonus)
                stat = stat:match("^%s*(.-)%s*$")
                item_data.bonuses[#item_data.bonuses + 1] = "+" .. bonus .. " " .. stat
                totals[stat] = (totals[stat] or 0) + bonus
            end
            if line:find("crumble into dust") then
                item_data.crumbly = true
            end
        end

        processed_items[#processed_items + 1] = item_data
        wait(0.1)
    end
end

if not verbose then
    DownstreamHook.remove(HOOK_ID)
end

local output = "\n"
output = output .. string.rep("=", 40) .. "\n"
output = output .. " ENHANCIVE ITEM REPORT\n"
output = output .. string.rep("=", 40) .. "\n"

for _, item in ipairs(processed_items) do
    local crumbly_str = item.crumbly and " (CRUMBLY)" or ""
    output = output .. item.name .. " (" .. item.charges .. ")" .. crumbly_str .. "\n"
    if #item.bonuses == 0 then
        output = output .. "   None detected\n"
    else
        for _, b in ipairs(item.bonuses) do
            output = output .. "   " .. b .. "\n"
        end
    end
    output = output .. string.rep("-", 40) .. "\n"
end

output = output .. "\n"
output = output .. string.rep("=", 40) .. "\n"
output = output .. " TOTAL BONUSES\n"
output = output .. string.rep("=", 40) .. "\n"

local sorted_stats = {}
for stat, _ in pairs(totals) do sorted_stats[#sorted_stats + 1] = stat end
table.sort(sorted_stats)
for _, stat in ipairs(sorted_stats) do
    output = output .. string.format(" %-30s : +%d\n", stat, totals[stat])
end
output = output .. string.rep("=", 40)

echo(output)
