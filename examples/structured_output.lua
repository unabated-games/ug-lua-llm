-- Ask a model for a specific shape and get a decoded Lua table back.
-- Usage: lua examples/structured_output.lua [--provider PROVIDER] [--model MODEL]
--
-- One schema works across every provider. The library carries it in whatever
-- shape the service takes: a flattened text.format on the OpenAI Responses API,
-- response_format.json_schema on Chat Completions services, responseSchema on
-- Gemini, and a forced tool call on Claude, which has no response-format field.

package.path = package.path .. ";../?.lua;./?.lua"

local ClientFactory = require "examples.helpers.client_factory"

local result = ClientFactory.create_client()
local client = result.client

local schema = {
  name = "npc_reply",
  schema = {
    type = "object",
    properties = {
      line = { type = "string", description = "What the character says" },
      mood = { type = "string", enum = { "calm", "wary", "angry" } },
    },
    required = { "line", "mood" },
    additionalProperties = false,
  },
}

local response, err = client:chat({
  { role = "system", content = "You voice a suspicious harbour guard." },
  { role = "user", content = "I ask the guard about the missing shipment." },
}, { json_schema = schema, max_tokens = 300 })

if not response then
  io.stderr:write("Request failed: " .. tostring(err) .. "\n")
  os.exit(1)
end

-- A model that cannot honour the schema still answers, so check before
-- trusting the shape rather than assuming the request implies compliance.
if response.structured_applied and type(response.parsed) == "table" then
  print("line: " .. tostring(response.parsed.line))
  print("mood: " .. tostring(response.parsed.mood))
else
  print("The provider did not enforce the schema. Raw reply:")
  print(response.text)
end
