--- @revenant-script
--- @lic-audit: validated 2026-03-18
--- name: totcandy
--- version: 3.0.4
--- author: elanthia-online
--- game: gs
--- tags: event, tot, candy, trick-or-treat, bundling, unwrap
--- description: Brown bag candy management for the Trick-or-Treat (ToT) event - unwrap, bundle, plan, rewards
---
--- Original Lich5 authors: elanthia-online community
--- Ported to Revenant Lua from totcandy.lic
---
--- Changelog (from Lich5):
---   v3.0.4 (2026-02-13): Improved focus navigation with shortest-path movement
---   v3.0.3 (2026-02-13): Removed expensive full-bag rescan after target bundling
---   v3.0.2 (2026-02-13): Fixed target bundle count handling
---   v3.0.1 (2026-02-13): Reverted rewards/planning count reads to focus traversal
---   v3.0.0 (2026-02-13): Made script fully self-contained, wrapped in module
---   v2.4.1 (2026-02-13): Rewards now reads counts from single LOOK IN response
---   v2.4.0 (2026-02-13): Updated rewards output to grouped live bag view
---   v2.3.0 (2026-02-13): Bundle commands use LOOK to choose TURN vs PUSH
---   v2.2.0 (2026-02-13): Added tier-progression bundling to selected target candy
---
--- Usage:
---   ;totcandy unwrap [count] [bag name]       - unwrap candies from bag
---   ;totcandy bundle [focus text|current] [N]  - bundle same-tier candies (3 of N = 1 of N+1)
---   ;totcandy all [unwrap_count] [bag name]    - unwrap then bundle everything
---   ;totcandy rewards                          - show reward table with current counts
---   ;totcandy plan                             - show bundle plan for all tiers
---   ;totcandy help                             - show usage

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_BAG_NAME = "brown bag"

local FOCUS_PATTERN        = 'labeled,%s*"([^"]+)"'
local OPEN_FOCUS_PATTERN   = 'compartment labeled,%s*"([^"]+)",%s*is currently '
local COUNT_PATTERN        = "There [ia][sr]e? (%d+) treats? inside"
local LOOK_COUNT_LINE_PAT  = "^%s*%((%d+)%)%s+(.-)%s*$"
local PULL_PATTERN         = "remove one piece|come up empty handed|no treats inside|need a free hand"
local BUNDLE_PATTERN       = "do not have anything to bundle|now has 2 bites|now has 3 bites|combined 3 bites|morphed into one bite|cannot bundle candy that is not of the same tier|need a free hand"
local TWIST_PATTERN        = "small treat is exposed|already unwrapped|You twist|Pulling on the outer ends"

-- Reward table: { candy_name, reward_description }
local CANDY_REWARD_ROWS = {
    { "some dried fruit",                                          "N/A (Tier 1)" },
    { "some sugar-dusted dried fruit",                             "a blue feather-shaped charm (6 charges)" },
    { "some sugar-dusted dried fruit dipped in chocolate",         "an enruned gold ring (60 charges)" },
    { "a chocolate-laced fruit coated in nonpareils",              "a swirling nexus orb (1 entry)" },
    { "a nonpareils-coated chocolate filled with fruit syrup",     "a warmly glowing orb (30 entries)" },
    { "a green candy",                                             "N/A (Tier 1)" },
    { "a swirled green candy",                                     "an urchin guide bond (60 days)" },
    { "a swirled green candy drizzled with caramel",               "a locker runner contract (60 items)" },
    { "a chocolate-dipped green candy topped with apple bits",     "a silvery blue potion (1 sip)" },
    { "a caramel-filled apple candy covered in milk chocolate",    "a locker expansion contract (10 items)" },
    { "a chocolate drop",                                          "N/A (Tier 1)" },
    { "a powdered chocolate drop",                                 "a birth certificate parchment (1)" },
    { "a powdered chocolate drop with lemon rind sprinkles",       "a squat pale grey crystal bottle (10 pills)" },
    { "a lemon-infused dark chocolate drop",                       "a thick stability contract (20 uses)" },
    { "a lemon-infused dark chocolate truffle",                    "a shimmering blue orb (1)" },
    { "a caramel square",                                          "N/A (Tier 1)" },
    { "a caramel and cream square",                                "a muscular arm token (100 uses)" },
    { "a caramel and cream square with chocolate corners",         "a bulging muscular arm token (90 days)" },
    { "an orange cream caramel square with chocolate corners",     "a swirling yellow-green potion (3 charges, 30 days each)" },
    { "a creamy orange caramel square dipped in chocolate",        "a potent yellow-green potion (4 charges, 1 month each)" },
    { "a candy stick",                                             "N/A (Tier 1)" },
    { "a cherry candy stick",                                      "an Elanthian Guilds voucher pack (10 uses)" },
    { "a cherry and vanilla candy stick",                          "an Adventurer's Guild voucher pack (40 uses)" },
    { "a swirled cherry-vanilla stick with chocolate tips",        "an Adventurer's Guild task waiver (60 days)" },
    { "a chocolate-tipped cherry-vanilla stick with peppermint crumbles", "a Guild Night form (3.5 hours)" },
}

