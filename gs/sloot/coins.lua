--- sloot/coins.lua
-- deposit_coins and withdraw_coins routines.
-- Mirrors deposit_coins proc and withdraw_coins proc from sloot.lic v3.5.2.

local M = {}

--- Deposit all coins in the bank; optionally keep sell_withdraw amount.
function M.deposit_coins(settings)
    local silvers = checksilvers()
    local withdraw = tonumber(settings.sell_withdraw or "") or 0

    if (silvers == 0 and withdraw == 0) or silvers == withdraw then
        return
    end

    go2("bank")

    if settings.enable_sell_share_silvers and silvers > 1 then
        dothistimeout("share all", 5, Regex.new("In order to share|share"))
    end

    dothistimeout("deposit all", 5, Regex.new("The teller carefully records the transaction|^You have no coins to deposit\\.$"))

    if withdraw > 0 then
        dothistimeout("withdraw " .. withdraw .. " silvers", 5,
            Regex.new("^The teller carefully records the transaction.*hands you \\d+ silvers?\\.$|Very well"))
    end
end

--- Withdraw coins from the bank if below needed amount.
-- Returns true on success.
function M.withdraw_coins(amount)
    local silvers = checksilvers()
    if silvers >= amount then return true end

    local cur_room = Room.id
    go2("bank")

    if invisible() or hiding() then
        dothistimeout("unhide", 5, Regex.new("hiding|visible"))
    end

    local needed = amount - silvers
    local res = dothistimeout("withdraw " .. needed .. " silvers", 5,
        Regex.new("^The teller carefully records the transaction.*hands you \\d+ silvers?\\.$|I'm sorry.*you don't seem to have that much"))

    local success = false
    if res then
        if Regex.test(res, "I'm sorry") then
            success = false
        else
            success = true
        end
    else
        echo("[SLoot] unknown response for withdraw_coins")
    end

    if cur_room then go2(tostring(cur_room)) end
    return success
end

return M
