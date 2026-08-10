-- Stream a response from a local Ollama model.
-- Usage: lua examples/ollama_streaming.lua [model] [prompt]

package.path = package.path .. ";../?.lua;./?.lua"

local UGLuaLLM = require "ug-lua-llm"
local StreamHelpers = require "ug-lua-llm.utils.stream_helpers"

local model = arg[1] or "llama3.2"
local prompt = arg[2] or "Write a four-line poem about local inference."
local client = UGLuaLLM.new("ollama", {
  model = model,
  base_url = os.getenv("OLLAMA_BASE_URL") or "http://localhost:11434/v1",
})

local response, err = client:stream_chat(
  { { role = "user", content = prompt } },
  StreamHelpers.content_callback(function(content)
    io.write(content)
    io.flush()
  end)
)

if not response then
  io.stderr:write("\nOllama request failed: " .. tostring(err or "unknown error") .. "\n")
  io.stderr:write("Check that Ollama is running and run: ollama pull " .. model .. "\n")
  os.exit(1)
end

io.write("\n")