-- Candy groups: each group is a tier progression from tier 1 (base) to tier 5
local CANDY_GROUPS = {
    {
        "some dried fruit",
        "some sugar-dusted dried fruit",
        "some sugar-dusted dried fruit dipped in chocolate",
        "a chocolate-laced fruit coated in nonpareils",
        "a nonpareils-coated chocolate filled with fruit syrup",
    },
    {
        "a green candy",
        "a swirled green candy",
        "a swirled green candy drizzled with caramel",
        "a chocolate-dipped green candy topped with apple bits",
        "a caramel-filled apple candy covered in milk chocolate",
    },
    {
        "a small chocolate drop",
        "a powdered chocolate drop",
        "a powdered chocolate drop with lemon rind sprinkles",
        "a lemon-infused dark chocolate drop",
        "a lemon-infused dark chocolate truffle",
    },
    {
        "a caramel square",
        "a caramel and cream square",
        "a caramel and cream square with chocolate corners",
        "an orange cream caramel square with chocolate corners",
        "a creamy orange caramel square dipped in chocolate",
    },
    {
        "a candy stick",
        "a cherry candy stick",
        "a cherry and vanilla candy stick",
        "a swirled cherry-vanilla stick with chocolate tips",
        "a chocolate-tipped cherry-vanilla stick with peppermint crumbles",
    },
}

-- Build the full cycle order: wrapped candy first, then all candy labels in order
local CANDY_CYCLE_ORDER = { "a wrapped piece of candy" }
for _, group in ipairs(CANDY_GROUPS) do
    for _, label in ipairs(group) do
        table.insert(CANDY_CYCLE_ORDER, label)
    end
end

-- Build reward lookup map
local REWARD_MAP = {}
for _, row in ipairs(CANDY_REWARD_ROWS) do
    REWARD_MAP[row[1]] = row[2]
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function normalize_label(label)
    local text = tostring(label or ""):match("^%s*(.-)%s*$")
    text = text:gsub("%.$", "")
    text = text:gsub("%s+", " ")
    return text
end

local function parse_focus_state(text)
    local line = tostring(text or "")
    local label_raw = line:match(FOCUS_PATTERN)
    local label = label_raw and normalize_label(label_raw) or nil
    local count_str = line:match(COUNT_PATTERN)
    local count = count_str and tonumber(count_str) or 0
    return { label = label, count = count, raw = line }
end

local function cycle_focus(bag_name, direction)
    direction = direction or "turn"
    local response = dothistimeout(direction .. " my " .. bag_name, 3,
        "labeled|turn|push|What were you referring|can't|cannot")
    return parse_focus_state(response)
end

local function current_focus_from_look(bag_name)
    local response = dothistimeout("look in my " .. bag_name, 6,
        "compartment labeled")
    if not response then return nil end
    local label = response:match(OPEN_FOCUS_PATTERN)
    if not label then return nil end
    return normalize_label(label)
end

local function navigation_plan(current_label, target_label, cycle_order)
    if not cycle_order or #cycle_order == 0 then return nil end

    local norm_current = string.lower(normalize_label(current_label))
    local norm_target  = string.lower(normalize_label(target_label))

    local current_idx, target_idx
    for i, lbl in ipairs(cycle_order) do
        local norm = string.lower(normalize_label(lbl))
        if norm == norm_current then current_idx = i end
        if norm == norm_target then target_idx = i end
    end

    if not current_idx or not target_idx then return nil end

    local size = #cycle_order
    local forward_steps  = (target_idx - current_idx) % size
    local backward_steps = (current_idx - target_idx) % size

    if forward_steps <= backward_steps then
        return { direction = "turn", steps = forward_steps }
    else
        return { direction = "push", steps = backward_steps }
    end
