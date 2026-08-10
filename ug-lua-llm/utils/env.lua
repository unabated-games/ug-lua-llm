-- Simple utility to load environment variables from a .env file
local env = {
  -- Internal storage for loaded environment variables
  _vars = {}
}

-- Load environment variables from a .env file
function env.load(file_path)
  file_path = file_path or ".env"

  local file = io.open(file_path, "r")
  if not file then
    return nil, "Could not open .env file: " .. file_path
  end

  for line in file:lines() do
    -- Skip empty lines and comments
    if line:match("^%s*[^#]") then
      -- Match key and value, allowing for spaces around equals sign
      local key, value = line:match("^%s*([^=%s]+)%s*=%s*(.+)%s*$")
      if key and value then
        -- Remove quotes if present
        value = value:gsub("^[\"'](.+)[\"']$", "%1")

        -- Store in our internal env table
        env._vars[key] = value

        -- Also try to set as system environment variable (may not work in all Lua environments)
        pcall(function()
          if os.setenv then -- luacheck: ignore 143
            os.setenv(key, value) -- luacheck: ignore 143
          end
        end)
      end
    end
  end

  file:close()
  return env._vars
end

-- Get an environment variable, with fallback
function env.get(name, default)
  -- First check system environment variables
  local value = os.getenv(name)

  -- If not found, check our internal storage from .env file
  if value == nil or value == "" then
    value = env._vars[name]
  end

  -- If still not found, return default
  if value == nil or value == "" then
    return default
  end

  return value
end

return env