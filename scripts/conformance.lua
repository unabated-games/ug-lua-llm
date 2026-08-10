local env = require "ug-lua-llm.utils.env"
env.load(".env")

local UGLuaLLM = require "ug-lua-llm"

local base_url = env.get("LLM_BASE_URL")
local model = env.get("LLM_MODEL")
if not base_url or not model then
  io.stderr:write("Set LLM_BASE_URL and LLM_MODEL (optionally LLM_API_KEY).\n")
  os.exit(2)
end

local report = UGLuaLLM.Conformance.run({
  base_url = base_url,
  model = model,
  api_key = env.get("LLM_API_KEY"),
})

for _, check in ipairs(report.checks) do
  io.write(string.format("%-12s %s", check.name, check.ok and "PASS" or "FAIL"))
  if check.error then io.write(" - " .. tostring(check.error)) end
  io.write("\n")
end
os.exit(report.ok and 0 or 1)
