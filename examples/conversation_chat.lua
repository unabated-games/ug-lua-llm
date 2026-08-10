-- Example of multi-turn conversation with an LLM
-- Usage: lua conversation_chat.lua [--provider openai|claude|groq|grok|openrouter] [--model modelname] [--temperature 0.7]

package.path = package.path .. ";../?.lua;./?.lua"

local StreamHelpers = require "ug-lua-llm.utils.stream_helpers"
local ClientFactory = require "examples.helpers.client_factory"

-- Create a client using the ClientFactory
local result = ClientFactory.create_client()
local client = result.client
local provider_name = result.provider

-- Initialize message history with system prompt
local message_history = {
  { role = "system", content = "You are a helpful assistant. Keep your answers short and concise." }
}

-- Print welcome message
print("\n--- Interactive Chat with " .. provider_name .. " ---")
print("Type 'exit' or 'quit' to end the conversation")
print("Type 'history' to view the conversation history")
print("Type 'clear' to clear the conversation history\n")

-- Main conversation loop
while true do
  -- Get user input
  io.write("\nYou: ")
  local user_input = io.read()
  
  -- Check for exit command
  if user_input == "exit" or user_input == "quit" then
    print("\nGoodbye!")
    break
  end
  
  -- Check for history command
  if user_input == "history" then
    print("\n--- Conversation History ---")
    for i, msg in ipairs(message_history) do
      if msg.role == "system" then
        print("[System] " .. msg.content)
      elseif msg.role == "user" then
        print("[You] " .. msg.content)
      elseif msg.role == "assistant" then
        print("[Assistant] " .. msg.content)
      end
    end
    print("---------------------------\n")
    goto continue
  end
  
  -- Check for clear history command
  if user_input == "clear" then
    message_history = {
      { role = "system", content = "You are a helpful assistant. Keep your answers short and concise." }
    }
    print("\nConversation history cleared.\n")
    goto continue
  end
  
  -- Add user message to history
  table.insert(message_history, { role = "user", content = user_input })
  
  -- Stream the assistant's response
  io.write("\nAssistant: ")
  
  -- Variable to accumulate the full response
  local full_response = ""
  
  -- Make the streaming API call
  local response, stream_err = client:stream_chat(message_history,
    StreamHelpers.content_callback(function(content)
      -- This callback only receives the extracted content regardless of provider format
      io.write(content)
      io.flush()
      full_response = full_response .. content
    end)
  )

  io.write("\n")

  if not response then
    io.stderr:write("Request failed: " .. tostring(stream_err or "unknown error") .. "\n")
    -- Let the user retry without leaving an unmatched user message in history.
    table.remove(message_history)
  elseif full_response == "" then
    io.stderr:write("The provider returned successfully but contained no text.\n")
    table.remove(message_history)
  else
    -- Add the assistant's response to history only after a successful request.
    table.insert(message_history, { role = "assistant", content = full_response })
  end
  
  ::continue::
end
