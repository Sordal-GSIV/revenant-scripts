--- @revenant-script
--- name: star_wealth
--- version: 1.0.0
--- author: Starsworn
--- game: gs
--- tags: wealth, currency, summary, utility
--- description: Display formatted wealth summary including currencies, bank, bounty, and service items
---
--- Original Lich5 authors: Starsworn
--- Ported to Revenant Lua from star-wealth.lic
---
--- Usage:
---   ;star_wealth <tattoo> <standard> <jewelry>  - first-time setup
---   ;star_wealth reset                           - clear nouns
---   ;star_wealth                                 - display wealth table

if Script.current.vars[1] == "reset" then
    CharSettings.set("sw_tattoo", nil)
    CharSettings.set("sw_standard", nil)
    CharSettings.set("sw_jewelry", nil)
    respond("star_wealth: Nouns cleared.")
    return
end

if Script.current.vars[1] and Script.current.vars[2] and Script.current.vars[3] then
    CharSettings.set("sw_tattoo", Script.current.vars[1])
    CharSettings.set("sw_standard", Script.current.vars[2])
    CharSettings.set("sw_jewelry", Script.current.vars[3])
    respond("star_wealth: Saved! Run ;star_wealth again to display.")
    return
end

local tattoo_noun = CharSettings.get("sw_tattoo")
local standard_noun = CharSettings.get("sw_standard")
local jewelry_noun = CharSettings.get("sw_jewelry")

if not tattoo_noun or not standard_noun or not jewelry_noun then
    respond("star_wealth: First-time setup!")
    respond("  ;star_wealth <tattoo_noun> <standard_noun> <jewelry_noun>")
    respond("  Example: ;star_wealth tattoo pennant spikes")
    return
end

local function commify(val)
    local s = tostring(val or 0)
    local pos = #s % 3
    if pos == 0 then pos = 3 end
    local result = s:sub(1, pos)
    for i = pos + 1, #s, 3 do
        result = result .. "," .. s:sub(i, i + 2)
    end
    return result
end

local function wcapture(command, end_pat, timeout)
    timeout = timeout or 7
    fput(command)
    local lines = {}
    local deadline = os.time() + timeout
    while os.time() < deadline do
        local line = get()
        if line then
            lines[#lines + 1] = line:gsub("<[^>]*>", ""):match("^%s*(.-)%s*$")
            if Regex.test(line, end_pat) then break end
        end
    end
    return lines
end

-- Gather data
wcapture("wealth all", "Dust in your reserves")

local silver = commify(Currency.silver or 0)
local bloodscrip = commify(Currency.bloodscrip or 0)

local bank_lines = wcapture("bank account", "Total:")
local bank_total = "n/a"
for _, l in ipairs(bank_lines) do
    local bt = l:match("Total:%s*([%d,]+)")
    if bt then bank_total = bt end
end

local bounty_lines = wcapture("bounty", "unspent bounty points")
local bounty_pts = "n/a"
for _, l in ipairs(bounty_lines) do
    local bp = l:match("(%d[%d,]*) unspent bounty points")
    if bp then bounty_pts = bp end
end

-- Service items
local service_items = {
    { cmd = "analyze " .. tattoo_noun, label = "Mystic Tattoo" },
    { cmd = "analyze " .. standard_noun, label = "Battle Standard" },
    { cmd = "analyze " .. jewelry_noun, label = "Bloodstone Jewelry" },
    { cmd = "resource", label = "Covert Arts" },
}

local service_results = {}
for _, item in ipairs(service_items) do
    local lines = wcapture(item.cmd, "charges? remaining|Charges:%s*%d|Covert Arts Charges|may not be lightened")
    local charges = "n/a"
    for _, l in ipairs(lines) do
        local c, m = l:match("(%d[%d,]*)%s+of%s+(%d[%d,]*)%s+charges?")
        if c then charges = c .. "/" .. m end
        if not c then
            c = l:match("Charges:%s*(%d+)")
            if c then charges = c end
        end
        if not c then
            c = l:match("Covert Arts Charges:%s*([%d/]+)")
            if c then charges = c end
        end
    end
    service_results[#service_results + 1] = { label = item.label, charges = charges }
end

-- Display
respond("")
respond("====== WEALTH SUMMARY ======")
respond(string.format("  %-28s %s", "Silver on Hand:", silver))
respond(string.format("  %-28s %s", "Bank Total:", bank_total))
respond(string.format("  %-28s %s", "Bloodscrip:", bloodscrip))
respond(string.format("  %-28s %s", "Unspent Bounty Points:", bounty_pts))
respond("")
respond("====== SERVICE ITEMS ======")
for _, r in ipairs(service_results) do
    respond(string.format("  %-22s %s", r.label, r.charges))
end
respond("")
