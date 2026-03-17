--- @revenant-module
--- name: dr/expmonitor
--- description: Background exp gain reporter

local M = {}

local is_running = false
local baselines = {}  -- skill_name → { rank, pct }

--- Start monitoring. Resets all baselines from current skill values.
function M.start()
    is_running = true
    baselines = {}
    if DRSkill and DRSkill.all then
        for name, info in pairs(DRSkill.all()) do
            baselines[name] = { rank = info.rank, pct = info.pct }
        end
    end
end

--- Stop monitoring.
function M.stop()
    is_running = false
end

--- Report gains since start.
function M.report()
    if not is_running then
        respond("[expmonitor] Not running.")
        return
    end
    if not DRSkill or not DRSkill.all then
        respond("[expmonitor] DRSkill not available.")
        return
    end

    local current = DRSkill.all()
    local any_gain = false

    for name, now in pairs(current) do
        local base = baselines[name]
        if base then
            local rank_diff = now.rank - base.rank
            local pct_diff  = now.pct - base.pct
            if rank_diff > 0 or (rank_diff == 0 and pct_diff > 0) then
                respond(string.format("  %s: %d %d%% → %d %d%% (+%d ranks, %+d%%)",
                    name, base.rank, base.pct, now.rank, now.pct, rank_diff, pct_diff))
                any_gain = true
            end
        else
            -- New skill appeared since start
            respond(string.format("  %s: 0 0%% → %d %d%% (new)",
                name, now.rank, now.pct))
            any_gain = true
        end
    end

    if not any_gain then
        respond("[expmonitor] No gains detected.")
    end
end

--- Check if monitoring is active.
function M.running()
    return is_running
end

return M
