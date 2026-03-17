--- @revenant-script
--- name: countpaidentries
--- version: 1.0.0
--- author: Phocosoen, ChatGPT
--- game: gs
--- description: Count vouchers in booklets and entries in markers for Bloodscrip/Raikhen estimation
--- tags: duskruin, booklet, marker, voucher, raikhen, bloodscrip, count, rumor woods

local total_vouchers = 0
local total_marker_entries = 0

echo("Scanning inventory and containers for booklets and markers...")

-- Collect booklets and markers from inventory
local booklets = {}
local markers = {}
local inv = GameObj.inv() or {}
for _, obj in ipairs(inv) do
    if obj.noun == "booklet" then
        table.insert(booklets, obj)
    end
    if obj.name and obj.name:lower():find("%bmarker%b") then
        table.insert(markers, obj)
    end
end

-- Collect from containers
local containers = GameObj.containers() or {}
for _, container_data in pairs(containers) do
    local items = container_data
    if type(items) == "table" then
        for _, item in ipairs(items) do
            if item.noun == "booklet" then
                table.insert(booklets, item)
            end
            if item.name and item.name:lower():find("marker") then
                table.insert(markers, item)
            end
        end
    end
end

if #booklets == 0 and #markers == 0 then
    echo("No booklets or markers found.")
    return
end

-- Process booklets
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
                    echo("[countpaidentries: Warning: Could not read voucher count for Booklet ID: " .. booklet.id .. ". Retrying... (Attempt " .. retries .. ")]")
                end
                pause(0.25)
            end
        else
            retries = retries + 1
        end
    end
end

-- Process markers
for _, marker in ipairs(markers) do
    local retries = 0
    local entries = nil

    while retries < 3 and entries == nil do
        pause(0.1)
        fput("look #" .. marker.id)
        local line = get()

        if line then
            local count = line:match("(%d+)%s+entries%s+left")
            if count then
                entries = tonumber(count)
                total_marker_entries = total_marker_entries + entries
            else
                retries = retries + 1
                if retries < 3 then
                    echo("[countpaidentries: Warning: Could not read entries for Marker ID: " .. marker.id .. ". Retrying... (Attempt " .. retries .. ")]")
                end
                pause(0.25)
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
local estimated_raikhen = total_marker_entries * 300

echo("-----------------------------------")
echo("Total vouchers remaining: " .. total_vouchers)
echo("Approximate Bloodscrip earnings: " .. format_number(estimated_bloodscrip) .. " BS")
echo("Total marker entries remaining: " .. total_marker_entries)
echo("Approximate Raikhen earnings: " .. format_number(estimated_raikhen) .. " Raikhen")
echo("-----------------------------------")
