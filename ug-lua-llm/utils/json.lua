local JSON = {}

local requested = os.getenv("UG_LUA_LLM_JSON_BACKEND")
local backend, backend_name

local function load_cjson()
  local ok, module = pcall(require, "cjson")
  if ok then return module, "cjson" end
end

local function load_dkjson()
  local ok, module = pcall(require, "dkjson")
  if ok then return module, "dkjson" end
end

if requested == "cjson" then
  backend, backend_name = load_cjson()
elseif requested == "dkjson" then
  backend, backend_name = load_dkjson()
elseif requested and requested ~= "" then
  error("Unsupported JSON backend: " .. requested)
else
  backend, backend_name = load_cjson()
  if not backend then backend, backend_name = load_dkjson() end
end

if not backend then
  error("No JSON backend found; install dkjson or lua-cjson")
end

JSON.backend = backend_name
JSON.null = backend.null

-- Both backends represent JSON null with a truthy sentinel: lua-cjson uses a
-- light userdata and dkjson uses a table. Either one survives `value or default`
-- and escapes through the normalized API unless it is stripped explicitly.
-- Compare by identity; the sentinels' tostring() forms vary between platforms
-- and versions, so matching on their text is not reliable.
function JSON.is_null(value)
  return JSON.null ~= nil and value == JSON.null
end

-- Decoded JSON value with null collapsed to nil, so callers can use ordinary
-- Lua fallback chains without a backend sentinel winning them.
function JSON.value(value)
  if value == nil or JSON.is_null(value) then return nil end
  return value
end

-- Decoded JSON value when it is genuinely a string, otherwise nil. Guards the
-- normalized fields that carry a string contract.
function JSON.string_value(value)
  value = JSON.value(value)
  if type(value) == "string" then return value end
  return nil
end

function JSON.encode(value)
  if backend_name == "cjson" then return backend.encode(value) end
  -- cjson, the original backend, encodes an empty Lua table as an object.
  -- dkjson defaults it to an array, which would silently turn JSON Schema
  -- properties and empty tool arguments into the wrong wire type. Clone only
  -- for encoding and mark empty tables explicitly to retain compatibility.
  local function prepare(item, seen)
    if type(item) ~= "table" or item == backend.null then return item end
    seen = seen or {}
    if seen[item] then error("Cannot encode circular table as JSON") end
    seen[item] = true
    local copy = {}
    for key, child in pairs(item) do copy[key] = prepare(child, seen) end
    if next(copy) == nil then setmetatable(copy, { __jsontype = "object" }) end
    seen[item] = nil
    return copy
  end
  local encoded, err = backend.encode(prepare(value))
  if not encoded then error(err or "Failed to encode JSON") end
  return encoded
end

function JSON.decode(value)
  if backend_name == "cjson" then return backend.decode(value) end
  local decoded, _, err = backend.decode(value, 1, backend.null)
  if err then error(err) end
  return decoded
end

return JSON
