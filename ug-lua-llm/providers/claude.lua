local Provider = require 'ug-lua-llm.core.provider'
local Tool = require 'ug-lua-llm.tools.tool'
local Response = require 'ug-lua-llm.core.response'
local Options = require 'ug-lua-llm.utils.options'

local ClaudeProvider = {}
setmetatable(ClaudeProvider, { __index = Provider })

-- Extract text string from Claude content (handles both string and content blocks table)
local function extract_content_text(content)
  if type(content) == "string" then
    return content
  elseif type(content) == "table" then
    local parts = {}
    for _, block in ipairs(content) do
      if block.type == "text" and block.text then
        parts[#parts + 1] = block.text
      end
    end
    return table.concat(parts)
  end
  return ""
end

-- Create a new Claude provider
function ClaudeProvider.new(config)
  config = config or {}

  -- Set default configuration for Claude
  config.base_url = config.base_url or "https://api.anthropic.com/v1"
  config.provider_name = "claude"

  if not config.api_key then
    error("Claude API key is required")
  end

  -- Set default model if not provided
  config.model = config.model or "claude-sonnet-4-6"

  -- Call parent constructor
  local provider = Provider.new(config)

  -- Add Claude-specific headers
  provider.http.headers["x-api-key"] = config.api_key
  provider.http.headers["anthropic-version"] = "2023-06-01"

  setmetatable(provider, { __index = ClaudeProvider })
  return provider
end

-- List available models (Claude doesn't have an equivalent endpoint, so we hardcode models)
function ClaudeProvider:list_models()
  return {
    { id = "claude-opus-4-6", name = "Claude Opus 4.6" },
    { id = "claude-sonnet-4-6", name = "Claude Sonnet 4.6" },
    { id = "claude-haiku-4-5-20251001", name = "Claude Haiku 4.5" },
    { id = "claude-opus-4-5", name = "Claude Opus 4.5" },
    { id = "claude-sonnet-4-5", name = "Claude Sonnet 4.5" },
    { id = "claude-sonnet-4-20250514", name = "Claude Sonnet 4" },
    { id = "claude-opus-4-20250514", name = "Claude Opus 4" },
  }
end

-- Complete a prompt (Claude uses messages API for everything, so we translate)
function ClaudeProvider:complete(prompt, options)
  options = options or {}

  -- Convert completion to chat format
  local messages = {
    { role = "user", content = prompt }
  }

  return self:chat(messages, options)
end

-- Build a Claude payload with optional thinking support
function ClaudeProvider:_build_payload(messages, options)
  local claude_messages, system = self:_format_messages(messages)
  local max_tokens = options.max_tokens or self.config.max_tokens

  local payload = {
    model = options.model or self.config.model,
    messages = claude_messages,
    max_tokens = max_tokens,
  }

  if system then payload.system = system end

  -- Extended thinking: when enabled, temperature must be 1 (or omitted)
  if options.thinking then
    local budget = options.thinking_budget or 10000
    if max_tokens <= budget then
      if options.max_tokens ~= nil then
        return nil, "max_tokens must be greater than thinking_budget"
      end
      -- Keep the convenient default usable when thinking is enabled without an
      -- explicit output limit.
      payload.max_tokens = budget + 1024
    end
    payload.thinking = {
      type = "enabled",
      budget_tokens = budget,
    }
    -- temperature must not be set when thinking is enabled
  else
    payload.temperature = options.temperature or self.config.temperature
  end

  return Options.payload(payload, options)
end

-- Send a chat message
function ClaudeProvider:chat(messages, options)
  options = options or {}
  local url = self.config.base_url .. "/messages"

  local payload, payload_err = self:_build_payload(messages, options)
  if not payload then
    return nil, self:validation_error(payload_err, "invalid_options")
  end

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat request failed")
  end

  return Response.normalize("claude", response.body)
end

-- Process a chat message with tools
-- Claude spells tool choice as an object with a type, not OpenAI's bare string,
-- and nothing translated it -- so `tool_choice` never reached the payload at
-- all. A caller forcing a tool got a free choice, and one asking for "none" to
-- forbid tool use had tools called anyway with nothing to say otherwise.
local TOOL_CHOICE_TYPE = {
  auto = "auto",
  required = "any",
  any = "any",
  none = "none",
}

local function tool_choice(choice)
  if choice == nil then return nil end

  if type(choice) == "string" then
    local kind = TOOL_CHOICE_TYPE[choice:lower()]
    return kind and { type = kind } or nil
  end

  if type(choice) == "table" then
    -- Already Claude-shaped, including the forced-tool form used to carry a
    -- JSON schema, so it travels untouched.
    if choice.type and (choice.type == "tool" or TOOL_CHOICE_TYPE[choice.type]) then
      return choice
    end
    -- OpenAI's { type = "function", function = { name = ... } }.
    local named = choice.name or (type(choice["function"]) == "table" and
      choice["function"].name)
    if named then return { type = "tool", name = named } end
  end

  return nil
end

function ClaudeProvider:chat_with_tools(messages, tools, options)
  options = options or {}
  local url = self.config.base_url .. "/messages"

  local payload, payload_err = self:_build_payload(messages, options)
  if not payload then
    return nil, self:validation_error(payload_err, "invalid_options")
  end
  payload.tools = Tool.to_provider_format(tools, "claude")

  local choice = tool_choice(options.tool_choice)
  if choice and payload.tool_choice == nil then payload.tool_choice = choice end

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat with tools request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat with tools request failed")
  end

  return Response.normalize("claude", response.body)
end

-- Stream a text completion
function ClaudeProvider:stream_complete(prompt, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  -- Convert completion to chat format
  local messages = {
    { role = "user", content = prompt }
  }

  -- Use stream_chat internally
  return self:stream_chat(messages, function(delta, full)
    -- Convert chat format to completion format for callback
    if delta and delta.content then
      local text_delta = {
        choices = {
          {
            text = delta.content,
            index = 0,
            finish_reason = delta.stop_reason
          }
        },
        delta = true
      }

      callback(text_delta, full)
    end
  end, options)
end

-- Stream a chat response
function ClaudeProvider:stream_chat(messages, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  local url = self.config.base_url .. "/messages"

  local payload, payload_err = self:_build_payload(messages, options)
  if not payload then
    return nil, self:validation_error(payload_err, "invalid_options")
  end
  payload.stream = true

  -- Track the accumulated response
  local accumulated_content = ""
  local current_response = {
    id = nil,
    model = options.model or self.config.model,
    type = "message",
    role = "assistant",
    content = "",
    thinking = nil,
    stop_reason = nil
  }

  -- Import the streaming module
  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  -- Process streaming events
  local success, _err = HttpStreaming.stream_claude(url, self.http.headers, payload, function(chunk)
    if chunk then
      -- Extract the delta content
      local delta_content = ""
      if chunk.delta and chunk.delta.text then
        delta_content = chunk.delta.text
        accumulated_content = accumulated_content .. delta_content
        current_response.content = accumulated_content
      end

      -- Check for stop reason
      local stop_reason = chunk.stop_reason or (chunk.delta and chunk.delta.stop_reason)
      if stop_reason then
        current_response.stop_reason = stop_reason
      end

      -- Create a delta response for the callback
      local delta_response = {
        content = delta_content,
        stop_reason = stop_reason,
        delta = true
      }

      -- Call the callback with both delta and accumulated response
      callback(delta_response, current_response)
    end
  end, "claude", options)

  if not success then
    -- Fall back to non-streaming if real streaming fails
    local response, fallback_err, details = self:chat(messages, options)
    if fallback_err or not response then
      return nil, fallback_err, details
    end

    -- Convert Claude response to the format we're using
    local content_text = extract_content_text(response.content)
    local formatted_response = {
      id = response.id,
      model = response.model,
      type = "message",
      role = "assistant",
      content = content_text,
      stop_reason = response.stop_reason
    }

    -- Notify the caller about the full response in one go
    callback({
      content = content_text,
      stop_reason = formatted_response.stop_reason,
      delta = true
    }, formatted_response)

    return formatted_response
  end

  -- Normalized like any other reply. The accumulator builds Anthropic's own
  -- shape, so returning it directly gave the caller `stop_reason` instead of
  -- `finish_reason`, no `provider` -- which breaks the documented
  -- `Tool.parse_tool_calls(response)` -- and a nil `text` against a contract
  -- that says it is always a string.
  return Response.normalize("claude", current_response)
end

-- Stream a chat response with tools
function ClaudeProvider:stream_chat_with_tools(messages, tools, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  local url = self.config.base_url .. "/messages"

  local payload, payload_err = self:_build_payload(messages, options)
  if not payload then
    return nil, self:validation_error(payload_err, "invalid_options")
  end
  payload.tools = Tool.to_provider_format(tools, "claude")
  payload.stream = true

  -- Track the accumulated response and tool calls
  local accumulated_content = ""
  local tool_json = {}
  local tools_by_index = {}
  local current_response = {
    id = nil,
    model = options.model or self.config.model,
    type = "message",
    role = "assistant",
    content = "",
    tool_calls = {},
    stop_reason = nil
  }

  -- Import the streaming module
  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  -- Process streaming events
  local success, _err = HttpStreaming.stream_claude(url, self.http.headers, payload, function(chunk)
    if chunk then
      -- Check for tool calls (Claude streams them differently from content)
      if chunk.type == "content_block_start" and chunk.content_block and
         chunk.content_block.type == "tool_use" then
        local block = chunk.content_block
        local tool_call = {
          id = block.id or "",
          name = block.name or "",
          input = block.input or {}
        }
        local index = chunk.index or #current_response.tool_calls
        tools_by_index[index] = tool_call
        tool_json[index] = ""
        table.insert(current_response.tool_calls, tool_call)
        callback({
          tool_call = tool_call,
          delta = true
        }, current_response)
      elseif chunk.delta and chunk.delta.type == "input_json_delta" then
        local index = chunk.index or 0
        tool_json[index] = (tool_json[index] or "") .. (chunk.delta.partial_json or "")
        local tool_call = tools_by_index[index]
        if tool_call and tool_json[index] ~= "" then
          local ok, input = pcall(
            require("ug-lua-llm.utils.json").decode, tool_json[index])
          if ok then tool_call.input = input end
          callback({ tool_call = tool_call, partial_json = chunk.delta.partial_json,
            delta = true }, current_response)
        end
      -- Handle regular content deltas
      elseif chunk.delta and chunk.delta.text then
        local delta_content = chunk.delta.text
        accumulated_content = accumulated_content .. delta_content
        current_response.content = accumulated_content

        -- Create a delta response for the callback
        local delta_response = {
          content = delta_content,
          stop_reason = chunk.stop_reason,
          delta = true
        }

        -- Call the callback with both delta and accumulated response
        callback(delta_response, current_response)
      end

      -- Check for stop reason
      local stop_reason = chunk.stop_reason or (chunk.delta and chunk.delta.stop_reason)
      if stop_reason then
        current_response.stop_reason = stop_reason
      end
    end
  end, "claude", options)

  if not success then
    -- Fall back to non-streaming if real streaming fails
    local response, fallback_err, details = self:chat_with_tools(messages, tools, options)
    if fallback_err or not response then
      return nil, fallback_err, details
    end

    -- Create a simulated stream callback
    if response.tool_calls and #response.tool_calls > 0 then
      -- Call the callback with the tool call
      callback({
        tool_call = response.tool_calls[1],
        delta = true
      }, response)
    else
      -- Call the callback with the content
      local content_text = extract_content_text(response.content)
      callback({
        content = content_text,
        stop_reason = response.stop_reason,
        delta = true
      }, response)
    end

    return response
  end

  -- Rebuild Anthropic's own content blocks before normalizing. The accumulator
  -- keeps text as a string and tool calls beside it, but a real reply is one
  -- array of blocks -- which is the shape the normalizer reads tool calls from,
  -- and the shape a tool follow-up echoes back. Leaving it as a string dropped
  -- the tool calls on normalization and would have sent a string where the
  -- follow-up expects blocks.
  local blocks = {}
  if type(current_response.content) == "string" and current_response.content ~= "" then
    blocks[#blocks + 1] = { type = "text", text = current_response.content }
  elseif type(current_response.content) == "table" then
    for _, block in ipairs(current_response.content) do
      blocks[#blocks + 1] = block
    end
  end
  for _, call in ipairs(current_response.tool_calls or {}) do
    blocks[#blocks + 1] = {
      type = "tool_use",
      id = call.id,
      name = call.name,
      input = call.input or {},
    }
  end
  current_response.content = blocks

  -- Normalized for the same reason as the streaming chat path: the
  -- accumulator holds Anthropic's own shape, not the caller's contract.
  return Response.normalize("claude", current_response)
end

-- Helper method to convert generic messages to Claude format
function ClaudeProvider:_format_messages(messages)
  local claude_messages = {}
  local system_parts = {}

  for _, message in ipairs(messages) do
    local role = message.role
    if role == "system" then
      system_parts[#system_parts + 1] = message.content
    elseif role == "user" or role == "assistant" then
      table.insert(claude_messages, { role = role, content = message.content })
    else
      -- Treat anything else as user message
      table.insert(claude_messages, { role = "user", content = message.content })
    end
  end

  local system = #system_parts > 0 and table.concat(system_parts, "\n\n") or nil
  return claude_messages, system
end

return ClaudeProvider
