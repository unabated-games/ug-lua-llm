-- Minimal non-streaming chat example.
-- Usage: lua examples/basic_chat.lua [--provider PROVIDER] [--model MODEL]

package.path = package.path .. ";../?.lua;./?.lua"

local ClientFactory = require "examples.helpers.client_factory"

local result = ClientFactory.create_client()
local response, err = result.client:chat({
  { role = "user", content = "Name one interesting fact about Lua." },
})

if not response then
  io.stderr:write("Request failed: " .. tostring(err or "unknown error") .. "\n")
  os.exit(1)
end

if not response.text or response.text == "" then
  io.stderr:write("The provider returned successfully but contained no text.\n")
  os.exit(1)
end

print(response.text)
