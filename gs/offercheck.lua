--- @revenant-script
--- name: offercheck
--- version: 1.0.0
--- author: Phocosoen
--- game: gs
--- description: Prevent accidentally offering non-gem/non-note items to other players
--- tags: offer,tip,safety
---
--- Listens for the offer message and cancels if the right-hand item
--- is not a gem or a valid note (mining chit, kraken chit, promissory note, bond note).

hide_me()

local VALID_NOTE_RE = Regex.new("mining chit|kraken chit|promissory note|bond note", "i")

while true do
    local line = get()

    local item_name, target = (line or ""):match(
        "You offer your (.-) to (.-), who has 30 seconds to accept the offer%.")

    if item_name and target then
        local item = GameObj.right_hand()

        if not item then
            echo("Error: No item detected in your right hand. Cancelling offer.")
            fput("cancel")
        else
            local is_valid_gem = item.type and item.type:find("gem")
            local is_valid_note = VALID_NOTE_RE:test(item.name or "")

            if not is_valid_gem and not is_valid_note then
                echo("The offered item (" .. item.name .. ") is NOT a gem or valid note! Cancelling offer.")
                fput("cancel")
            else
                echo("Offer verified: You are offering a valid item (" .. item.name .. ") to " .. target .. ".")
            end
        end
    end

    pause(0.25)
end
