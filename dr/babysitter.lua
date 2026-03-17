--- @revenant-script
--- name: babysitter
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Watch and care for a pet raccoon (feed on whimper, pet on pace)
--- tags: pet, raccoon, companion

while true do
    local line = get()
    if line then
        if line:lower():find("whimper") then
            fput("feed corn to raccoon")
        elseif line:lower():find("pace") then
            fput("pet raccoon")
        end
    end
end