end

local function focus_on_label(bag_name, target_text, max_steps, cycle_order, current_label)
    max_steps = max_steps or 80

    -- Try navigation plan if we know current position and cycle order
    if current_label and cycle_order then
        local plan = navigation_plan(current_label, target_text, cycle_order)
        if plan then
            if plan.steps == 0 then
                return { label = normalize_label(current_label), count = nil, raw = "" }
            end
            local state = nil
            for _ = 1, plan.steps do
                state = cycle_focus(bag_name, plan.direction)
            end
            if state then return state end
        end
    end

    -- Fallback: linear search
    for _ = 1, max_steps do
        local state = cycle_focus(bag_name, "turn")
        if state.label and string.find(string.lower(state.label), string.lower(target_text), 1, true) then
            return state
        end
    end
    return nil
end

local function clear_hands_to_bag(bag_name)
    local right = GameObj.right_hand()
    local left  = GameObj.left_hand()
    if right and right.id then
        fput("put #" .. tostring(right.id) .. " in my " .. bag_name)
    end
    if left and left.id then
        fput("put #" .. tostring(left.id) .. " in my " .. bag_name)
    end
end

local function pull_piece(bag_name)
    return dothistimeout("pull my " .. bag_name, 4, PULL_PATTERN)
end

local function twist_held_candy()
    local candy = GameObj.right_hand() or GameObj.left_hand()
    if not candy then return nil end
    return dothistimeout("twist #" .. tostring(candy.id), 4, TWIST_PATTERN)
end

local function bundle_held_candy()
    return dothistimeout("bundle", 4, BUNDLE_PATTERN)
end

--------------------------------------------------------------------------------
-- Bundle from current focus
--------------------------------------------------------------------------------

local function bundle_from_current_focus(bag_name, bundle_goal)
    clear_hands_to_bag(bag_name)
    local bundled = 0

    while true do
        if bundle_goal and bundled >= bundle_goal then break end

        local pull_result = tostring(pull_piece(bag_name) or "")
        if pull_result:match("come up empty handed") or pull_result:match("no treats inside") then
            break
        end

        if pull_result:match("need a free hand") then
            clear_hands_to_bag(bag_name)
            goto continue
        end

        local bundle_result = tostring(bundle_held_candy() or "")
        if bundle_result:match("combined 3 bites") or bundle_result:match("morphed into one bite") then
            bundled = bundled + 1
            clear_hands_to_bag(bag_name)
        elseif bundle_result:match("cannot bundle candy that is not of the same tier") or
               bundle_result:match("need a free hand") then
            clear_hands_to_bag(bag_name)
        end
        -- else: keep current held candy for next pull/bundle pass

        ::continue::
    end

    clear_hands_to_bag(bag_name)
    return bundled
end

--------------------------------------------------------------------------------
-- Unwrap from wrapped focus
--------------------------------------------------------------------------------

local function unwrap_from_wrapped_focus(bag_name, unwrap_limit)
    local focus = focus_on_label(bag_name, "wrapped piece of candy")
    if not focus then return nil end

    local unwrapped = 0
    while true do
        if unwrap_limit and unwrapped >= unwrap_limit then break end

        local pull_result = tostring(pull_piece(bag_name) or "")
        if pull_result:match("come up empty handed") or pull_result:match("no treats inside") then
            break
        end

        if pull_result:match("need a free hand") then
            clear_hands_to_bag(bag_name)
            goto continue
        end

        twist_held_candy()
        clear_hands_to_bag(bag_name)
        unwrapped = unwrapped + 1

        ::continue::
    end

    return { unwrapped = unwrapped, start_label = focus.label }
end

--------------------------------------------------------------------------------
-- Full cycle bundle (unwrap + bundle all)
--------------------------------------------------------------------------------

