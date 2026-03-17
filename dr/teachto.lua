--- @revenant-script
--- name: teachto
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Wait for someone to arrive and teach them a skill (template script)
--- tags: teach, education
---
--- Usage: Edit "soandso" and "something" to match your student and skill.

while true do
    waitfor("soandso arrive")
    fput("teach something to soandso")
end
