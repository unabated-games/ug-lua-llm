local Provider = require 'ug-lua-llm.core.provider'
local Tool = require 'ug-lua-llm.tools.tool'
local Options = require 'ug-lua-llm.utils.options'
local Response = require 'ug-lua-llm.core.response'
local Reasoning = require 'ug-lua-llm.core.reasoning'
local ChatStream = require 'ug-lua-llm.utils.openai_chat_stream'
local Pagination = require 'ug-lua-llm.utils.pagination'

local OpenAIProvider = {}
setmetatable(OpenAIProvider, { __index = Provider })

-- Create a new OpenAI provider
function OpenAIProvider.new(config)
  config = config or {}

  -- Set default configuration for OpenAI
  config.base_url = config.base_url or "https://api.openai.com/v1"
  config.provider_name = "openai"

  if not config.api_key then
    error("OpenAI API key is required")
  end

  -- Set default model if not provided
  config.model = config.model or "gpt-5.6-terra"
  config.api = config.api or "responses"

  -- Call parent constructor
  local provider = Provider.new(config)

  -- Add OpenAI-specific headers
  provider.http.headers["Authorization"] = "Bearer " .. config.api_key

  setmetatable(provider, { __index = OpenAIProvider })
  return provider
end

local function responses_tools(tools)
  local result = {}
  for _, tool in ipairs(tools or {}) do
    result[#result + 1] = {
      type = "function",
      name = tool.name,
      description = tool.description,
      parameters = tool.parameters or { type = "object", properties = {} },
      strict = tool.strict,
    }
  end
  return result
end

