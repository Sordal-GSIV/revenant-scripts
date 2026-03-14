--- Shared argument parser for Revenant scripts.
--- Only long-form --flag and --flag=value are supported.

local M = {}

--- Parse a space-separated argument string from Script.vars[0].
---
--- Script.vars[0] contains only the user-supplied arguments (no script name prefix).
--- All non-flag tokens go into result.args. Flags set named keys on the result table.
---
--- Example:
---   args.parse("add foo --global")
---   → { args = {"add", "foo"}, global = true }
---
--- Unknown flags are accepted and stored as-is (permissive parsing).
function M.parse(input)
  local result = { args = {} }
  if not input or input == "" then return result end

  for token in input:gmatch("%S+") do
    if token:match("^%-%-") then
      local key, val = token:match("^%-%-([%w_-]+)=?(.*)")
      if key then
        key = key:gsub("-", "_")
        result[key] = (val ~= "") and val or true
      end
    else
      result.args[#result.args + 1] = token
    end
  end

  return result
end

return M
