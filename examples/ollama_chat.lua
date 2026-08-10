-- Local chat with Ollama; no cloud API key is required.
-- Usage: lua examples/ollama_chat.lua [model] [prompt]

package.path = package.path .. ";../?.lua;./?.lua"

local UGLuaLLM = require "ug-lua-llm"

local model = arg[1] or "llama3.2"
local prompt = arg[2] or "Explain why Lua is useful in two sentences."
local client = UGLuaLLM.new("ollama", {
  model = model,
  base_url = os.getenv("OLLAMA_BASE_URL") or "http://localhost:11434/v1",
})

local response, err = client:chat({ { role = "user", content = prompt } })
if not response then
  io.stderr:write("Ollama request failed: " .. tostring(err or "unknown error") .. "\n")
  io.stderr:write("Check that Ollama is running and run: ollama pull " .. model .. "\n")
  os.exit(1)
end

print(response.text)
