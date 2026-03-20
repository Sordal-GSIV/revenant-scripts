--- @revenant-script
--- @lic-certified: complete 2026-03-20
--- name: ht
--- version: 1.0.0
--- author: Ensayn (Revenant port)
--- description: Alias for ;high_type — forwards all arguments to the high_type script
--- game: gs
--- tags: highlighting, colors, alias
---
--- Syntax: ;ht [high_type command]
---   ;ht                       Show config / start daemon
---   ;ht add gem thought       Add a type→color mapping
---   ;ht remove gem            Remove a type mapping
---   ;ht help                  Show high_type help
---   (all other high_type commands are supported)

Script.run("high_type", Script.vars[0] or "")