local function normalize_responses_body(body)
  local content_parts, tool_calls = {}, {}
  for _, item in ipairs((body and body.output) or {}) do
    if item.type == "message" then
      for _, part in ipairs(item.content or {}) do
        if part.type == "output_text" and part.text then
          content_parts[#content_parts + 1] = part.text
        end
      end
    elseif item.type == "function_call" then
      tool_calls[#tool_calls + 1] = {
        id = item.call_id or item.id,
        type = "function",
        ["function"] = { name = item.name, arguments = item.arguments or "{}" },
      }
    end
  end
  local text = table.concat(content_parts)
  local finish_reason = #tool_calls > 0 and "tool_calls" or
    (body and body.status == "completed" and "stop" or body and body.status)
  return {
    id = body and body.id,
    object = body and body.object or "response",
    model = body and body.model,
    content = text,
    output_text = text,
    tool_calls = #tool_calls > 0 and tool_calls or nil,
    finish_reason = finish_reason,
    usage = body and body.usage,
    output = body and body.output,
    choices = {{
      index = 0,
      message = { role = "assistant", content = text,
        tool_calls = #tool_calls > 0 and tool_calls or nil },
      finish_reason = finish_reason,
    }},
    raw = body,
  }
end

function OpenAIProvider:_responses_payload(messages, options, tools)
  options = options or {}
  local payload = Options.payload({
    model = options.model or self.config.model,
    input = messages,
    max_output_tokens = options.max_tokens or self.config.max_tokens,
  }, options)
  if options.reasoning ~= nil or options.reasoning_effort or options.reasoning_mode then
    -- `reasoning` means the same thing here as it does on chat. The Responses
    -- API wants an object, so a normalized level -- the string or boolean every
    -- other call path takes -- has to be translated rather than passed through
    -- as "Invalid type for 'reasoning': expected an object, but got a string".
    -- A caller who already knows the provider's own shape still sends a table.
    local reasoning = options.reasoning
    if type(reasoning) == "table" then
      payload.reasoning = reasoning
    else
      payload.reasoning = {}
      local level = Reasoning.level(reasoning)
      if level then payload.reasoning.effort = level end
    end
    if options.reasoning_effort then payload.reasoning.effort = options.reasoning_effort end
    if options.reasoning_mode then payload.reasoning.mode = options.reasoning_mode end
  end
  if options.text then payload.text = options.text end
  if options.response_format then
    payload.text = payload.text or {}
    payload.text.format = options.response_format
  end
  if tools then
    payload.tools = responses_tools(tools)
    if options.tool_choice then payload.tool_choice = options.tool_choice end
  end
  return Options.payload(payload, options)
end

function OpenAIProvider:response(input, options)
  options = options or {}
  local payload = self:_responses_payload(input, options, options.tools)
  local response, err, details = self.http:post(self.config.base_url .. "/responses", payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Response request failed")
  end
  if response.status ~= 200 then
    return nil, self:format_error(response, "Response request failed")
  end
  return Response.normalize("openai", normalize_responses_body(response.body))
end

-- List available models
function OpenAIProvider:list_models(options)
  return Pagination.openai(function(url)
    local response, err, details = self.http:get(url)
    if err or not response then
      return nil, self:transport_error(err, details, "Failed to fetch models")
    end
    if response.status ~= 200 then
      return nil, self:format_error(response, "Failed to fetch models")
    end
    return response
  end, self.config.base_url .. "/models", options)
end

-- List of models that only support the chat endpoint
local CHAT_ONLY_MODELS = {
  ["gpt-4"] = true,
  ["gpt-4-turbo"] = true,
  ["gpt-4o"] = true,
  ["gpt-4o-mini"] = true,
  ["gpt-3.5-turbo"] = true
}

-- Check if a model only supports chat API
local function is_chat_only_model(model)
  -- Check for exact matches
  if CHAT_ONLY_MODELS[model] then
    return true
  end

  -- Check for prefix matches (e.g., gpt-4-0125-preview)
  for prefix, _ in pairs(CHAT_ONLY_MODELS) do
    if model:find("^" .. prefix .. "%-") then
      return true
    end
  end

  return false
end

-- Complete a prompt
function OpenAIProvider:complete(prompt, options)
  options = options or {}
  if (options.api or self.config.api) == "responses" then
    return self:response(prompt, options)
  end
  local model = options.model or self.config.model

  -- Check if the model only supports the chat completion API
  if is_chat_only_model(model) then
    -- Convert prompt to chat format and use chat endpoint instead
    local chat_messages = {
      { role = "user", content = prompt }
    }

    local response, err, details = self:chat(chat_messages, options)
    if err or not response then
      return nil, err, details
    end

    -- Format the response to match the completion API format
    if response.choices and response.choices[1] and response.choices[1].message then
      response.choices[1].text = response.choices[1].message.content
    end

    return response
  end

  -- For models that support the completion API (e.g., text-davinci-003)
  local url = self.config.base_url .. "/completions"

  local payload = {
    model = model,
    prompt = prompt,
    max_tokens = options.max_tokens or self.config.max_tokens,
    temperature = options.temperature or self.config.temperature,
  }

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Completion request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Completion request failed")
  end

  return Response.normalize("openai", response.body)
end

-- Build a chat payload, handling o-series reasoning models
function OpenAIProvider:_build_chat_payload(messages, options)
  local model = options.model or self.config.model

  local payload = {
    model = model,
    messages = messages,
  }

  -- OpenAI replaced max_tokens with max_completion_tokens on Chat Completions,
  -- and current models reject the old name outright. The previous rule guessed
  -- from the model name (^o%d), which stopped matching the moment the naming
  -- convention changed, so the default model could not be used at all.
  payload.max_completion_tokens = options.max_tokens or self.config.max_tokens

  if options.reasoning_effort then
    payload.reasoning_effort = options.reasoning_effort
  end

  -- There is no temperature default, so anything here is the caller's choice
  -- and travels. It is deliberately not stripped for reasoning models: the old
  -- rule dropped it for `^o%d`, but gpt-5.x refuses a temperature too and
  -- cannot be recognised by name, so stripping for one family and not the
  -- other was inconsistent in the direction that hides the problem. A clear
  -- 400 naming the parameter beats a silent drop that looks like it applied.
  payload.temperature = options.temperature or self.config.temperature

  return payload
end

-- Send a chat message
function OpenAIProvider:chat(messages, options)
  options = options or {}
  if (options.api or self.config.api) == "responses" then
    return self:response(messages, options)
  end
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_build_chat_payload(messages, options)

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat request failed")
  end

  return Response.normalize("openai", response.body)
end

-- Process a chat message with tools
function OpenAIProvider:chat_with_tools(messages, tools, options)
  options = options or {}
  if (options.api or self.config.api) == "responses" then
    local payload = self:_responses_payload(messages, options, tools)
    local response, err, details = self.http:post(self.config.base_url .. "/responses", payload)
    if err or not response then
      return nil, self:transport_error(err, details, "Response request failed")
    end
    if response.status ~= 200 then
      return nil, self:format_error(response, "Response request failed")
    end
    return Response.normalize("openai", normalize_responses_body(response.body))
  end
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_build_chat_payload(messages, options)
  payload.tools = Tool.to_provider_format(tools, "openai")
  payload.tool_choice = options.tool_choice or "auto"

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat with tools request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat with tools request failed")
  end

  return Response.normalize("openai", response.body)
end

-- Stream a text completion
function OpenAIProvider:stream_complete(prompt, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  local model = options.model or self.config.model

  -- Check if the model only supports the chat completion API
  if is_chat_only_model(model) then
    -- Convert prompt to chat format and use stream_chat method instead
    local chat_messages = {
      { role = "user", content = prompt }
    }

    local response = self:stream_chat(chat_messages, function(delta, full)
      -- Convert chat format to completion format
      if delta.choices and delta.choices[1] and delta.choices[1].delta and delta.choices[1].delta.content then
        local text_delta = {
          choices = {
            {
              text = delta.choices[1].delta.content,
              index = delta.choices[1].index,
              finish_reason = delta.choices[1].finish_reason
            }
          },
          delta = true
        }

        callback(text_delta, full)
      end
    end, options)

    return response
  end

  -- For models that support the completion API (e.g., text-davinci-003)
  local url = self.config.base_url .. "/completions"

  local payload = {
    model = model,
    prompt = prompt,
    max_tokens = options.max_tokens or self.config.max_tokens,
    temperature = options.temperature or self.config.temperature,
    stream = true
  }

  -- Track the full text for each choice in the response
  local accumulated_text = {}
  local current_response = {
    choices = {},
    id = nil,
    model = model,
    object = "text_completion"
  }

  -- Import the streaming module
  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  -- Process streaming events
  local success, _err = HttpStreaming.stream_openai(url, self.http.headers, payload, function(chunk)
    -- If there are choices in the chunk, process them
    if chunk and chunk.choices then
      for i, choice in ipairs(chunk.choices) do
        -- Initialize the choice in our accumulated response if needed
        if not current_response.choices[i] then
          current_response.choices[i] = {
            text = "",
            index = i - 1,
            finish_reason = nil
          }
          accumulated_text[i] = ""
        end

        -- Get the delta text if available
        local delta_text = ""
        if choice.text then
          -- Convert to string if needed
          delta_text = tostring(choice.text)
          accumulated_text[i] = accumulated_text[i] .. delta_text
          current_response.choices[i].text = accumulated_text[i]
        end

        -- Check for finish reason
        if choice.finish_reason then
          current_response.choices[i].finish_reason = choice.finish_reason
        end

        -- Create a delta response for this chunk only
        local delta_response = {
          choices = {
            {
              index = i - 1,
              text = delta_text,
              finish_reason = choice.finish_reason
            }
          },
          delta = true -- Mark this as a delta update
        }

        -- Call the callback with both current accumulated response and delta
        callback(delta_response, current_response)
      end
    end
  end, "openai", options)

  if not success then
    -- Fall back to non-streaming if real streaming fails
    local response, fallback_err, details = self:complete(prompt, options)
    if fallback_err or not response then
      return nil, fallback_err, details
    end

    -- Notify the caller about the full response
    callback({
      choices = {
        {
          text = response.choices[1].text,
          index = 0,
          finish_reason = "stop"
        }
      },
      delta = true
    }, response)

    return response
  end

  return current_response
end

-- Stream a chat response (with real streaming)
function OpenAIProvider:stream_chat(messages, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  if (options.api or self.config.api) == "responses" then
    local payload = self:_responses_payload(messages, options)
    payload.stream = true
    local accumulated = ""
    local current = { provider = "openai", text = "", content = "",
      model = payload.model, raw_events = {} }
    local HttpStreaming = require "ug-lua-llm.utils.http_streaming"
    local result, stream_err, stream_details = HttpStreaming.stream_sse(
      self.config.base_url .. "/responses", self.http.headers, payload,
      function(event)
        current.raw_events[#current.raw_events + 1] = event
        if type(event) == "table" and event.type == "response.output_text.delta" then
          local text = event.delta or ""
          accumulated = accumulated .. text
          current.text, current.content = accumulated, accumulated
          callback({ content = text, text = text, delta = true, raw = event,
            choices = {{ index = 0, delta = { content = text } }} }, current)
        elseif type(event) == "table" and event.type == "response.completed" and event.response then
          local complete = Response.normalize("openai", normalize_responses_body(event.response))
          for key, value in pairs(complete) do current[key] = value end
        end
      end, options.timeout or self.config.timeout or 120, "POST", "openai", options)
    if not result then
      local response, fallback_err, details = self:chat(messages, options)
      if not response then
        return nil, fallback_err or stream_err, details or stream_details
      end
      callback({ content = response.text, text = response.text, delta = true,
        choices = {{ index = 0, delta = { content = response.text }, finish_reason = "stop" }} }, response)
      return response
    end
    return current
  end
  local url = self.config.base_url .. "/chat/completions"

  local payload = {
    model = options.model or self.config.model,
    messages = messages,
    -- Chat Completions replaced max_tokens with max_completion_tokens and
    -- current models reject the old name. The non-streaming builder was fixed
    -- in 0.3.0; these two send the same payload to the same endpoint and were
    -- missed, so streaming was rejected and quietly fell back to a non-streaming
    -- request that reported success.
    max_completion_tokens = options.max_tokens or self.config.max_tokens,
    temperature = options.temperature or self.config.temperature,
    stream = true
  }

  local accumulator = ChatStream.new(
    options.model or self.config.model, "openai", false)

  -- Import the streaming module
  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  local success, _err = HttpStreaming.stream_openai(
    url, self.http.headers, payload,
    function(chunk) accumulator:consume(chunk, callback) end, "openai", options)

  if not success then
    -- Fall back to non-streaming if real streaming fails
    local response, fallback_err, details = self:chat(messages, options)
    if fallback_err or not response then
      return nil, fallback_err, details
    end

    callback(ChatStream.fallback_delta(response, "openai"), response)

    return response
  end

  return accumulator.current
end

-- Stream a chat response with tools (with real streaming)
function OpenAIProvider:stream_chat_with_tools(messages, tools, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  if (options.api or self.config.api) == "responses" then
    -- Function-call events are typed output items. Return a complete normalized
    -- response until the registry grows a typed incremental tool-call API.
    local response, err, details = self:chat_with_tools(messages, tools, options)
    if not response then return nil, err, details end
    callback({ content = response.text, text = response.text,
      tool_calls = response.tool_calls, finish_reason = response.finish_reason,
      delta = true }, response)
    return response
  end
  local url = self.config.base_url .. "/chat/completions"

  local formatted_tools = Tool.to_provider_format(tools, "openai")

  local payload = {
    model = options.model or self.config.model,
    messages = messages,
    -- Chat Completions replaced max_tokens with max_completion_tokens and
    -- current models reject the old name. The non-streaming builder was fixed
    -- in 0.3.0; these two send the same payload to the same endpoint and were
    -- missed, so streaming was rejected and quietly fell back to a non-streaming
    -- request that reported success.
    max_completion_tokens = options.max_tokens or self.config.max_tokens,
    temperature = options.temperature or self.config.temperature,
    tools = formatted_tools,
    tool_choice = options.tool_choice or "auto",
    stream = true
  }

  local accumulator = ChatStream.new(
    options.model or self.config.model, "openai", true)

  -- Import the streaming module
  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  local success, _err = HttpStreaming.stream_openai(
    url, self.http.headers, payload,
    function(chunk) accumulator:consume(chunk, callback) end, "openai", options)

  if not success then
    -- Fall back to non-streaming if real streaming fails

    local response, fallback_err, details = self:chat_with_tools(messages, tools, options)
    if fallback_err or not response then
      return nil, fallback_err, details
    end

    callback(ChatStream.fallback_delta(response, "openai"), response)

    return response
  end

  return accumulator.current
end

return OpenAIProvider
