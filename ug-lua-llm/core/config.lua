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

  return config
end

-- Merge configurations
function Config.merge(base, override)
  local merged = {}

  for key, value in pairs(base) do
    merged[key] = key == "cancel_token" and value or copy_value(value)
  end

  for key, value in pairs(override or {}) do
    merged[key] = key == "cancel_token" and value or copy_value(value)
  end

  return merged
end

return Config
