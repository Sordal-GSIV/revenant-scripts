-- Group composition parser
-- Parses GROUP verb output to populate Group.members and Group.leader

DownstreamHook.add("__group_parser", function(text)
    -- Pattern: "Your group: You (leader), Frodo, Samwise"
    -- Pattern: "Gandalf's group: Gandalf (leader), Frodo, Samwise"
    local group_line = text:match("group:%s+(.+)")
    if not group_line then return text end

    local members = {}
    local leader = nil

    for entry in group_line:gmatch("([^,]+)") do
        entry = entry:match("^%s*(.-)%s*$") -- trim
        local name, is_leader = entry:match("^(.-)%s*%(leader%)$")
        if is_leader then
            name = name:match("^%s*(.-)%s*$")
            if name == "You" then
                leader = GameState.name
            else
                leader = name
            end
            members[#members + 1] = name == "You" and GameState.name or name
        else
            if entry ~= "" then
                members[#members + 1] = entry
            end
        end
    end

    if #members > 0 then
        Group.members = members
        Group.leader = leader
    end

    return text
end)
