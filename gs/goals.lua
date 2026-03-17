--- @revenant-script
--- name: goals
--- version: 1.0.0
--- author: Tysong
--- game: gs
--- description: Shows your GOALS URL link for copy/paste into a browser.
--- tags: goals,planner

status_tags("on")

local line = dothistimeout("goals", 5, '<LaunchURL src="(.-)" />')
if line then
    local url_part = line:match('<LaunchURL src="(.-)" />')
    if url_part then
        echo("https://www.play.net" .. url_part)
    end
end
