--- @revenant-script
--- name: snakeheal
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Auto-heal snake alts when they arrive in room.
--- tags: empath, healing, automated
---
--- Converted from snakeheal.lic

local snakes = {
    "Sarikis", "Sleepyz", "Stickyz", "Solidad", "Schooter", "Saite",
    "Schleepie", "Shugenga", "Snowhitney", "Soaprano", "Surlyz"
}

local heal_time = nil

while true do
    local line = get()
    if line then
        for _, name in ipairs(snakes) do
            if line:find(name .. " just arrived") then
                pause(2)
                local pcs = DRRoom and DRRoom.pcs or {}
                local found = false
                for _, pc in ipairs(pcs) do
                    if pc == name then found = true; break end
                end
                if found then
                    fput("touch " .. name)
                    fput("transfer " .. name .. " quick vit")
                    fput("transfer " .. name .. " quick all")
                    heal_time = os.time()
                end
                break
            end
        end
        if heal_time and os.time() - heal_time > 15 and not running("healme") then
            heal_time = nil
            start_script("healme")
        end
    end
end
