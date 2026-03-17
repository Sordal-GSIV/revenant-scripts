--- @revenant-script
--- name: countbooklets
--- version: 1.0.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Count vouchers in booklets across inventory and containers for bloodscrip estimation
--- tags: duskruin, booklet, voucher, count

local total_vouchers = 0

echo("Scanning inventory and containers for booklets...")

-- Collect booklets from inventory
local booklets = {}
local inv = GameObj.inv() or {}
for _, obj in ipairs(inv) do
    if obj.noun == "booklet" then
        table.insert(booklets, obj)
    end
end

-- Collect booklets from containers
local containers = GameObj.containers() or {}
for _, container_data in pairs(containers) do
    local items = container_data
    if type(items) == "table" then
        for _, item in ipairs(items) do
            if item.noun == "booklet" then
                table.insert(booklets, item)
            end
        end
    end
end

if #booklets == 0 then
    echo("No booklets found.")
    return
end

-- Process each booklet
for _, booklet in ipairs(booklets) do
    local retries = 0
    local vouchers = nil

    while retries < 3 and vouchers == nil do
        pause(0.1)
        fput("look #" .. booklet.id)
        local line = get()

        if line then
            local count = line:match("(%d+)%s+of%s+%d+%s+stamped vouchers remaining")
            if count then
                vouchers = tonumber(count)
                total_vouchers = total_vouchers + vouchers
            else
                retries = retries + 1
                if retries < 3 then
                    echo("[countbooklets: Warning: Could not read voucher count for Booklet ID: " .. booklet.id .. ". Retrying... (Attempt " .. retries .. ")]")
                    pause(0.25)
                else
                    echo("[countbooklets: Warning: Skipping Booklet ID: " .. booklet.id .. " after 3 failed attempts.]")
                end
            end
        else
            retries = retries + 1
        end
    end
end

-- Format number with commas
local function format_number(n)
    local s = tostring(n)
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        result = s:sub(i, i) .. result
        count = count + 1
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

local estimated_bloodscrip = total_vouchers * 300

echo("-----------------------------------")
echo("Total vouchers remaining: " .. total_vouchers)
echo("Approximate Bloodscrip earnings: " .. format_number(estimated_bloodscrip) .. " BS")
echo("-----------------------------------")
