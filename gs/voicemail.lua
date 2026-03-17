--- @revenant-script
--- name: voicemail
--- version: 1.1.2
--- author: Peggyanne
--- game: gs
--- tags: messages, thoughtnet, lnet, afk
--- description: Record and review ThoughtNet/LNet messages received while AFK
---
--- Original Lich5 authors: Peggyanne
--- Ported to Revenant Lua from voicemail.lic v1.1.2
---
--- Usage:
---   ;voicemail help               - show help
---   ;voicemail                    - start recording
---   ;voicemail check              - check saved messages
---   ;voicemail delete <number>    - delete a saved message
---   ;voicemail delete all         - delete all messages

local function show_help()
    respond("Voicemail Version: 1.1.2 (September 1, 2025)")
    respond("")
    respond("   Usage:")
    respond("   ;voicemail help                        Brings up this message")
    respond("   ;voicemail                             Starts recording received messages")
    respond("")
    respond("   After started:")
    respond("   ;voicemail check                       Checks your saved messages")
    respond("   ;voicemail delete <message #>          Deletes a saved message")
    respond("   ;voicemail delete all                  Deletes all saved messages")
    respond("")
    respond("   ~Peggyanne")
end

local settings = UserVars.load("voicemail") or {}
settings.messages = settings.messages or {}

local function save()
    UserVars.save("voicemail", settings)
end

local function check_messages()
    if #settings.messages == 0 then
        respond("")
        respond("You Have No New Messages")
        respond("")
    else
        respond("")
        respond("You Have The Following New Messages:")
        respond("")
        for i, msg in ipairs(settings.messages) do
            put(i .. ". " .. msg)
        end
        respond("")
    end
end

local function delete_message(idx)
    idx = tonumber(idx)
    if not idx or idx < 1 or idx > #settings.messages then
        respond("Invalid message number.")
        return
    end
    respond("Deleting Message Number " .. idx .. "...")
    table.remove(settings.messages, idx)
    save()
    respond("Message Deleted!")
    check_messages()
end

local function delete_all()
    respond("Deleting All Saved Messages...")
    settings.messages = {}
    save()
    respond("All Messages Deleted!")
    check_messages()
end

-- Handle upstream commands
UpstreamHook.add("voicemail_upstream", function(command)
    if command:match(";voicemail check") then
        check_messages()
        return nil
    elseif command:match(";voicemail help") then
        show_help()
        return nil
    elseif command:match(";voicemail delete all") then
        delete_all()
        return nil
    else
        local num = command:match(";voicemail delete (%d+)")
        if num then
            delete_message(num)
            return nil
        end
    end
    return command
end)

before_dying(function()
    UpstreamHook.remove("voicemail_upstream")
end)

local arg1 = Script.current.vars[1]
if arg1 == "help" or arg1 == "?" then
    show_help()
    return
end

while true do
    local line = get()
    if line then
        local person, message = line:match('^%[Focused%] (%S+) %S+, "(.+)"')
        if person then
            local ts = os.date("%c")
            local entry = ts .. ": " .. person .. ' thought, "' .. message .. '"'
            -- Avoid duplicates
            local found = false
            for _, m in ipairs(settings.messages) do
                if m == entry then found = true; break end
            end
            if not found then
                settings.messages[#settings.messages + 1] = entry
                save()
            end
        else
            -- Skip status/combat messages
            if not line:match('^%[Private%].-Health:') and
               not line:match('^%[Private%].-Weekly') and
               not line:match('^%[Private%].-Ready For Combat') then
                person, message = line:match('^%[Private%]%-GSIV:(.-):%s*"(.-)"')
                if person and message then
                    if not message:find("Task Complete") and not message:find("Reporting For Duty") then
                        local ts = os.date("%c")
                        local entry = ts .. ": " .. person .. ' chat, "' .. message .. '"'
                        local found = false
                        for _, m in ipairs(settings.messages) do
                            if m == entry then found = true; break end
                        end
                        if not found then
                            settings.messages[#settings.messages + 1] = entry
                            save()
                        end
                    end
                end
            end
        end
    end
end
