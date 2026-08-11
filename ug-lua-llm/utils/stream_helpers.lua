-- Helper utilities for streaming across different providers
--
-- This module provides utilities for handling streaming responses from different LLM providers
-- in a consistent way, abstracting away the differences in response formats.
--
-- Usage example for simple streaming content:
--
-- local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
-- client:stream_chat(messages,
--   StreamHelpers.content_callback(function(content)
--     io.write(content)
--     io.flush()
--   end)
-- )
--
-- Usage example for streaming with tool call detection:
--
-- client:stream_chat_with_tools(messages, tools,
--   StreamHelpers.tool_call_detector(
--     -- Tool call detection callback
--     function()
--       print("[Tool call detected]")
--     end,
--     -- Content callback
--     function(content)
--       io.write(content)
--       io.flush()
--     end
--   )
-- )

local JSON = require "ug-lua-llm.utils.json"

local StreamHelpers = {}

-- Decoded JSON null is truthy, so a provider sending {"content":null} would
-- otherwise reach the callback as the backend's sentinel. Earlier revisions
-- filtered it by comparing tostring(value) against "userdata: (nil)", which
-- never matched: lua-cjson renders its sentinel as "userdata: 0x0" on many
-- platforms and dkjson's is a table. Compare identity instead.
local function text_of(value)
  return JSON.string_value(value)
end

-- Create a standardized content streaming callback
-- This automatically handles different provider response formats and returns
-- just the content text in a consistent way
function StreamHelpers.content_callback(user_callback)
  return function(delta, full)
    local choice = delta.choices and JSON.value(delta.choices[1])
    local content =
      (choice and text_of(choice.text)) or
      (choice and JSON.value(choice.delta) and text_of(choice.delta.content)) or
      text_of(delta.content)

    if content and content ~= "" then
      user_callback(content, full)
    end
  end
end

-- Create a standardized tool call detection callback
-- This automatically handles different provider response formats and returns
-- information about detected tool calls
function StreamHelpers.tool_call_detector(on_tool_call_detect, on_content)
  local tool_call_detected = false

  return function(delta, full)
    local choice = delta.choices and JSON.value(delta.choices[1])
    local inner = choice and JSON.value(choice.delta)
    local tool_calls = (inner and JSON.value(inner.tool_calls)) or
      JSON.value(delta.tool_call)

    if tool_calls then
      if not tool_call_detected then
        tool_call_detected = true
        if on_tool_call_detect then
          on_tool_call_detect()
        end
      end
      return
    end

    local content = (inner and text_of(inner.content)) or text_of(delta.content)
    if content and content ~= "" and on_content then
      on_content(content, full)
    end
  end
end

-- Safe output writer that handles different data types
function StreamHelpers.safe_writer(text)
  local safe_text = text_of(text)
  if safe_text == nil and JSON.value(text) ~= nil then
    safe_text = tostring(text)
  end
  if safe_text and safe_text ~= "" then
    io.write(safe_text)
    io.flush()
  end
end

-- Determine provider type from client object
function StreamHelpers.get_provider_type(client)
  if client.provider.config.provider_name then
    return client.provider.config.provider_name:lower()
  end
  -- Check provider type by URL pattern
  local base_url = client.provider.config.base_url

  if client.provider.http.headers["x-api-key"] then
    return "claude"
  elseif base_url:find("groq.com") then
    return "groq"
  elseif base_url:find("x.ai") then
    return "grok"
  elseif base_url:find("googleapis.com") then
    return "gemini"
  elseif base_url:find("openrouter.ai") then
    return "openrouter"
  else
    return "openai" -- Default to OpenAI
  end
end

return StreamHelpers
