-- gracemon.lua — part 2 of Coup de Grace script
-- Tracks the Empowerment buff and exits when it fades.
-- Launched by coup.lua; do not run directly.
--
-- @author: Gwrawr (stayrange)
-- @lic-source: gracemon.lic
-- @lic-certified: complete 2026-03-20

if not Script.exists("coup") then
    echo("This is part 2 of a 2 part script, please download coup.lua and run that instead")
    Script.exit()
end

hide_me()

waitfor("Your surge of empowerment fades")
