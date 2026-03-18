--- @revenant-script
--- name: arenatimer
--- version: 1.1
--- author: Tysong (horibu on PC), original Nylis
--- game: gs
--- description: Duskruin Arena run timer — per-kill times, averages, and lnet end-of-run report
--- tags: duskruin, arena, timer, event
---
--- Syntax: ;arenatimer
---
--- Changelog (from Lich5 arenatimer2.lic):
---   v1.1 (2017-08-19) - Fixes for new arena messaging; 1v1/2v2/3v3 match support
---   v1.0 (2017-04-28) - Initial release
---   Revenant port: frontend detection via Frontend.supports_streams(); PCRE regexes
---
--- @lic-certified: complete 2026-03-18

-- Champion wave kill numbers (every 5th kill for a 25-kill Duskruin run)
local CHAMP = { [5]=true, [10]=true, [15]=true, [20]=true, [25]=true }

-- PCRE patterns (alternation/non-capturing groups require Regex.new, not Lua patterns)
local RE_INTRO  = Regex.new([=[An announcer shouts, "Introducing (?:.*)"]=])
local RE_PORTC  = Regex.new([=[An announcer shouts, "(?:.*)"  An iron portcullis is raised and .* (?:enter|enters) the arena!]=])
local RE_FIGHT  = Regex.new([=[An announcer shouts, "FIGHT!"  An iron portcullis is raised and .* (?:enter|enters) the arena!]=])
local RE_WIN    = Regex.new([=[An announcer boasts, "(?:.*) defeating all those that opposed .* The overwhelming sound of applauding echoes throughout the stands!]=])
local RE_ESCORT = Regex.new([=[An arena guard escorts you from the dueling sands|drags you out of the arena]=])

-- Output to familiar window when the frontend supports streams (Wrayth/Stormfront),
-- otherwise fall back to respond() for plain-text clients.
local function fam(text)
    if Frontend.supports_streams() then
        put("<pushStream id=\"familiar\" ifClosedStyle=\"watching\"/>" .. text .. "\r\n<popStream/>\r\n")
    else
        respond(text)
    end
end

-- Format a float/int of seconds as MM:SS (matches Ruby Time.at(secs).strftime("%M:%S"))
local function fmt_mmss(secs)
    secs = math.max(0, math.floor(secs + 0.5))
    return string.format("%02d:%02d", math.floor(secs / 60), secs % 60)
end

-- State (mirrors the Ruby globals in arenatimer2.lic)
local start_time = 0   -- os.time() when FIGHT! fires
local total_time = 0   -- elapsed seconds since start_time (updated each portcullis event)
local prev_total = 0   -- previous total_time — used to compute per-kill delta
local avg_reg    = 0   -- accumulated seconds for regular kills
local avg_champ  = 0   -- accumulated seconds for champion kills
local number     = 0   -- kill counter (0-indexed display; incremented after each portcullis)
local group_size = 0   -- 1, 2, or 3 (1v1, 2v2, 3v3)

local function reset()
    start_time = 0
    total_time = 0
    prev_total = 0
    avg_reg    = 0
    avg_champ  = 0
    number     = 0
end

-- Ruby: checkpcs.count >=2 → 3v3, ==1 → 2v2, nil → 1v1
local function detect_group_size()
    local pcs = GameObj.pcs()
    local count = #pcs
    if count >= 2 then return 3 end
    if count == 1 then return 2 end
    return 1
end

-- Handle a portcullis-raise event (the FIGHT! shout, or each subsequent kill).
-- Mirrors the elsif branch in the original Ruby:
--   (start_time = Time.now) if line =~ /FIGHT!/
--   kill_time = total_time; total_time = Time.now - start_time
--   kill_time = total_time - kill_time   (delta)
--   avg_reg/avg_champ += kill_time based on kill number
--   puts familiar window stats
--   number += 1
local function on_portcullis(line)
    if RE_FIGHT:test(line) then
        start_time = os.time()
    end
    prev_total = total_time
    total_time = os.time() - start_time
    local kill_delta = total_time - prev_total

    if not CHAMP[number] then
        avg_reg = avg_reg + kill_delta
    else
        avg_champ = avg_champ + kill_delta
    end

    fam(string.format("%dv%d DR-Kills: %d, Total Time %s, Kill Time: %s",
        group_size, group_size, number, fmt_mmss(total_time), fmt_mmss(kill_delta)))
    number = number + 1
end

-- Main event loop
while true do
    local line = get()

    if RE_INTRO:test(line) then
        -- Arena is starting — detect group size and announce
        fam("DR-Starting Arena")
        group_size = detect_group_size()

    elseif RE_PORTC:test(line) then
        -- A new opponent entered (or the fight began): record kill timing
        on_portcullis(line)

    elseif RE_WIN:test(line) then
        -- Player won the run — record final kill delta, compute averages, report
        prev_total = total_time
        total_time = os.time() - start_time
        local kill_delta = total_time - prev_total

        if not CHAMP[number] then
            avg_reg = avg_reg + kill_delta
        else
            avg_champ = avg_champ + kill_delta
        end

        -- Divisors match the original: 20 regular kills, 5 champion kills in a full run
        local avg_reg_per   = avg_reg   / 20
        local avg_champ_per = avg_champ / 5

        fam(string.format("DR-Winning Time: %s", fmt_mmss(total_time)))
        fam(string.format("DR-Avg Reg Kill: %s, Avg Champ Kill: %s",
            fmt_mmss(avg_reg_per), fmt_mmss(avg_champ_per)))
        send_to_script("lnet", string.format(
            "chat on DUSKRUIN %dv%d Finished: %s, Avg Reg Kill: %s, Avg Champ Kill: %s",
            group_size, group_size,
            fmt_mmss(total_time), fmt_mmss(avg_reg_per), fmt_mmss(avg_champ_per)))

    elseif RE_ESCORT:test(line) then
        -- Escorted out without finishing: reset all state
        reset()
    end
end
