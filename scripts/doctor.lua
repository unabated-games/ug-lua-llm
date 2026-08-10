local Doctor = require "ug-lua-llm.doctor"

local options = {}
local json_output = false
local i = 1
while i <= #arg do
  local name = arg[i]
  if name == "--json" then
    json_output = true
  elseif name == "--env" or name == "--provider" or name == "--endpoint" or
      name == "--model" or name == "--api-key-env" then
    local value = arg[i + 1]
    if not value then error(name .. " requires a value") end
    local key = name:sub(3):gsub("%-", "_")
    options[key] = value
    i = i + 1
  elseif name == "--help" then
    print([[Usage: lua scripts/doctor.lua [options]
  --env FILE          Load and validate an environment file
  --provider NAME     Check the conventional credential for a provider
  --api-key-env NAME  Check a custom credential variable
  --endpoint URL      Opt in to an OpenAI-compatible /models connectivity check
  --model NAME        Model name used to construct the endpoint client
  --json              Print machine-readable output]])
    os.exit(0)
  else
    error("Unknown option: " .. tostring(name))
  end
  i = i + 1
end

if options.api_key_env then
  local env = require "ug-lua-llm.utils.env"
  if options.env_file then env.load(options.env_file) end
  options.api_key = env.get(options.api_key_env)
end

local report = Doctor.run(options)
if json_output then
  print(require("ug-lua-llm.utils.json").encode(report))
else
  Doctor.print(report)
end
os.exit(report.ok and 0 or 1)
