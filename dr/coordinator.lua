--- @revenant-script
--- name: coordinator
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: Task coordinator - manages hunting and town task rotation based on YAML config
--- tags: training, coordination, tasks, hunting, town
---
--- Ported from coordinator.lic (Lich5) to Revenant Lua
---
--- Requires: common, drinfomon, common-travel, common-items, common-arcana, common-money
---
--- YAML Settings:
---   coordinator_hunting_tasks: [...]
---   coordinator_town_tasks: [...]
---   coordinator_hunting_cleanup: [...]

local settings = get_settings()
local hunting_tasks = settings.coordinator_hunting_tasks or {}
local town_tasks = settings.coordinator_town_tasks or {}
local cleanup_tasks = settings.coordinator_hunting_cleanup or {}
local debug_mode = Script.vars[1] == "debug"

local timers = CharSettings.get("coordinator_timers") or {}

local function predicate_met(task)
    if not task then return false end
    if task.expn and DRSkill.getxp(task.expn) and DRSkill.getxp(task.expn) >= (task.mind_target or 30) then
        return false
    end
    if task.timer_name and timers[task.timer_name] then
        local elapsed = os.time() - timers[task.timer_name]
        if elapsed < (task.timer_seconds or 300) then
            return false
        end
    end
    return true
end

local function run_task(task)
    if not task then return end
    echo("Running task: " .. (task.script or task.name or "unknown"))
    if task.script then
        DRC.wait_for_script_to_complete(task.script, task.args or {})
    end
    if task.timer_name then
        timers[task.timer_name] = os.time()
        CharSettings.set("coordinator_timers", timers)
    end
end

local function get_next_task()
    -- Check cleanup tasks first
    for _, task in ipairs(cleanup_tasks) do
        if task.marked and predicate_met(task) then return task end
    end
    -- Then town tasks
    for _, task in ipairs(town_tasks) do
        if predicate_met(task) then return task end
    end
    -- Then hunting tasks
    for _, task in ipairs(hunting_tasks) do
        if predicate_met(task) then return task end
    end
    return nil
end

echo("=== Coordinator ===")
echo("Hunting tasks: " .. #hunting_tasks)
echo("Town tasks: " .. #town_tasks)
echo("Cleanup tasks: " .. #cleanup_tasks)

Flags.add("coord-song", "you finish playing")

while true do
    local task = get_next_task()
    if not task then
        echo("No more tasks available.")
        break
    end
    if debug_mode then echo("Next task: " .. tostring(task.script or task.name)) end
    run_task(task)
end
