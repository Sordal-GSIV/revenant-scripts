--- @revenant-script
--- name: ledger
--- version: 1.4.0
--- author: elanthia-online
--- contributors: Ondreian, Tysong
--- game: gs
--- description: Financial tracking ledger for silvers, bounty points, and locksmith fees
--- tags: silver,bounty,ledger,bank,tracking
---
--- Changelog (from Lich5):
---   v1.4.0 (2026-01-19): database indexes, terminal-table chart, YAML settings, CLI args
---   v1.3.4 (2023-09-18): note withdrawal tracking
---   v1.3.0 (2023-08-01): lootcap estimator
---   v1.2.0 (2023-07-01): add lootcap estimator for --report-character
---   v1.1.0 (2023-02-22): fix reports by game code, add --report-character
---
--- Usage:
---   ;ledger                     - start tracking (runs in background)
---   ;ledger --report-character  - enable per-character reporting
---   ;ledger --report-fees       - enable locksmith fee tracking
---   ;ledger --help              - show help
---
--- NOTE: Requires Revenant SQLite support. Transactions are tracked via
--- downstream hooks monitoring bank deposit/withdrawal messages.

local Ledger = {}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local settings = {
    report_character = false,
    report_fees = false,
}

-- Load saved settings
local function load_settings()
    local saved_char = CharSettings.ledger_report_character
    if saved_char ~= nil then
        settings.report_character = (saved_char == "true")
    end
    local saved_fees = CharSettings.ledger_report_fees
    if saved_fees ~= nil then
        settings.report_fees = (saved_fees == "true")
    end
end

local function save_settings()
    CharSettings.ledger_report_character = tostring(settings.report_character)
    CharSettings.ledger_report_fees = tostring(settings.report_fees)
end

-- Parse CLI args
local function parse_args()
    local args = Script.vars
    for i = 1, #args do
        local arg = args[i]
        if not arg then break end
        local lower = arg:lower()
        if lower:find("report%-?_?character") then
            local val = lower:match("=(.+)")
            if val == "off" or val == "false" or val == "no" or val == "0" then
                settings.report_character = false
            else
                settings.report_character = true
            end
        elseif lower:find("report%-?_?fees?") then
            local val = lower:match("=(.+)")
            if val == "off" or val == "false" or val == "no" or val == "0" then
                settings.report_fees = false
            else
                settings.report_fees = true
            end
        elseif lower == "help" or lower == "--help" then
            respond([[
Ledger Script - Track silver, bounty points, and fees

Usage: ;ledger [options]

Options:
  --report-character[=<on|off>]   Show per-character statistics
  --report-fees[=<on|off>]        Track and report locksmith pool fees
  --help                          Display this help message

Settings persist across script runs.
            ]])
            return false
        end
    end
    save_settings()
    return true
end

---------------------------------------------------------------------------
-- Transaction storage (JSON-based via CharSettings)
---------------------------------------------------------------------------
-- Transactions stored as JSON arrays in CharSettings
-- Key format: ledger_txns_YYYY_MM
local function current_key()
    local date = os.date("*t")
    return string.format("ledger_txns_%04d_%02d", date.year, date.month)
end

local function load_transactions()
    local key = current_key()
    local raw = CharSettings[key]
    if raw and raw ~= "" then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

local function save_transactions(txns)
    CharSettings[current_key()] = Json.encode(txns)
end

local function record_transaction(amount, txn_type)
    local txns = load_transactions()
    local date = os.date("*t")
    table.insert(txns, {
        amount    = amount,
        type      = txn_type,
        character = GameState.name,
        game      = GameState.game,
        year      = date.year,
        month     = date.month,
        day       = date.day,
        hour      = date.hour,
        timestamp = os.time(),
    })
    save_transactions(txns)
end

---------------------------------------------------------------------------
-- Query helpers
---------------------------------------------------------------------------
local function with_commas(n)
    local s = tostring(math.floor(n))
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        count = count + 1
        result = s:sub(i, i) .. result
        if count % 3 == 0 and i > 1 then
            result = "," .. result
        end
    end
    return result
end

local function sum_transactions(filter)
    local txns = load_transactions()
    local total = 0
    for _, txn in ipairs(txns) do
        local match = true
        for k, v in pairs(filter) do
            if txn[k] ~= v then
                match = false
                break
            end
        end
        if match then
            total = total + (txn.amount or 0)
        end
    end
    return total
end

local function query_sum(txn_type, period)
    local date = os.date("*t")
    local filter = {type = txn_type, game = GameState.game}
    if period == "yearly" then
        filter.year = date.year
    elseif period == "monthly" then
        filter.year = date.year
        filter.month = date.month
    elseif period == "daily" then
        filter.year = date.year
        filter.month = date.month
        filter.day = date.day
    elseif period == "hourly" then
        filter.year = date.year
        filter.month = date.month
        filter.day = date.day
        filter.hour = date.hour
    end
    return sum_transactions(filter)
end

local function character_sum(txn_type, period)
    local date = os.date("*t")
    local filter = {type = txn_type, game = GameState.game, character = GameState.name}
    if period == "yearly" then
        filter.year = date.year
    elseif period == "monthly" then
        filter.year = date.year
        filter.month = date.month
    elseif period == "daily" then
        filter.year = date.year
        filter.month = date.month
        filter.day = date.day
    elseif period == "hourly" then
        filter.year = date.year
        filter.month = date.month
        filter.day = date.day
        filter.hour = date.hour
    end
    return sum_transactions(filter)
