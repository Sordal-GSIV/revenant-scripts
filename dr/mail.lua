--- @revenant-script
--- name: mail
--- version: 1.0
--- author: Alastir/Dreaven
--- game: dr
--- description: Send and check in-game mail packages.
--- tags: mail, shipping, utility
--- Usage: ;mail <recipient> or ;mail check
--- Converted from mail.lic
local recipient = Script.vars[1]
if not recipient then echo("Usage: ;mail <recipient> or ;mail check") return end
if recipient:lower() == "check" then
    fput("stow left"); fput("stow right")
    wait_for_script_to_complete("go2", {"mail"})
    fput("mail check")
else
    echo("=== mail ===")
    echo("Mail sending requires go2 navigation and bank APIs.")
end
