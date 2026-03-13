-- vars.lua
-- Display current CharSettings and UserVars.

respond("=== CharSettings (stored in revenant.db) ===")
respond("  Read:  CharSettings[\"key\"]")
respond("  Write: CharSettings[\"key\"] = value  (any type, stored as string)")
respond("  Tip:   tonumber(CharSettings[\"threshold\"]) to read as number")
respond("")
respond("=== UserVars (game-wide, not per-character) ===")
respond("  Read:  UserVars[\"key\"]")
respond("  Write: UserVars[\"key\"] = value")
