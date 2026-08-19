local Config = {}

-- Default configuration values
local defaults = {
  timeout = 120,
  retries = 3,
  retry_delay = 1,
  retry_predicate = nil,
  backoff = nil,
  cancel_token = nil,
  on_request = nil,
  on_response = nil,
  on_retry = nil,
  on_error = nil,
  base_url = nil,
  api_key = nil,
  model = nil,
  temperature = 0.7,
  max_tokens = 1024,
  headers = {},
  debug = false,
}

local function copy_value(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy_value(item) end
  return result
end

-- Create a new configuration with user overrides
function Config.new(opts)
  opts = opts or {}
  local config = {}

  -- Apply defaults, then override with user options
  for key, value in pairs(defaults) do
    local selected = opts[key] ~= nil and opts[key] or value
    config[key] = key == "cancel_token" and selected or copy_value(selected)
  end

  -- Add extra user options not in defaults
  for key, value in pairs(opts) do
    if config[key] == nil then
      config[key] = key == "cancel_token" and value or copy_value(value)
    end
  end

  -- Which keys the caller supplied, as opposed to the ones filled in here.
  -- Some providers reject a parameter outright unless the model supports it,
  -- and forcing a library default onto every request fails calls the caller
  -- never asked to constrain.
  --
  -- A resolved config is wrapped again on its way through the client and the
  -- provider. By then every key is present, so recomputing this from its keys
  -- would mark the library's own defaults as the caller's choices. Carry the
  -- original record forward instead, which makes re-wrapping idempotent.
  local explicit = {}
  if type(opts._explicit) == "table" then
    for key in pairs(opts._explicit) do explicit[key] = true end
  else
    for key in pairs(opts) do explicit[key] = true end
  end
  config._explicit = explicit

  return config
end

--- True when the caller chose this value rather than inheriting a default.
function Config.is_explicit(config, key)
  return not not (config and config._explicit and config._explicit[key])
end

-- Merge configurations
function Config.merge(base, override)
  local merged = {}

  for key, value in pairs(base) do
    merged[key] = key == "cancel_token" and value or copy_value(value)
  end

  local explicit = {}
  for key in pairs((base and base._explicit) or {}) do explicit[key] = true end
  for key in pairs(override or {}) do explicit[key] = true end

  for key, value in pairs(override or {}) do
    merged[key] = key == "cancel_token" and value or copy_value(value)
  end

  merged._explicit = explicit
  return merged
end

return Config
