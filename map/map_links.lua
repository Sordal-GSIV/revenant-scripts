-- map_links.lua
-- Hardcoded inter-map portal zones from the original map.lic
-- Each entry: { source_image, x1, x2, y1, y2, target_image, target_x, target_y }
local M = {}

M.links = {
    { "TI-teras.gif", 990, 1150, 415, 515, "TI-temple.gif", 700, 300 },
    { "TI-temple.gif", 0, 100, 200, 400, "TI-teras.gif", 1050, 465 },
    { "WL-wehnimers.gif", 1680, 1800, 0, 100, "EN-dragonspine.gif", 200, 900 },
    { "EN-dragonspine.gif", 100, 300, 850, 950, "WL-wehnimers.gif", 1740, 50 },
    { "EN-dragonspine.gif", 1800, 1920, 0, 100, "EN-victory.gif", 960, 700 },
    { "EN-victory.gif", 900, 1020, 650, 750, "EN-dragonspine.gif", 1860, 50 },
    { "WL-wehnimers.gif", 0, 120, 800, 900, "WL-coastal.gif", 1800, 200 },
    { "WL-coastal.gif", 1750, 1870, 150, 250, "WL-wehnimers.gif", 60, 850 },
    { "IMT-icemule.gif", 1580, 1700, 0, 100, "EN-dragonspine.gif", 900, 900 },
    { "EN-dragonspine.gif", 850, 950, 850, 950, "IMT-icemule.gif", 1640, 50 },
    { "TV-tavaalor.gif", 0, 120, 400, 500, "EN-dragonspine.gif", 1400, 900 },
    { "EN-dragonspine.gif", 1350, 1450, 850, 950, "TV-tavaalor.gif", 60, 450 },
}

function M.find_link_at(current_image, click_x, click_y)
    for _, link in ipairs(M.links) do
        if link[1] == current_image then
            if click_x >= link[2] and click_x <= link[3]
               and click_y >= link[4] and click_y <= link[5] then
                return {
                    target_image = link[6],
                    target_x = link[7],
                    target_y = link[8],
                }
            end
        end
    end
    return nil
end

return M
