local JSON = require "ug-lua-llm.utils.json"

local Options = {}

-- A table Lua would encode as a JSON array. Arrays are replaced wholesale
-- rather than merged: a generated `contents` or `messages` list must never be
-- interleaved with a caller's.
local function is_array(value)
  return value[1] ~= nil
end

local function mergeable(value)
  return type(value) == "table" and not is_array(value) and
    not JSON.is_null(value)
end

-- Overlay generated fields onto the caller's, recursing into nested objects.
-- Generated leaves always win, so required protocol fields cannot be replaced;
-- sibling keys the caller added alongside them survive.
local function overlay(target, generated)
  for key, value in pairs(generated) do
    if mergeable(value) and mergeable(target[key]) then
      overlay(target[key], value)
    else
      target[key] = value
    end
  end
end

local function deep_copy(value, seen)
  if type(value) ~= "table" or JSON.is_null(value) then return value end
  seen = seen or {}
  if seen[value] then error("Cannot merge circular request_options") end
  seen[value] = true
  local copy = {}
  for key, item in pairs(value) do copy[key] = deep_copy(item, seen) end
  seen[value] = nil
  return copy
end

-- Merge an explicit provider escape hatch into a generated payload. Generated
-- fields win, so callers cannot accidentally replace required protocol fields.
--
-- Nested objects are merged rather than overwritten. Providers build container
-- fields such as Gemini's `generationConfig`, and replacing the whole container
-- would silently discard anything a caller set inside it -- which made options
-- like `thinkingConfig` impossible to reach.
function Options.payload(base, options)
  local result = deep_copy((options and options.request_options) or {})
  overlay(result, base or {})
  return result
end

return Options
