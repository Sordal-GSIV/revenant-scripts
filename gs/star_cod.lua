--- @revenant-script
--- name: star_cod
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Mail items COD or free via Four Winds Isle postal service
--- tags: mail, cod, package, four winds
---
--- Usage:
---   ;star_cod <buyer_name> <sale_amount>
---   ;star_cod Tatterclaws 20000    - send COD
---   ;star_cod Tatterclaws 0        - send free (non-COD)
---
--- NOTE: Currently designed for use on Four Winds Isle only.

local buyer      = Script.vars[1]
local amount_str = Script.vars[2]

if not buyer or not amount_str then
    respond("Usage: ;star_cod <buyer_name> <sale_amount>")
    respond("Example: ;star_cod Tatterclaws 20000")
    respond("         ;star_cod Tatterclaws 0")
    respond("Note: This script currently only works on Four Winds Isle.")
    return
end

local base_amount = tonumber(amount_str:gsub("[^%d]", "")) or 0

-- Location check: must be on Four Winds Isle
local loc_lines = {}
local loc_done = false
local hook_id = "star_cod_loc_check"

DownstreamHook.add(hook_id, function(s)
    if not loc_done then
        local clean = s:gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
        if clean and #clean > 0 then
            table.insert(loc_lines, clean)
            if clean:lower():find("current location is") then
                loc_done = true
            end
        end
    end
    return nil
end)

fput("location")
local deadline = os.time() + 5
while not loc_done and os.time() < deadline do
    pause(0.1)
end
DownstreamHook.remove(hook_id)

local on_isle = false
for _, l in ipairs(loc_lines) do
    if l:find("Isle of Four Winds") then
        on_isle = true
        break
    end
end

if not on_isle then
    respond("[star_cod] Error: You must be on Four Winds Isle to use this script.")
    respond("[star_cod] Aborted.")
    return
end

respond("[star_cod] Starting mail process...")

-- 1) Go to bank and withdraw 8000 silver
start_script("go2", {"bank"})
wait_while(function() return running("go2") end)
fput("withdraw 8000 silver")

-- 2) Go to mail and buy package
start_script("go2", {"mail"})
wait_while(function() return running("go2") end)
fput("order 4")
fput("buy")

-- 3) Check right-hand item
local right_item = GameObj.right_hand()
if not right_item then
    respond("[star_cod] Error: no item in right hand.")
    return
end

local item_name = right_item.name
local item_noun = right_item.noun

-- 4) Package item
fput("put " .. item_noun .. " in my package")
fput("close my package")

if base_amount <= 0 then
    -- NON-COD path
    fput("mail send " .. buyer .. " first")
    fput("mail send " .. buyer .. " first")
    respond("[star_cod] You sent '" .. item_name .. "' to " .. buyer .. " via first class (NON-COD).")
    respond("[star_cod] Mailing complete.")
    return
end

-- 5) COD path
local cod_fee = math.ceil(base_amount * 0.03)
local total   = base_amount + cod_fee + 7000
fput("mail send " .. buyer .. " cod " .. total .. " first")
fput("mail send " .. buyer .. " cod " .. total .. " first")

-- 6) Summary
respond("[star_cod] You sent '" .. item_name .. "' to " .. buyer .. " via first class for " .. base_amount .. " silvers.")
respond("[star_cod] COD fee (3%): " .. cod_fee .. ", mailing cost: 7000; Total: " .. total .. " silvers.")
respond("[star_cod] Mailing complete.")
