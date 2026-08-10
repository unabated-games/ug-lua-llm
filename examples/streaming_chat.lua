-- Simplified example for streaming chat responses
-- Usage: lua streaming_chat.lua "Your prompt here"
--        lua streaming_chat.lua --provider claude "Tell me a joke"
--        lua streaming_chat.lua --help

package.path = package.path .. ";../?.lua;./?.lua"

local StreamHelpers = require "ug-lua-llm.utils.stream_helpers"
local ClientFactory = require "examples.helpers.client_factory"

-- Create a client using the ClientFactory
local result = ClientFactory.create_client()
local client = result.client
local provider_name = result.provider

-- Extract prompt from remaining args after removing options
local prompt = "Tell me a short joke"

-- Find any non-option argument that's not immediately after an option that takes a value
local i = 1
while i <= #arg do
    if arg[i]:match("^%-") then  
        -- Skip this option and its value if it has one
        if arg[i]:match("^%-%-provider$") or arg[i]:match("^%-p$") or 
           arg[i]:match("^%-%-model$") or arg[i]:match("^%-m$") or
           arg[i]:match("^%-%-temperature$") or arg[i]:match("^%-t$") then
            i = i + 1  -- Skip the option's value
        end
    else
        -- This is not an option, use it as the prompt
        prompt = arg[i]
        break
    end
    i = i + 1
end

-- Message to send
local messages = {
  { role = "user", content = prompt }
}

print("\n--- Streaming " .. provider_name .. " response to: " .. prompt .. " ---\n")

-- Stream the response, printing each token as it arrives
local response, err = client:stream_chat(messages,
  -- Use the standardized content callback for consistent handling across providers
  StreamHelpers.content_callback(function(content)
    io.write(content)
    io.flush() -- Force immediate display after each token
  end)
)

if not response then
  io.stderr:write("Request failed: " .. tostring(err or "unknown error") .. "\n")
  os.exit(1)
end

print("\n\n--- End of response ---")
