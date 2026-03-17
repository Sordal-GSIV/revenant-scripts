--- @revenant-script
--- name: maxlock3
--- version: 0.6.0
--- author: LostRanger
--- game: gs
--- description: Shows max lock/trap difficulty chart, stats, and lockpick suggestions
--- tags: utility, rogue, locks, traps
---
--- Usage:
---   ;maxlock3         - Show lock/trap difficulty chart
---   ;maxlock3 stats   - Show relevant stats and bonuses
---   ;maxlock3 <num>   - Suggest lockpicks for a lock of given difficulty

local LOCKPICKS = {
    {"copper", 1.00}, {"brass", 1.05}, {"steel", 1.10}, {"gold/ivory", 1.20},
    {"silver", 1.30}, {"mithril", 1.45}, {"professional", 1.50}, {"ora", 1.55},
    {"glaes", 1.60}, {"laje", 1.75}, {"vultite", 1.80}, {"rolaren", 1.90},
    {"veniom", 2.20}, {"invar", 2.25}, {"alum", 2.30}, {"golvern", 2.35},
    {"kelyn", 2.40}, {"vaalin", 2.50}, {"best crafted vaalin", 2.55},
}

local lmas_ranks = nil

local function lock_skill()
    return Skills.to_bonus(Skills.pickinglocks)
end

local function trap_skill()
    return Skills.to_bonus(Skills.disarmingtraps)
end

local function dex_bonus()
    if Stats.enhanced_dex and Stats.enhanced_dex[1] and Stats.enhanced_dex[1] > 0 then
        return Stats.enhanced_dex[2]
    end
    return Stats.dex[2]
end

local function update_lmas_ranks()
    local result = quiet_command("gld", "You are a")
    lmas_ranks = 0
    for _, line in ipairs(result or {}) do
        if line:match("You are a Master of Lock Mastery") then
            lmas_ranks = 63
            return
        end
        local ranks = line:match("You have (%d+) ranks in the Lock Mastery skill")
        if ranks then
            lmas_ranks = tonumber(ranks)
            return
        end
    end
end

local function lore_bonus(spell, skill, selfcast)
    if selfcast == nil then selfcast = Spell[spell].known end
    local bonus = math.floor(Char.level / 2) + math.floor(skill * 0.1) + dex_bonus() + math.floor(Spells.minorelemental / 4)
    if bonus > skill then bonus = skill end
    if not selfcast then bonus = math.floor(bonus / 2) end
    return bonus
end

local function locklore_bonus(selfcast)
    return lore_bonus(403, lock_skill(), selfcast)
end

local function traplore_bonus(selfcast)
    return lore_bonus(404, trap_skill(), selfcast)
end

local function focus_bonus()
    if lmas_ranks == nil then update_lmas_ranks() end
    if lmas_ranks <= 0 then return 0 end
    return math.floor(dex_bonus() / 2) + (2 * lmas_ranks)
end

local function rjust(s, width)
    s = tostring(s)
    while #s < width do s = " " .. s end
    return s
end

local function show_bonuses()
    local db = dex_bonus()
    local ls = lock_skill()
    local ts = trap_skill()
    local llb = locklore_bonus()
    local tlb = traplore_bonus()
    if lmas_ranks == nil then update_lmas_ranks() end
    local fb = focus_bonus()
    local know403 = Spell[403].known and "(self-cast)" or "(halved since not self-cast)"
    local know404 = Spell[404].known and "(self-cast)" or "(halved since not self-cast)"

    respond("Dexterity bonus........| " .. rjust(db, 4))
    respond("Picking Locks bonus....| " .. rjust(ls, 4))
    respond("Locklore bonus.........| " .. rjust(llb, 4) .. "  " .. know403)
    respond("Disarming Traps bonus..| " .. rjust(ts, 4))
    respond("Traplore bonus.........| " .. rjust(tlb, 4) .. "  " .. know404)
    respond("Lock Mastery ranks.....| " .. rjust(lmas_ranks, 4))
    respond("LM Focus bonus.........| " .. rjust(fb, 4))
end

local function show_chart()
    local unlored = dex_bonus() + lock_skill()
    local lored = unlored + locklore_bonus()
    local fb = focus_bonus()
    local has_focus = fb and fb > 0

    if has_focus then
        respond(" UNLORED    W/LORE   W/FOCUS  LOCKPICK")
        respond("--------  --------  --------  --------------")
    else
        respond(" UNLORED    W/LORE  LOCKPICK")
        respond("--------  --------  --------------")
    end

    for _, pick in ipairs(LOCKPICKS) do
        local name, mult = pick[1], pick[2]
        local u = math.floor(unlored * mult) - 1
        local l = math.floor(lored * mult) - 1
        if has_focus then
            local f = math.floor((unlored + fb) * mult) - 1
            respond(rjust(u, 8) .. "  " .. rjust(l, 8) .. "  " .. rjust(f, 8) .. "  " .. name .. " (" .. mult .. ")")
        else
            respond(rjust(u, 8) .. "  " .. rjust(l, 8) .. "  " .. name .. " (" .. mult .. ")")
        end
    end

    -- Traps section
    local t_unlored = dex_bonus() + trap_skill() - 1
    local t_lored = t_unlored + traplore_bonus()
    respond("")
    if has_focus then
        local t_focus = t_unlored + fb
        respond("   TRAPS    W/LORE   W/FOCUS")
        respond("--------  --------  --------")
        respond(rjust(t_unlored, 8) .. "  " .. rjust(t_lored, 8) .. "  " .. rjust(t_focus, 8))
    else
        respond("   TRAPS    W/LORE")
        respond("--------  --------")
        respond(rjust(t_unlored, 8) .. "  " .. rjust(t_lored, 8))
    end
    respond("Values shown assume a 100 on a d100 roll.")
end

local function suggest_lockpick(difficulty)
    local base = dex_bonus() + lock_skill()
    local bonuses = { [false] = base, ["lore"] = base + locklore_bonus() }
    local fb = focus_bonus()
    if fb and fb > 0 then bonuses["focus"] = base + fb end

    local candidates = {}
    local best = nil
    for btype, bonus in pairs(bonuses) do
        for _, pick in ipairs(LOCKPICKS) do
            local name, mult = pick[1], pick[2]
            local n = math.floor(bonus * mult) - 1
            local roll = 100 - (n - difficulty)
            if roll < 2 then roll = 2 end
            local candidate = {n, roll, btype, name}
            if best == nil or n > best[1] then best = candidate end
            if roll <= 100 and (roll > 30 or #candidates == 0) then
                table.insert(candidates, candidate)
            end
        end
    end

    if #candidates == 0 and best then candidates = {best} end

    respond(" MAX   ROLL  BONUS   LOCKPICK")
    respond("----  -----  -----   --------------")
    for _, c in ipairs(candidates) do
        local n, roll, btype, lockpick = c[1], c[2], c[3], c[4]
        local type_str = btype and (rjust(tostring(btype), 5) .. " + ") or "        "
        respond(rjust(n, 4) .. "  " .. rjust(roll, 4) .. "+  " .. type_str .. lockpick)
    end
end

-- Main
local args = script.vars
if args[1] and args[1]:match("^%-?%d+$") then
    suggest_lockpick(math.abs(tonumber(args[1])))
elseif args[1] and args[1]:lower():match("stats") then
    show_bonuses()
else
    show_chart()
end