local function full_cycle_bundle(bag_name, unwrap_limit)
    local unwrap_result = unwrap_from_wrapped_focus(bag_name, unwrap_limit)
    if not unwrap_result then return nil end

    local bundles_done = 0
    local start_label = unwrap_result.start_label
    local visited_labels = {}

    while true do
        local state = cycle_focus(bag_name, "turn")
        local label = state.label

        if not label then break end
        if label == start_label and visited_labels[label] then break end

        visited_labels[label] = true

        if string.find(string.lower(label), "wrapped piece of candy") then
            goto continue
        end
        if state.count < 3 then
            goto continue
        end

        local planned_bundles = math.floor(state.count / 3)
        bundles_done = bundles_done + bundle_from_current_focus(bag_name, planned_bundles)

        ::continue::
    end

    return { unwrapped = unwrap_result.unwrapped, bundled = bundles_done }
end

--------------------------------------------------------------------------------
-- Scan focus counts
--------------------------------------------------------------------------------

local function scan_focus_counts(bag_name, max_steps)
    max_steps = max_steps or 120
    local counts = {}

    local first_state = cycle_focus(bag_name, "turn")
    local first_label = first_state.label
    if not first_label then return counts end

    counts[first_label] = first_state.count
    local steps = 0

    while steps < max_steps do
        local state = cycle_focus(bag_name, "turn")
        local label = state.label
        if not label then break end
        if label == first_label then break end

        counts[label] = state.count
        steps = steps + 1
    end

    return counts
end

--------------------------------------------------------------------------------
-- Bundle planning
--------------------------------------------------------------------------------

local function compute_bundle_plan(group_labels, counts_by_label, target_index)
    local working = {}
    for i, label in ipairs(group_labels) do
        working[i] = counts_by_label[normalize_label(label)] or 0
    end

    local operations = {}
    for i = 1, #group_labels do
        operations[i] = 0
    end

    for idx = 1, target_index - 1 do
        operations[idx] = math.floor(working[idx] / 3)
        working[idx] = working[idx] % 3
        working[idx + 1] = working[idx + 1] + operations[idx]
    end

    return {
        operations = operations,
        projected_target = working[target_index],
        projected_counts = working,
    }
end

local function compute_exact_target_plan(group_labels, counts_by_label, target_index, target_count)
    local working = {}
    for i, label in ipairs(group_labels) do
        working[i] = counts_by_label[normalize_label(label)] or 0
    end

    local operations = {}
    local required = {}
    for i = 1, #group_labels do
        operations[i] = 0
        required[i] = 0
    end
    required[target_index] = target_count

    for idx = target_index - 1, 1, -1 do
        local needed = required[idx + 1] * 3
        local available = working[idx]
        local consumed = math.min(available, needed)
        working[idx] = available - consumed
        required[idx] = needed - consumed
        operations[idx] = required[idx + 1]
    end

    return {
        feasible = (required[1] == 0),
        operations = operations,
    }
end

--------------------------------------------------------------------------------
-- Target label resolution
--------------------------------------------------------------------------------

local function resolve_target_label(input_text)
    local needle = string.lower(normalize_label(input_text))
    if needle == "" then return nil end

    for _, group in ipairs(CANDY_GROUPS) do
        for _, label in ipairs(group) do
            if string.find(string.lower(normalize_label(label)), needle, 1, true) then
                return label
            end
        end
    end
    return nil
end

local function find_group_for_label(target_label)
    local norm_target = string.lower(normalize_label(target_label))
    for _, group in ipairs(CANDY_GROUPS) do
        for _, label in ipairs(group) do
            if string.lower(normalize_label(label)) == norm_target then
                return group
            end
        end
    end
    return nil
end

local function find_index_in_group(group, target_label)
    local norm_target = string.lower(normalize_label(target_label))
    for i, label in ipairs(group) do
        if string.lower(normalize_label(label)) == norm_target then
            return i
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Bundle to target tier
--------------------------------------------------------------------------------

