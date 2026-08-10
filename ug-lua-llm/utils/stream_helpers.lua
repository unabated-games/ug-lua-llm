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

local StreamHelpers = {}

-- Create a standardized content streaming callback
-- This automatically handles different provider response formats and returns
-- just the content text in a consistent way
function StreamHelpers.content_callback(user_callback)
  return function(delta, full)
    local content = nil

    -- Handle OpenAI/Groq/OpenRouter format - text completions
    if delta.choices and delta.choices[1] and delta.choices[1].text then
      content = delta.choices[1].text

    -- Handle OpenAI/Groq/OpenRouter format - chat completions
    elseif delta.choices and delta.choices[1] and delta.choices[1].delta and delta.choices[1].delta.content then
      local delta_content = delta.choices[1].delta.content
      -- Handle any content type, including light userdata
      if type(delta_content) == "string" then
        content = delta_content
      else
        content = tostring(delta_content or "")
        -- Skip "userdata: (nil)" values
        if content == "userdata: (nil)" then
          content = nil
        end
      end

    -- Handle Claude format
    elseif delta.content then
      local delta_content = delta.content
      -- Handle any content type, including light userdata
      if type(delta_content) == "string" then
        content = delta_content
      else
        content = tostring(delta_content or "")
        -- Skip "userdata: (nil)" values
        if content == "userdata: (nil)" then
          content = nil
        end
      end
    end

    -- Pass content to callback even if it's not a string, we've converted it above
    if content then
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
    -- Handle OpenAI/Groq/OpenRouter format - tool calls
    if delta.choices and delta.choices[1] and delta.choices[1].delta and delta.choices[1].delta.tool_calls then
      if not tool_call_detected then
        tool_call_detected = true
        if on_tool_call_detect then
          on_tool_call_detect()
        end
      end
    -- Handle Claude format - tool calls
    elseif delta.tool_call then
      if not tool_call_detected then
        tool_call_detected = true
        if on_tool_call_detect then
          on_tool_call_detect()
        end
      end
    -- Handle OpenAI/Groq/OpenRouter format - content
    elseif delta.choices and delta.choices[1] and delta.choices[1].delta and delta.choices[1].delta.content then
      if on_content then
        local content = delta.choices[1].delta.content
        -- Handle any content type, including light userdata
        if type(content) ~= "string" then
          content = tostring(content or "")
          -- Skip "userdata: (nil)" values
          if content == "userdata: (nil)" then
            return -- Skip this content
          end
        end
        on_content(content)
      end
    -- Handle Claude format - content
    elseif delta.content then
      if on_content then
        local content = delta.content
        -- Handle any content type, including light userdata
        if type(content) ~= "string" then
          content = tostring(content or "")
          -- Skip "userdata: (nil)" values
          if content == "userdata: (nil)" then
            return -- Skip this content
          end
        end
        on_content(content)
      end
    end
  end
end

-- Safe output writer that handles different data types
function StreamHelpers.safe_writer(text)
  if type(text) == "string" then
    io.write(text)
    io.flush()
  else
    -- Convert non-string values to strings, but skip "userdata: (nil)"
    local safe_text = tostring(text or "")
    if safe_text ~= "userdata: (nil)" then
      io.write(safe_text)
      io.flush()
    end
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
