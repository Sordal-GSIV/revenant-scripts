--- @revenant-script
--- name: mana_balance
--- version: 1.0.0
--- author: Lucullan
--- game: gs
--- tags: mana, balance, group, queen, utility
--- description: Coordinate mana balancing across multiple characters via queen script
---
--- Original Lich5 authors: Lucullan
--- Ported to Revenant Lua from mana_balance.lic v1.0.0
---
--- Usage: ;mana_balance (requires queen and mana_report scripts)

local MANA_CAP = 300
local LOSS_RATE = 0.05
local GAIN_RATE = 1.0 - LOSS_RATE
local WAIT_TIMEOUT = 25
local POLL_INTERVAL = 0.25
local QUEEN_DELAY = 0.5
local MIN_PARTICIPANTS = 2
local STABLE_POLLS_NEEDED = 4

-- Check for mana_report script
if not Script.exists("mana_report") then
    echo("mana_balance requires mana_report script.")
    echo("Please download it first.")
    return
end

-- Use shared file for coordination instead of SQLite
local data_file = GameState.data_dir .. "/mana_balance_data.lua"

local function write_report(name, cur_mana, max_mana, capped)
    local reports = {}
    local f = io.open(data_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local fn = load("return " .. content)
        if fn then reports = fn() or {} end
    end
    reports[name] = { cur = cur_mana, max = max_mana, cap = capped, ts = os.time() }
    f = io.open(data_file, "w")
    if f then
        f:write("{\n")
        for k, v in pairs(reports) do
            f:write(string.format('  ["%s"] = { cur=%d, max=%d, cap=%d, ts=%d },\n', k, v.cur, v.max, v.cap, v.ts))
        end
        f:write("}\n")
        f:close()
    end
end

local function load_reports()
    local f = io.open(data_file, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    local fn = load("return " .. content)
    if fn then return fn() or {} end
    return {}
end

local function build_plan(reports, target)
    local donors = {}
    local receivers = {}
    for name, r in pairs(reports) do
        if r.cap > target then
            donors[#donors + 1] = { name = name, surplus = r.cap - target }
        elseif r.cap < target then
            receivers[#receivers + 1] = { name = name, deficit = r.cap - target }
        end
    end
    if #donors == 0 or #receivers == 0 then return {} end
    local plan = {}
    local di = 1
    for _, recv in ipairs(receivers) do
        local need = math.abs(recv.deficit)
        while need > 0 and di <= #donors do
            local d = donors[di]
            if d.surplus <= 0 then di = di + 1 else
                local gain = math.min(d.surplus * GAIN_RATE, need)
                local send = math.ceil(gain / GAIN_RATE)
                if send > d.surplus then send = d.surplus end
                plan[#plan + 1] = { from = d.name, to = recv.name, send = send }
                d.surplus = d.surplus - send
                need = need - (send * GAIN_RATE)
                if d.surplus <= 0 then di = di + 1 end
            end
        end
    end
    return plan
end

-- Clear and initialize
os.remove(data_file)
wait(1)

Script.run("queen", "wall ;mana_report")

local deadline = os.time() + WAIT_TIMEOUT
local stable_polls = 0
local last_keys = nil
local reports = {}

while os.time() < deadline do
    reports = load_reports()
    local keys = {}
    for k, _ in pairs(reports) do keys[#keys + 1] = k end
    table.sort(keys)
    local key_str = table.concat(keys, ",")
    if key_str == last_keys then
        stable_polls = stable_polls + 1
    else
        stable_polls = 0
        last_keys = key_str
    end
    if #keys >= MIN_PARTICIPANTS and stable_polls >= STABLE_POLLS_NEEDED then break end
    wait(POLL_INTERVAL)
end

local participants = {}
for k, _ in pairs(reports) do participants[#participants + 1] = k end
table.sort(participants)

if #participants < MIN_PARTICIPANTS then
    echo("mana_balance: not enough participants (" .. #participants .. ")")
    os.remove(data_file)
    return
end

local sum_caps = 0
for _, name in ipairs(participants) do sum_caps = sum_caps + reports[name].cap end
local target = math.min(math.floor(sum_caps / #participants), MANA_CAP)

echo("---- mana_balance ----")
echo("participants=" .. #participants .. " target=" .. target)
for _, name in ipairs(participants) do
    local r = reports[name]
    echo(name .. ": cur=" .. r.cur .. " max=" .. r.max .. " cap=" .. r.cap)
end

local plan = build_plan(reports, target)
if #plan == 0 then
    echo("No transfers needed.")
    os.remove(data_file)
    return
end

echo("---- transfer plan (loss ~" .. math.floor(LOSS_RATE * 100) .. "%) ----")
for i, p in ipairs(plan) do
    echo(i .. ". " .. p.from .. " -> " .. p.to .. " send=" .. p.send)
end

for _, p in ipairs(plan) do
    Script.run("queen", p.from .. " send " .. p.send .. " " .. p.to)
    wait(QUEEN_DELAY)
end

echo("mana_balance: commands issued.")
os.remove(data_file)
echo("mana_balance: cleanup done.")
