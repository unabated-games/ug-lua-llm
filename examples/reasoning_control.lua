-- Turn reasoning down where latency matters, and up where it earns its cost.
-- Usage: lua examples/reasoning_control.lua [--provider PROVIDER] [--model MODEL]
--
-- Providers express this four different ways: an effort string, a token budget,
-- an opt-in block, or a different model entirely. `reasoning` is translated to
-- whichever one applies, and a model that cannot comply still answers.

package.path = package.path .. ";../?.lua;./?.lua"

local socket = require "socket"
local ClientFactory = require "examples.helpers.client_factory"

local result = ClientFactory.create_client()
local client = result.client

print("reasoning_control for " .. result.provider .. ": " ..
  tostring(client:capabilities().reasoning_control))

local function ask(label, options)
  local started = socket.gettime()
  local response, err = client:chat({
    { role = "user", content = "In one sentence, what is 17 * 24?" },
  }, options)
  if not response then
    io.stderr:write(label .. " failed: " .. tostring(err) .. "\n")
    return
  end
  local usage = response.usage or {}
  print(string.format(
    "%-22s %5.2fs  reasoning_tokens=%-6s applied=%s",
    label, socket.gettime() - started,
    tostring(usage.reasoning_tokens or "n/a"),
    -- nil when nothing was asked for; false when the model refused the control
    -- and the reply came back without it rather than failing.
    tostring(response.reasoning_applied)))
  print("  " .. tostring(response.text))
end

ask("default", nil)
ask("reasoning = false", { reasoning = false, max_tokens = 300 })
ask("reasoning = \"high\"", { reasoning = "high", max_tokens = 900 })
