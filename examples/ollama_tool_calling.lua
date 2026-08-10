-- Execute a local tool requested by an Ollama model.
-- Usage: lua examples/ollama_tool_calling.lua [tool-capable-model]

package.path = package.path .. ";../?.lua;./?.lua"

local UGLuaLLM = require "ug-lua-llm"
local ToolRegistry = require "ug-lua-llm.tools.registry"

local model = arg[1] or "llama3.2"
local client = UGLuaLLM.new("ollama", {
  model = model,
  base_url = os.getenv("OLLAMA_BASE_URL") or "http://localhost:11434/v1",
})

local registered, register_err = ToolRegistry.register("multiply", {
  description = "Multiply two numbers",
  parameters = {
    type = "object",
    properties = {
      a = { type = "number" },
      b = { type = "number" },
    },
    required = { "a", "b" },
  },
  handler = function(args) return { product = args.a * args.b } end,
}, true)

if not registered then error(register_err) end
local tools = assert(ToolRegistry.collection({ "multiply" }))
local messages = {
  { role = "user", content = "Use the multiply tool to calculate 23 times 47." },
}

local response, err = client:chat_with_tools(messages, tools)
if not response then
  io.stderr:write("Ollama tool request failed: " .. tostring(err or "unknown error") .. "\n")
  os.exit(1)
end

local calls = ToolRegistry.process_tool_calls(client, response)
if #calls == 0 then
  io.stderr:write("The model did not request the tool; try another tool-capable model.\n")
  os.exit(1)
end

ToolRegistry.process_response(client, response, messages, function(final_response)
  if not final_response then
    io.stderr:write("Ollama returned no final response.\n")
    return
  end
  print(final_response.text)
end)
