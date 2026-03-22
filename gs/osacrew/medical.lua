-- osacrew/medical.lua
-- Medical officer subsystem for OSA Crew.
-- Ported from osacrew.lic v6.0.6 (Ganalon / original authors).
-- Lines 657-789 and 2372-2390.

local M = {}

-- M.triage(osa, patient_list)
-- Waits up to 3s for additional "I Am Injured!" LNet messages on the crew
-- channel and accumulates sender names into patient_list (mutates in-place).
-- Recursively collects until the 3s window expires.
-- Source: medicalofficer_triage, lines 658-667.
function M.triage(osa, patient_list)
    local crew    = osa.crew_channel
    local pattern = "^%[" .. crew .. "%]-GSIV:(.-): \"I Am Injured!\"$"
    local result  = matchtimeout(3, pattern)
    if result then
        local sender = result:match(pattern)
        if sender then
            table.insert(patient_list, sender)
            M.triage(osa, patient_list)
        end
    end
end

-- M.checkup(osa, patient_list)
-- Waits for any running ecure to finish, then runs ecure for all patients
-- and waits for it to complete.
-- Source: medicalofficer_checkup, lines 669-685.
function M.checkup(osa, patient_list)
    if running("ecure") then
        wait_while(function() return running("ecure") end)
    end
    waitrt()
    waitcastrt()
    if stunned() then
        wait_until(function() return not stunned() end)
    end
    echo("Your Patients Are: " .. table.concat(patient_list, ", "))
    Script.run("ecure", table.concat(patient_list, " "))
    wait_while(function() return running("ecure") end)
    pause(0.2)
end

