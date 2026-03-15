--- Simple ASCII table renderer (replaces Ruby's Terminal::Table gem).
--- Usage:
---   local T = require("lib/table_render")
---   local tbl = T.new({"Level", "Creature", "Types"})
---   tbl:add_row({5, "kobold", "aggressive npc"})
---   tbl:add_separator()
---   tbl:add_row({6, "goblin", "aggressive npc"})
---   respond(tbl:render())

local M = {}
M.__index = M

function M.new(headings)
    local self = setmetatable({}, M)
    self.headings = headings
    self.rows = {}
    self.col_widths = {}
    for i, h in ipairs(headings) do
        self.col_widths[i] = #tostring(h)
    end
    return self
end

function M:add_row(data)
    local row = {}
    for i, v in ipairs(data) do
        local s = tostring(v)
        row[i] = s
        if #s > (self.col_widths[i] or 0) then
            self.col_widths[i] = #s
        end
    end
    for i = #row + 1, #self.headings do
        row[i] = ""
    end
    table.insert(self.rows, {type = "row", data = row})
end

function M:add_separator()
    table.insert(self.rows, {type = "sep"})
end

function M:render()
    local lines = {}
    local ncols = #self.headings

    local function border_line()
        local parts = {}
        for i = 1, ncols do
            parts[i] = string.rep("-", self.col_widths[i] + 2)
        end
        return "+" .. table.concat(parts, "+") .. "+"
    end

    local function format_row(data)
        local parts = {}
        for i = 1, ncols do
            local val = data[i] or ""
            parts[i] = " " .. val .. string.rep(" ", self.col_widths[i] - #val) .. " "
        end
        return "|" .. table.concat(parts, "|") .. "|"
    end

    table.insert(lines, border_line())
    table.insert(lines, format_row(self.headings))
    table.insert(lines, border_line())

    for _, entry in ipairs(self.rows) do
        if entry.type == "sep" then
            table.insert(lines, border_line())
        else
            table.insert(lines, format_row(entry.data))
        end
    end

    table.insert(lines, border_line())
    return table.concat(lines, "\n")
end

return M