local function run_bundle_to_target(bag_name, target_label, target_count)
    local norm_target = normalize_label(target_label)
    local group = find_group_for_label(target_label)
    if not group then
        echo("totcandy: could not match target group for '" .. target_label .. "'.")
        return
    end

    local target_index = find_index_in_group(group, target_label)
    if not target_index then
        echo("totcandy: could not find target index for '" .. target_label .. "'.")
        return
    end

    local counts = scan_focus_counts(bag_name)
    local plan = compute_bundle_plan(group, counts, target_index)
    local operations = plan.operations
    local initial_target_count = counts[norm_target] or 0

    if target_count then
        if target_count <= 0 then
            echo("totcandy: bundle count must be greater than 0.")
            return
        end

        if target_index == 1 then
            echo("totcandy: '" .. target_label .. "' is a base tier and cannot be created by bundling.")
            return
        end

        local exact_plan = compute_exact_target_plan(group, counts, target_index, target_count)
        if not exact_plan.feasible then
            local max_makeable = math.max(plan.projected_target - initial_target_count, 0)
            echo("totcandy: not enough candy to make " .. tostring(target_count) ..
                " '" .. target_label .. "' (max makeable " .. tostring(max_makeable) .. ").")
            return
        end

        operations = exact_plan.operations
    end

    local total_bundles = 0
    local produced_by_tier = {}
    for i = 1, #group do
        produced_by_tier[i] = 0
    end

    for idx = 1, target_index - 1 do
        local bundles_needed = operations[idx]
        if bundles_needed and bundles_needed > 0 then
            local curr_focus = current_focus_from_look(bag_name)
            local focus = focus_on_label(bag_name, group[idx], nil, CANDY_CYCLE_ORDER, curr_focus)
            if not focus then
                echo("totcandy: failed to focus '" .. group[idx] .. "'. stopping early.")
                break
            end

            local completed = bundle_from_current_focus(bag_name, bundles_needed)
            total_bundles = total_bundles + completed
            produced_by_tier[idx + 1] = produced_by_tier[idx + 1] + completed
        end
    end

    local made = produced_by_tier[target_index] or 0
    local final_target_count = initial_target_count + made

    if target_count then
        echo("totcandy: target '" .. target_label .. "' requested " .. tostring(target_count) ..
            ", made " .. tostring(made) .. ", now " .. tostring(final_target_count) ..
            ". bundles run: " .. tostring(total_bundles) .. ".")
    else
        echo("totcandy: target '" .. target_label .. "' projected " .. tostring(plan.projected_target) ..
            ", now " .. tostring(final_target_count) ..
            ". bundles run: " .. tostring(total_bundles) .. ".")
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local function parse_optional_count(args, pos)
    pos = pos or 1
    if not args[pos] then return nil, pos end
    if args[pos]:match("^%d+$") then
        local count = tonumber(args[pos])
        return count, pos + 1
    end
    return nil, pos
end

local function cmd_unwrap(args)
    local unwrap_limit, next_pos = parse_optional_count(args, 1)
    local bag_name = DEFAULT_BAG_NAME
    if args[next_pos] then
        local parts = {}
        for i = next_pos, #args do
            table.insert(parts, args[i])
        end
        if #parts > 0 then
            bag_name = table.concat(parts, " ")
        end
    end

    local result = unwrap_from_wrapped_focus(bag_name, unwrap_limit)
    if not result then
        echo("totcandy: could not focus wrapped candy in my " .. bag_name .. ".")
        return
    end

    echo("totcandy: unwrapped " .. tostring(result.unwrapped) .. " candy.")
end

local function cmd_bundle(args)
    local bag_name = DEFAULT_BAG_NAME

    -- Check if last arg is a number (bundle goal)
    local bundle_goal = nil
    if #args > 0 and args[#args]:match("^%d+$") then
        bundle_goal = tonumber(table.remove(args))
    end

    local focus_text = table.concat(args, " "):match("^%s*(.-)%s*$")

    if focus_text ~= "" and string.lower(focus_text) ~= "current" then
        -- Try to resolve as a target label for tier-progression bundling
        local resolved = resolve_target_label(focus_text)
        if resolved then
            run_bundle_to_target(bag_name, resolved, bundle_goal)
            return
        end

        -- Otherwise, navigate to that focus and bundle
        local curr_focus = current_focus_from_look(bag_name)
        local focus = focus_on_label(bag_name, focus_text, nil, CANDY_CYCLE_ORDER, curr_focus)
        if not focus then
            echo("totcandy: could not focus on '" .. focus_text .. "' in my " .. bag_name .. ".")
            return
        end
    end

    local bundled = bundle_from_current_focus(bag_name, bundle_goal)
    echo("totcandy: completed " .. tostring(bundled) .. " bundles.")
end

