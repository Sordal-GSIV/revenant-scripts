--- @revenant-script
--- @lic-certified: complete 2026-03-18
--- name: goals
--- version: 1.0.0
--- author: Tysong
--- game: gs
--- description: Shows your GOALS URL link for copy/paste into a browser.
--- tags: goals,planner
---
--- Changelog (from Lich5):
---   v1.0.0 (2025-09-01)
---     - initial release

status_tags("on")

local line = dothistimeout("goals", 5, '<LaunchURL src="(.-)" />')
if line then
    local url_part = line:match('<LaunchURL src="(.-)" />')
    if url_part then
        echo("https://www.play.net" .. url_part)
    end
end
