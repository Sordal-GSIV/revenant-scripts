--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: origami_master
--- version: 1.3.0
--- author: Wolenthor
--- game: gs
--- tags: origami, crafting, automation
--- description: Automate origami folding without paper cuts
---
--- Original Lich5 authors: Wolenthor
--- Ported to Revenant Lua from origami_master.lic v1.3.0
---
--- Usage:
---   ;origami_master <shape> <origami kit name>
---   ;origami_master <shape> <origami kit name> nosleep
---   ;origami_master help

local params = Script.vars

local function bold(msg)
    respond("<pushBold/>" .. msg .. "<popBold/>")
end

local function show_help()
    bold("Origami Master Help")
    respond("")
    respond("Usage: ;origami_master banana <origami kit name> [optional: nosleep]")
    respond("Example: ;origami_master banana humidor")
    respond("Example: ;origami_master banana humidor nosleep")
    bold("")
    bold("Festival Master Examples:")
    respond("Begin Origami - ASK MASTER ABOUT LEARN")
    respond("Advance to next level - ASK MASTER ABOUT ADVANCE")
    respond("Review available patterns - ASK MASTER ABOUT PATTERN SKILL ADEPT")
    respond("Review specific pattern - ASK MASTER ABOUT PATTERN NAME BANANA")
    respond("Learn pattern at master - ASK MASTER ABOUT BUY PATTERN BANANA")
    respond("Buy instructions parchment to learn at later date - ASK MASTER ABOUT BUY INSTRUCTIONS TEACHER")
    respond("Buy instructions to learn pattern at later date - ASK MASTER ABOUT BUY PATTERN BANANA")
end

if not params[1] or params[1]:lower() == "help" then
    show_help()
    return
end

local pattern = params[1]:lower()
local origami_kit = params[2] and params[2]:lower() or ""
local nosleep = params[3] and params[3]:lower() == "nosleep"
local sleep_time = nosleep and 1 or 7
local tally = 0

fput("get my " .. origami_kit)
fput("pluck my " .. origami_kit)
fput("stow my " .. origami_kit)
fput("origami fold " .. pattern)
tally = tally + 1

while true do
    local line = get()
    if Regex.test(line, "Tucking a final fold into place") then
        fput("origami unfold")
        tally = tally + 1
        bold("Shapes created this run: " .. tally)
        bold("Waiting " .. sleep_time .. "s")
        pause(sleep_time)
    elseif Regex.test(line, "You gently unfold") or Regex.test(line, "You put a") then
        fput("origami fold " .. pattern)
        bold("Waiting " .. sleep_time .. "s")
        pause(sleep_time)
    elseif Regex.test(line, "You surreptitiously smooth out the paper") then
        fput("origami fold " .. pattern)
        bold("Waiting " .. sleep_time .. "s")
        pause(sleep_time)
    elseif Regex.test(line, "You can TOSS it or throw it away") then
        fput("toss my paper")
        fput("toss my paper")
    elseif Regex.test(line, "You toss a") then
        fput("get my " .. origami_kit)
        fput("pluck my " .. origami_kit)
        fput("stow my " .. origami_kit)
    elseif Regex.test(line, "is already folded.  ORIGAMI UNFOLD will remove") then
        fput("origami unfold")
    elseif Regex.test(line, "You are about to unfold a") then
        fput("origami unfold")
    elseif Regex.test(line, "You must hold a piece of paper") then
        bold("------ PAPER MISSING OR NO ORIGAMI KIT ------")
        break
    elseif Regex.test(line, "Your mind feels overloaded with creativity") then
        bold("------ NO MORE ORIGAMI TODAY! ------")
        break
    elseif Regex.test(line, "It looks like you may need a little more healing time") or
           Regex.test(line, "At first glance, your finger appears unscathed") then
        bold("-------------- WOUNDED ---------------")
        break
    end
end

bold("Final tally this run: " .. tally)
bold("-------------- ENDING ---------------")
