--- @revenant-script
--- name: enhrecalls
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Watch bard recalls and build JSON data for enhancive items
--- tags: bard, enhancives, recalls, loresong
---
--- Usage: ;enhrecalls (runs in background, watches for recall output)

local items = {}
local parsing = false
local chunk_lines = {}

echo("[enhrecalls] Watching recalls...")

while true do
    local line = get()
    if not line then break end
    line = line:match("^(.-)%s*$") or ""

    if not parsing and line:match("^As you recall") then
        parsing = true
        chunk_lines = {line}
    elseif parsing then
        table.insert(chunk_lines, line)
        if line:match("unlocked loresong") then
            parsing = false
            -- Extract item name
            local name = "Unknown"
            for _, cl in ipairs(chunk_lines) do
                local n = cl:match("from the (.-) in your")
                if n then name = n; break end
            end
            -- Extract enhancive targets
            local targets = {}
            for _, cl in ipairs(chunk_lines) do
                local amt, stat = cl:match("provides .- of%s+([+-]?%d+)%s+to%s+(.-)[%.%(]")
                if amt and stat then
                    table.insert(targets, {target = stat:match("^%s*(.-)%s*$"), amount = tonumber(amt)})
                end
            end
            if #targets > 0 then
                table.insert(items, {name = name, targets = targets})
                echo("[enhrecalls] Captured: " .. name .. " (" .. #targets .. " enhancives)")
            end
            chunk_lines = {}
        end
    end
end
