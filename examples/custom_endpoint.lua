-- Connect to any server implementing OpenAI Chat Completions.
-- Required: OPENAI_COMPATIBLE_BASE_URL and OPENAI_COMPATIBLE_MODEL
-- Optional: OPENAI_COMPATIBLE_API_KEY

package.path = package.path .. ";../?.lua;./?.lua"

local UGLuaLLM = require "ug-lua-llm"
local env = require "ug-lua-llm.utils.env"

env.load(".env")

local base_url = env.get("OPENAI_COMPATIBLE_BASE_URL")
local model = env.get("OPENAI_COMPATIBLE_MODEL")
if not base_url or not model then
  io.stderr:write("Set OPENAI_COMPATIBLE_BASE_URL and OPENAI_COMPATIBLE_MODEL.\n")
  os.exit(1)
end

local client = UGLuaLLM.openai_compatible({
  base_url = base_url,
  model = model,
  api_key = env.get("OPENAI_COMPATIBLE_API_KEY"),
  -- Add vendor- or gateway-specific authentication here when Bearer auth is
  -- not appropriate: headers = { ["X-API-Key"] = "..." }
  capabilities = {
    streaming = true,
    tools = true,
    models = true,
  },
})

local response, err = client:chat({
  { role = "user", content = "Reply with the name of the model serving this request." },
})

if not response then
  io.stderr:write("Custom endpoint request failed: " .. tostring(err or "unknown error") .. "\n")
  os.exit(1)
end

print(response.text)
