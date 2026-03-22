-- map_links.lua
-- Inter-map portal zones from the original map.lic (ElanthiaMap::MapData::MAP_LINKS)
-- Each entry: { source_image, x1, x2, y1, y2, target_image, target_x, target_y }
local M = {}

M.links = {
    { "TI-teras.gif", 1962, 2238, 68, 192, "TI-wilds.gif", 840, 1252 },
    { "TI-teras.gif", 710, 972, 2130, 2260, "WL-wehnimers.gif", 2338, 1070 },
    { "TI-wilds.gif", 1124, 1412, 604, 682, "TI-vtull.gif", 2276, 1638 },
    { "TI-wilds.gif", 678, 1006, 1218, 1296, "TI-teras.gif", 2100, 130 },
    { "TI-wilds.gif", 1448, 1776, 1386, 1464, "EN-victory.gif", 660, 1340 },
    { "TI-vtull.gif", 2156, 2380, 1556, 1636, "TI-wilds.gif", 1246, 654 },
    { "WL-wehntower.gif", 1448, 1738, 1284, 1414, "WL-wehnimers.gif", 2182, 464 },
    { "WL-wehnimers.gif", 2198, 2314, 364, 480, "WL-wehntower.gif", 1622, 1332 },
    { "WL-wehnimers.gif", 2296, 2380, 1020, 1104, "TI-teras.gif", 858, 1010 },
    { "EN-victory.gif", 548, 724, 1256, 1332, "TI-wilds.gif", 1634, 1428 },
    { "EN-dragonspine.gif", 2038, 2130, 2180, 2272, "EN-victory.gif", 1654, 218 },
    { "EN-victory.gif", 1628, 1720, 144, 236, "EN-dragonspine.gif", 2092, 2218 },
}

--- Find a map link at the given image-space coordinates.
--- @param current_image string  Filename of the current map image
--- @param click_x number  X coordinate on the unscaled image
--- @param click_y number  Y coordinate on the unscaled image
--- @return table|nil  { target_image, target_x, target_y } or nil
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