-- M.fix_muscles_ks(osa, person)
-- Waits for ecure to finish, pauses osacombat, transfers exertion to person,
-- then casts Spell 1107 (Kai's Strike) if affordable.
-- The "ks" variant transfers exertion first (Kai's Strike / Kroderine Soul path).
-- Source: medicalofficer_fix_muscles_ks, lines 687-702.
function M.fix_muscles_ks(osa, person)
    if running("ecure") then
        LNet.private(person, "Please wait one moment while I finish up.")
        wait_while(function() return running("ecure") end)
    end
    Script.pause("osacombat")
    wait_until(function() return not stunned() end)
    waitrt()
    waitcastrt()
    pause(0.5)
    fput("transfer " .. person .. " exertion")
    if Spell[1107]:affordable() then
        Spell[1107]:cast()
    end
    Script.unpause("osacombat")
end

-- M.fix_muscles(osa, person)
-- Waits for ecure, pauses osacombat, casts Spell 1107 directly at person.
-- Source: medicalofficer_fix_muscles, lines 704-718.
function M.fix_muscles(osa, person)
    if running("ecure") then
        LNet.private(person, "Please wait one moment while I finish up.")
        wait_while(function() return running("ecure") end)
    end
    Script.pause("osacombat")
    wait_until(function() return not stunned() end)
    waitrt()
    waitcastrt()
    pause(0.5)
    if Spell[1107]:affordable() then
        Spell[1107]:cast(person)
    end
    Script.unpause("osacombat")
end

-- M.fix_poison(osa, person)
-- Waits for ecure, pauses osacombat, casts Spell 114 (Purify Air) at person.
-- Source: medicalofficer_fix_poison, lines 720-734.
function M.fix_poison(osa, person)
    if running("ecure") then
        LNet.private(person, "Please wait one moment while I finish up.")
        wait_while(function() return running("ecure") end)
    end
    Script.pause("osacombat")
    wait_until(function() return not stunned() end)
    waitrt()
    waitcastrt()
    pause(0.5)
    if Spell[114]:affordable() then
        Spell[114]:cast(person)
    end
    Script.unpause("osacombat")
end

-- M.fix_disease(osa, person)
-- Waits for ecure, pauses osacombat, casts Spell 113 (Unpresence) at person.
-- Source: medicalofficer_fix_disease, lines 736-750.
function M.fix_disease(osa, person)
    if running("ecure") then
        LNet.private(person, "Please wait one moment while I finish up.")
        wait_while(function() return running("ecure") end)
    end
    Script.pause("osacombat")
    wait_until(function() return not stunned() end)
    waitrt()
    waitcastrt()
    pause(0.5)
    if Spell[113]:affordable() then
        Spell[113]:cast(person)
    end
    Script.unpause("osacombat")
end

-- M.give_bread_one(osa, person)
-- Offers bread; waits up to 3s for person to accept.  On timeout or refusal,
-- cancels the offer and drops whatever is in right hand.
-- Source: medicalofficer_give_bread, lines 752-759.
function M.give_bread_one(osa, person)
    local pat    = "^" .. person .. " has accepted your offer"
    local result = matchtimeout(3, pat)
    if result and result:match(pat) then
        return
    else
        multifput("cancel", "drop right")
    end
end

-- M.bread(osa, person)
-- If mana > 4: waits for RT/castRT, incants 203 (Spirit Bread), gives the
-- resulting item to person, then calls give_bread_one to confirm acceptance.
-- Source: medicalofficer_bread, lines 761-769.
function M.bread(osa, person)
    if GameState.mana > 4 then
        waitrt()
        waitcastrt()
        fput("incant 203")
        pause(1)
        local rh = GameObj.right_hand()
        if rh then
            fput("give #" .. rh.id .. " to " .. person)
            M.give_bread_one(osa, person)
        end
    end
end

-- M.bread_orders(osa, breadlist)
-- Collects up to 3s of "I Will Take Some Please." private LNet messages.
-- Pushes each sender into breadlist (mutates in-place).  Recurses until
-- the 3s window produces no more messages.
-- Source: medicalofficer_bread_orders, lines 772-779.
function M.bread_orders(osa, breadlist)
    local pattern = "^%[Private%]-GSIV:(.-): \"I Will Take Some Please%.\""
    local result  = matchtimeout(3, pattern)
    if result then
        local crewmate = result:match(pattern)
        if crewmate then
            table.insert(breadlist, crewmate)
            M.bread_orders(osa, breadlist)
        end
    end
end

-- M.spells(osa, recipient)
-- Waits for any running ewaggle to finish, then starts ewaggle for recipient.
-- Source: medicalofficer_spells, lines 781-789.
function M.spells(osa, recipient)
    if running("ewaggle") then
        LNet.private(recipient, "Please wait one moment while I finish up.")
        wait_while(function() return running("ewaggle") end)
    end
    waitrt()
    waitcastrt()
    Script.run("ewaggle", recipient)
end

-- M.receive_bread(osa, medical_officer)
-- Waits up to 30s for the medical officer to offer bread.  If the offer is
-- to "you" (this character), accepts and eats.  If the offer is to someone
-- else in the same message, recurses to keep waiting.
-- Source: crew_recieve_bread, lines 2372-2380.
function M.receive_bread(osa, medical_officer)
    local pat_you   = medical_officer .. " offers you %(a|some%)"
    local pat_other = medical_officer .. " offers (.-) %(a|some%)"
    local combined  = medical_officer .. " offers .* %(a|some%)"
    local result    = matchtimeout(30, combined)
    if result then
        if result:match(pat_you) then
            fput("accept")
            M.eat_bread(osa)
        elseif result:match(pat_other) then
            -- offer was to someone else; keep waiting
            M.receive_bread(osa, medical_officer)
        end
    end
end

-- M.eat_bread(osa)
-- Gobbles whatever is in right hand repeatedly until the hand is empty.
-- Source: crew_eat_bread, lines 2382-2389.
function M.eat_bread(osa)
    local rh = GameObj.right_hand()
    if rh then
        fput("gobble #" .. rh.id)
        -- re-check after the gobble command resolves
        rh = GameObj.right_hand()
        if rh then
            M.eat_bread(osa)
        end
    end
end

return M
