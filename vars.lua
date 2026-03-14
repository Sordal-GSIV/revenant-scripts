--- @revenant-script
--- name: vars
--- version: 0.1.0
--- description: Manage persistent character variables (UserVars)

local args = require("lib/args")
local vars = require("lib/vars")

local parsed = args.parse(Script.vars[0] or "")
local cmd    = parsed.args[1]

if not cmd then
  -- List all vars by iterating CharSettings["vars"]
  local raw = CharSettings["vars"]
  if not raw or raw == "" then
    respond("No variables set.")
    return
  end
  local ok, t = pcall(Json.decode, raw)
  if not ok or type(t) ~= "table" then
    respond("(vars storage corrupted)")
    return
  end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  if #keys == 0 then
    respond("No variables set.")
  else
    respond(string.format("%-20s  %s", "Name", "Value"))
    respond(string.rep("-", 50))
    for _, k in ipairs(keys) do
      respond(string.format("%-20s  %s", k, tostring(t[k])))
    end
  end

elseif cmd == "set" then
  local name = parsed.args[2]
  -- Join remaining tokens so multi-word values like "hello world" work
  local val_parts = {}
  for i = 3, #parsed.args do val_parts[#val_parts + 1] = parsed.args[i] end
  local val = #val_parts > 0 and table.concat(val_parts, " ") or nil
  if not name or not val then
    respond("Usage: ;vars set <name> <value>")
    return
  end
  vars.set(name, val)
  respond(name .. " = " .. val)

elseif cmd == "get" then
  local name = parsed.args[2]
  if not name then
    respond("Usage: ;vars get <name>")
    return
  end
  local val = vars.get(name)
  if val == nil then
    respond(name .. " is not set.")
  else
    respond(name .. " = " .. tostring(val))
  end

elseif cmd == "unset" then
  local name = parsed.args[2]
  if not name then
    respond("Usage: ;vars unset <name>")
    return
  end
  vars.unset(name)
  respond(name .. " unset.")

elseif cmd == "clear" then
  local confirm = parsed.args[2]
  if confirm ~= "yes" then
    respond("Usage: ;vars clear yes  (this deletes ALL variables — 'yes' required)")
    return
  end
  -- Bulk clear by replacing the entire vars object
  CharSettings["vars"] = "{}"
  respond("All variables cleared.")

else
  respond("Usage: ;vars [set <name> <val> | get <name> | unset <name> | clear yes]")
end
