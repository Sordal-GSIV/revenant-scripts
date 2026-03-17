--- @revenant-script
--- name: shard
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Navigate to Shard thief guild using password from settings
--- tags: thief, guild, shard, navigation

local settings = get_settings()
local password = settings.shard_thief_password

DRCT.walk_to(13920)
fput("knock")
fput("say " .. tostring(password))
move("go door")
