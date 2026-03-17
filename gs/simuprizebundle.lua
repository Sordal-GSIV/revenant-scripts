--- @revenant-script
--- name: simuprizebundle
--- version: 1.0.0
--- author: elanthia-online
--- contributors: Dissonance, Tysong, Jervil
--- game: gs
--- description: Bundle all Rumor Woods prizes that can be bundled
--- tags: utility,rumor woods

local BUNDLEABLE = {
    "Adventurer's Guild voucher pack",
    "blue feather%-shaped charm",
    "Elanthian Guilds voucher pack",
    "small glowing orb",
    "squat jar of pallid grey salve",
    "tall jar of pallid grey salve",
    "potent blue%-green potion",
    "swirling yellow%-green potion",
    "twisting blue%-green potion",
    "light yellow note",  "stack of light yellow notes",
    "bright orange note", "stack of bright orange notes",
    "deep black note",    "stack of deep black notes",
    "pale pink note",     "stack of pale pink notes",
    "light pink note",    "stack of light pink notes",
    "bright pink note",   "stack of bright pink notes",
    "vivid pink note",    "stack of vivid pink notes",
    "pale blue note",     "stack of pale blue notes",
    "light blue note",    "stack of light blue notes",
    "bright blue note",   "stack of bright blue notes",
    "vivid blue note",    "stack of vivid blue notes",
}

local function name_matches_any(name, patterns)
    for _, pat in ipairs(patterns) do
        if name:match("^" .. pat .. "$") then return true end
    end
    return false
end

local function populate_containers()
    for _, item in ipairs(GameObj.inv()) do
        if item.type and not item.type:match("jewelry") and not item.type:match("weapon")
           and not item.type:match("armor") and not item.type:match("uncommon") then
            local result = dothistimeout("open #" .. item.id, 3,
                "exposeContainer|That is already open|There doesn't seem to be any way")
            if not result or result:find("There doesn't seem") then
                -- skip
            else
                dothistimeout("look in #" .. item.id, 3, "exposeContainer|You see|There is nothing")
                for _ = 1, 20 do
                    if GameObj.containers(item.id) then break end
                    sleep(0.1)
                end
            end
        end
    end
end

local function main()
    empty_hands()
    populate_containers()

    for _, pattern in ipairs(BUNDLEABLE) do
        local all_found = {}
        local first_container = nil

        for _, inv_item in ipairs(GameObj.inv()) do
            local contents = GameObj.containers(inv_item.id)
            if contents then
                for _, item in ipairs(contents) do
                    if item.name and item.name:match(pattern) then
                        all_found[#all_found + 1] = item
                        if not first_container then
                            first_container = inv_item.id
                        end
                    end
                end
            end
        end

        if #all_found > 1 then
            for _, item in ipairs(all_found) do
                -- Make sure a hand is free
                if checkleft() and checkright() and first_container then
                    local rh = GameObj.right_hand()
                    if rh then fput("_drag #" .. rh.id .. " #" .. first_container) end
                end
                fput("get #" .. item.id)
                for _ = 1, 20 do
                    local lh = GameObj.left_hand()
                    local rh = GameObj.right_hand()
                    if (lh and lh.id == item.id) or (rh and rh.id == item.id) then break end
                    sleep(0.1)
                end
                if checkleft() and checkright() then
                    if item.name:match("potion") then
                        fput("pour my first potion in my second potion")
                    else
                        fput("bundle")
                    end
                end
            end
            -- Stow remaining items
            if first_container then
                local lh = GameObj.left_hand()
                local rh = GameObj.right_hand()
                if lh then fput("_drag #" .. lh.id .. " #" .. first_container) end
                if rh then fput("_drag #" .. rh.id .. " #" .. first_container) end
            end
        end
    end

    fill_hands()
end

main()