end

---------------------------------------------------------------------------
-- Report display
---------------------------------------------------------------------------
local function print_report()
    local types = {"silver", "bounty"}
    if settings.report_fees then table.insert(types, "fee") end

    local header = string.format("%-10s %12s %12s %12s %12s",
        GameState.game, "hourly", "daily", "monthly", "yearly")
    respond("")
    respond(header)
    respond(string.rep("-", 58))

    for _, t in ipairs(types) do
        respond(string.format("%-10s %12s %12s %12s %12s",
            t,
            with_commas(query_sum(t, "hourly")),
            with_commas(query_sum(t, "daily")),
            with_commas(query_sum(t, "monthly")),
            with_commas(query_sum(t, "yearly"))
        ))
    end

    if settings.report_character then
        respond("")
        local char_header = string.format("%-10s %12s %12s %12s %12s",
            GameState.name, "hourly", "daily", "monthly", "yearly")
        respond(char_header)
        respond(string.rep("-", 58))
        for _, t in ipairs(types) do
            respond(string.format("%-10s %12s %12s %12s %12s",
                t,
                with_commas(character_sum(t, "hourly")),
                with_commas(character_sum(t, "daily")),
                with_commas(character_sum(t, "monthly")),
                with_commas(character_sum(t, "yearly"))
            ))
        end
    end

    if settings.report_fees then
        respond("")
        respond("Monthly Locksmith Fees: " .. with_commas(character_sum("fee", "monthly")) .. " silvers")
    end
    respond("")
end

---------------------------------------------------------------------------
-- Regex patterns for matching bank transactions
---------------------------------------------------------------------------
local withdraw_patterns = {
    "Very well, a withdrawal of ([%d,]+) silver",
    "teller scribbles the transaction into a book and hands you ([%d,]+) silver",
    "teller carefully records the transaction, .* hands you ([%d,]+) silver",
}

local deposit_patterns = {
    "You deposit ([%d,]+) silvers? into your account",
    "That's a total of ([%d,]+) silver",
    "That's ([%d,]+) silver",
    "You deposit your note worth ([%d,]+) into your account",
    "They add up to ([%d,]+) silver",
}

local debt_pattern = "I have a bill of ([%d,]+) silvers?"
local bounty_pattern = "%[You have earned ([%d,]+) bounty points"
local locksmith_fee_pattern = "(%d[%d,]*) silvers? fee has been collected"
local bank_trigger = "inter%-town bank transfer options? available"

local function parse_silver(s)
    return tonumber((s:gsub(",", "")))
end

---------------------------------------------------------------------------
-- Main event loop
---------------------------------------------------------------------------
local function main_loop()
    while true do
        local line = get()
        if not line then break end

        -- Check withdrawals
        local matched = false
        for _, pattern in ipairs(withdraw_patterns) do
            local silver_str = line:match(pattern)
            if silver_str then
                local silver = parse_silver(silver_str)
                if silver then
                    echo("recorded.withdraw : " .. tostring(silver))
                    record_transaction(-silver, "silver")
                end
                matched = true
                break
            end
        end

        -- Check debt collector
        if not matched then
            local debt_str = line:match(debt_pattern)
            if debt_str then
                -- Only count if preceded by debt collector entering
                local recent = reget(10)
                local is_debt = false
                if recent then
                    for _, prev in ipairs(recent) do
                        if prev:find("The local debt collector suddenly enters") then
                            is_debt = true
                            break
                        end
                    end
                end
                if is_debt then
                    local silver = parse_silver(debt_str)
                    if silver then
                        echo("recorded.withdraw (debt): " .. tostring(silver))
                        record_transaction(-silver, "silver")
                    end
                end
                matched = true
            end
        end

        -- Check deposits
        if not matched then
            for _, pattern in ipairs(deposit_patterns) do
                local silver_str = line:match(pattern)
                if silver_str then
                    local silver = parse_silver(silver_str)
                    if silver then
                        echo("recorded.deposit : " .. tostring(silver))
                        record_transaction(silver, "silver")
                    end
                    matched = true
                    break
                end
            end
        end

        -- Check bounty points
        if not matched then
            local bounty_str = line:match(bounty_pattern)
            if bounty_str then
                local amount = parse_silver(bounty_str)
                if amount then
                    record_transaction(amount, "bounty")
                end
                matched = true
            end
        end

        -- Check locksmith fees
        if not matched and settings.report_fees then
            local fee_str = line:match(locksmith_fee_pattern)
            if fee_str then
                local fee = parse_silver(fee_str)
                if fee then
                    if settings.report_fees then
                        echo("recorded.fee : " .. tostring(fee))
                    end
                    record_transaction(fee, "fee")
                end
                matched = true
            end
        end

        -- Display report at bank
        if line:find(bank_trigger) then
            print_report()
        end
    end
end

---------------------------------------------------------------------------
-- Entry point
---------------------------------------------------------------------------
load_settings()
if not parse_args() then return end
print_report()
main_loop()
