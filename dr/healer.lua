--- @revenant-script
--- name: healer
--- version: 1.0
--- author: unknown
--- game: dr
--- description: Background empath - heals on whisper request.
--- tags: empath, healing, automated
--- Converted from healer.lic
no_pause_all()
local queue = {}
echo("Healer ready. Whisper 'heal' to request healing.")
while true do
    local line = get()
    if line then
        local name = line:match("^(%w+) whispers, \"heal")
        if name then
            echo("Healing " .. name)
            waitrt(); fput("touch " .. name)
            fput("transfer " .. name .. " vit quick")
            fput("transfer " .. name .. " quick all")
            start_script("healme")
        end
    end
end
