local Provider = require 'ug-lua-llm.core.provider'
local Tool = require 'ug-lua-llm.tools.tool'
local Options = require 'ug-lua-llm.utils.options'
local Response = require 'ug-lua-llm.core.response'
local Config = require 'ug-lua-llm.core.config'
local ChatStream = require 'ug-lua-llm.utils.openai_chat_stream'
local Pagination = require 'ug-lua-llm.utils.pagination'

local OpenAICompatible = {}
setmetatable(OpenAICompatible, { __index = Provider })

local FORWARDED_OPTIONS = {
  "response_format", "top_p", "stop", "seed", "presence_penalty",
  "frequency_penalty", "reasoning_effort", "stream_options",
  "parallel_tool_calls", "user",
}

local function build_payload(base, options)
  local payload = Options.payload(base, options)
  for _, key in ipairs(FORWARDED_OPTIONS) do
    if options[key] ~= nil then payload[key] = options[key] end
  end
  return payload
end

-- Create a new OpenAI-compatible provider.
-- Subclasses should call this from their own .new() after setting config defaults.
function OpenAICompatible.new(config)
  config = config or {}

  if config.require_api_key ~= false and not config.api_key then
    error((config.provider_name or "Provider") .. " API key is required")
  end

  if not config.base_url or config.base_url == "" then
    error((config.provider_name or "OpenAI-compatible provider") .. " base_url is required")
  end

  if not config.model or config.model == "" then
    error((config.provider_name or "OpenAI-compatible provider") .. " model is required")
  end

  config = Config.new(config)
  config.base_url = config.base_url:gsub("/+$", "")
  config.provider_name = config.provider_name or "openai-compatible"

  local provider = Provider.new(config)

  -- Local servers often need no authentication. Add the conventional bearer
  -- header only when a key was supplied; custom headers remain available for
  -- servers with a different authentication scheme.
  if config.api_key and config.api_key ~= "" then
    provider.http.headers["Authorization"] = "Bearer " .. config.api_key
  end

  -- Provider name used for tool format conversion (defaults to "openai")
  provider.tool_format = config.tool_format or "openai"

  setmetatable(provider, { __index = OpenAICompatible })
  return provider
end

-- Build a provider from adapter-specific defaults without mutating the caller's
-- configuration. Hosted adapters use this to share their constructor logic.
function OpenAICompatible.with_defaults(config, defaults)
  local merged = {}
  for key, value in pairs(defaults or {}) do merged[key] = value end
  for key, value in pairs(config or {}) do merged[key] = value end
  return OpenAICompatible.new(merged)
end

function OpenAICompatible:_chat_payload(messages, options, tools, stream)
  options = options or {}
  local payload = {
    model = options.model or self.config.model,
    messages = messages,
    max_tokens = options.max_tokens or self.config.max_tokens,
    temperature = options.temperature or self.config.temperature,
  }
  if tools then
    payload.tools = Tool.to_provider_format(tools, self.tool_format)
    -- Chat Completions spelling: a named tool is an object, not a bare name.
    local choice = options.tool_choice
    if type(choice) == "table" then
      local named = choice.name or
        (type(choice["function"]) == "table" and choice["function"].name)
      if named then choice = { type = "function", ["function"] = { name = named } } end
    end
    payload.tool_choice = choice or "auto"
  end
  if stream then payload.stream = true end
  return build_payload(payload, options)
end

-- List available models via GET /models
function OpenAICompatible:list_models(options)
  if not self:supports("models") then
    return nil, self:validation_error(
      "Model listing is disabled for this OpenAI-compatible endpoint",
      "capability_disabled")
  end
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

-- Complete a prompt (converts to chat format)
function OpenAICompatible:complete(prompt, options)
  local messages = {
    { role = "user", content = prompt }
  }
  return self:chat(messages, options)
end

-- Send a chat message
function OpenAICompatible:chat(messages, options)
  options = options or {}
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_chat_payload(messages, options)

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat request failed")
  end

  return Response.normalize(self.config.provider_name:lower(), response.body)
end

-- Chat with tools
function OpenAICompatible:chat_with_tools(messages, tools, options)
  if not self:supports("tools") then
    return nil, self:validation_error(
      "Tool calling is disabled for this OpenAI-compatible endpoint",
      "capability_disabled")
  end
  options = options or {}
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_chat_payload(messages, options, tools)

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat with tools request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat with tools request failed")
  end

  return Response.normalize(self.config.provider_name:lower(), response.body)
end

-- Stream a text completion (delegates to stream_chat)
function OpenAICompatible:stream_complete(prompt, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  local messages = {
    { role = "user", content = prompt }
  }

  return self:stream_chat(messages, function(delta, full)
    if delta.choices and delta.choices[1] and delta.choices[1].delta then
      local text_delta = {
        content = delta.choices[1].delta.content,
        text = delta.choices[1].delta.content,
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
end

-- Stream a chat response
function OpenAICompatible:stream_chat(messages, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end
  if not self:supports("streaming") then
    return nil, self:validation_error(
      "Streaming is disabled for this OpenAI-compatible endpoint",
      "capability_disabled")
  end

  options = options or {}
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_chat_payload(messages, options, nil, true)

  local accumulator = ChatStream.new(
    options.model or self.config.model, self.config.provider_name:lower(), false)

  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  local success, stream_err, stream_details = HttpStreaming.stream_openai(
    url, self.http.headers, payload,
    function(chunk) accumulator:consume(chunk, callback) end,
    self.config.provider_name, options)

  if not success then
    if options.stream_fallback == false then
      return nil, stream_err, stream_details
    end
    local response, err, details = self:chat(messages, options)
    if err or not response then
      return nil, err, details
    end

    callback(ChatStream.fallback_delta(
      response, self.config.provider_name:lower()), response)

    return response
  end

  return accumulator.current
end

-- Stream a chat response with tools
function OpenAICompatible:stream_chat_with_tools(messages, tools, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end
  if not self:supports("streaming") then
    return nil, self:validation_error(
      "Streaming is disabled for this OpenAI-compatible endpoint",
      "capability_disabled")
  end
  if not self:supports("tools") then
    return nil, self:validation_error(
      "Tool calling is disabled for this OpenAI-compatible endpoint",
      "capability_disabled")
  end

  options = options or {}
  local url = self.config.base_url .. "/chat/completions"

  local payload = self:_chat_payload(messages, options, tools, true)

  local accumulator = ChatStream.new(
    options.model or self.config.model, self.config.provider_name:lower(), true)

  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"

  local success, stream_err, stream_details = HttpStreaming.stream_openai(
    url, self.http.headers, payload,
    function(chunk) accumulator:consume(chunk, callback) end,
    self.config.provider_name, options)

  if not success then
    if options.stream_fallback == false then
      return nil, stream_err, stream_details
    end
    local response, err, details = self:chat_with_tools(messages, tools, options)
    if err or not response then
      return nil, err, details
    end

    callback(ChatStream.fallback_delta(
      response, self.config.provider_name:lower()), response)

    return response
  end

  return accumulator.current
end

return OpenAICompatible
