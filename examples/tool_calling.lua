-- Focused example of registering, calling, and executing one local tool.
-- Usage: lua examples/tool_calling.lua [--provider PROVIDER] [--model MODEL]

package.path = package.path .. ";../?.lua;./?.lua"

local ClientFactory = require "examples.helpers.client_factory"
local ToolRegistry = require "ug-lua-llm.tools.registry"

local result = ClientFactory.create_client()
local client = result.client

local registered, register_err = ToolRegistry.register("get_weather", {
  description = "Get the current weather for a city",
  parameters = {
    type = "object",
    properties = {
      city = { type = "string", description = "City name" },
    },
    required = { "city" },
  },
  handler = function(args)
    -- Replace this deterministic result with a real weather service.
    return { city = args.city, temperature = 18, unit = "celsius", condition = "sunny" }
  end,
}, true)

if not registered then
  io.stderr:write("Could not register tool: " .. tostring(register_err) .. "\n")
  os.exit(1)
end

local tools, collection_err = ToolRegistry.collection({ "get_weather" })
if not tools then
  io.stderr:write("Could not create tool collection: " .. tostring(collection_err) .. "\n")
  os.exit(1)
end

local messages = {
  { role = "user", content = "What is the weather in London? Use the weather tool." },
}

local response, request_err = client:chat_with_tools(messages, tools)
if not response then
  io.stderr:write("Tool request failed: " .. tostring(request_err or "unknown error") .. "\n")
  os.exit(1)
end

local calls = ToolRegistry.process_tool_calls(client, response)
if #calls == 0 then
  print(response.text or "The model did not request a tool.")
  os.exit(0)
end

for _, call in ipairs(calls) do
  print("Executing tool: " .. call.name)
end

ToolRegistry.process_response(client, response, messages, function(final_response)
  if not final_response or not final_response.text or final_response.text == "" then
    io.stderr:write("The final response contained no text.\n")
    return
  end
  print(final_response.text)
end)