local function cmd_all(args)
    local unwrap_limit, next_pos = parse_optional_count(args, 1)
    local bag_name = DEFAULT_BAG_NAME
    if args[next_pos] then
        local parts = {}
        for i = next_pos, #args do
            table.insert(parts, args[i])
        end
        if #parts > 0 then
            bag_name = table.concat(parts, " ")
        end
    end

    local result = full_cycle_bundle(bag_name, unwrap_limit)
    if not result then
        echo("totcandy: could not focus wrapped candy in my " .. bag_name .. ".")
        return
    end

    echo("totcandy: unwrapped " .. tostring(result.unwrapped) ..
        ", completed " .. tostring(result.bundled) .. " bundles.")
end

local function cmd_rewards()
    local bag_name = DEFAULT_BAG_NAME
    local counts = scan_focus_counts(bag_name)

    if not counts or not next(counts) then
        echo("totcandy: unable to parse counts from 'look in my " .. bag_name .. "'.")
        return
    end

    local wrapped_label = "a wrapped piece of candy"
    local wrapped_count = counts[normalize_label(wrapped_label)] or 0

    echo("WRAPPED CANDY")
    echo("(" .. tostring(wrapped_count) .. ") " .. wrapped_label)
    echo("")

    for group_index, group in ipairs(CANDY_GROUPS) do
        echo("GROUP " .. tostring(group_index))

        for tier_index, label in ipairs(group) do
            local norm = normalize_label(label)
            local current_count = counts[norm] or 0
            local plan = compute_bundle_plan(group, counts, tier_index)
            local projected = plan.projected_target
            local reward = REWARD_MAP[label] or "N/A"

            echo("(" .. tostring(current_count) .. ") " .. label)
            echo("  reward: " .. reward)
            echo("  makeable now: " .. tostring(projected))
        end

        echo("")
    end
end

local function cmd_plan()
    local bag_name = DEFAULT_BAG_NAME
    local counts = scan_focus_counts(bag_name)

    if not counts or not next(counts) then
        echo("totcandy: unable to read bag counts.")
        return
    end

    echo("=== BUNDLE PLAN ===")
    for group_index, group in ipairs(CANDY_GROUPS) do
        echo("")
        echo("GROUP " .. tostring(group_index) .. ":")
        for tier_index, label in ipairs(group) do
            local norm = normalize_label(label)
            local current_count = counts[norm] or 0
            local plan = compute_bundle_plan(group, counts, tier_index)
            local projected = plan.projected_target

            local line = "  T" .. tostring(tier_index) .. ": " ..
                "(" .. tostring(current_count) .. ") " .. label
            if tier_index > 1 then
                line = line .. "  [makeable: " .. tostring(projected) .. "]"
            end
            echo(line)
        end
    end
    echo("")
    echo("===================")
end

local function show_usage()
    echo("totcandy - Brown bag candy helper for the ToT event")
    echo("")
    echo("usage: ;totcandy unwrap [count] [bag name]       - unwrap candies")
    echo("usage: ;totcandy bundle [focus text|current] [N]  - bundle candies")
    echo("usage: ;totcandy all [unwrap_count] [bag name]    - unwrap + bundle all")
    echo("usage: ;totcandy rewards                          - show reward table")
    echo("usage: ;totcandy plan                             - show bundle plan")
    echo("usage: ;totcandy help                             - show this help")
    echo("")
    echo("examples:")
    echo("  ;totcandy unwrap 100")
    echo("  ;totcandy bundle \"a caramel square\" 5")
    echo("  ;totcandy bundle current 10")
    echo("  ;totcandy all 250")
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local args = {}
for i = 1, 20 do
    local v = Script.vars[i]
    if not v or v == "" then break end
    table.insert(args, v)
end

local command = string.lower(args[1] or "help")

-- Remove the command token from args for subcommands
local sub_args = {}
for i = 2, #args do
    table.insert(sub_args, args[i])
end

if command == "unwrap" or command == "u" then
    cmd_unwrap(sub_args)
elseif command == "bundle" or command == "b" or command == "focus" or command == "f" then
    cmd_bundle(sub_args)
elseif command == "all" or command == "auto" or command == "full" then
    cmd_all(sub_args)
elseif command == "rewards" or command == "reward" or command == "table" or command == "list" then
    cmd_rewards()
elseif command == "plan" then
    cmd_plan()
elseif command == "help" or command == "-h" or command == "--help" then
    show_usage()
else
    -- Default to bundle behavior
    cmd_bundle(args)
end
