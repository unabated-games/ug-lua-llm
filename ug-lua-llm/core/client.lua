local Config = require 'ug-lua-llm.core.config'
local Error = require 'ug-lua-llm.core.error'
local Reasoning = require 'ug-lua-llm.core.reasoning'
local Structured = require 'ug-lua-llm.core.structured'

local Client = {}

-- Run a provider call with the normalized `reasoning` option translated into
-- whatever this provider understands.
--
-- Providers disagree about the option's very existence: Groq and Mistral reject
-- reasoning_effort with a 400 on models that do not reason, and some Gemini
-- models refuse a zero thinking budget. Asking for less reasoning must never
-- turn a working request into a failure, so the attempts run best-first and the
-- last one always sends no reasoning control at all.
-- `request_options` promises to reach the provider untouched, which is exactly
-- what makes a name this library also owns dangerous inside it: the ladder
-- consumes the top-level `reasoning`, so a copy nested here is forwarded raw
-- and the provider rejects a parameter the caller was told to use. Only our own
-- value shape is refused -- a level string or boolean. A provider's native
-- object means the caller knows that API and is passed through untouched.
local function library_option_leak(options)
  local nested = options.request_options
  if type(nested) ~= "table" then return nil end
  local value = nested.reasoning
  if type(value) == "string" or type(value) == "boolean" then
    return "reasoning"
  end
  return nil
end

function Client:_with_reasoning(options, invoke)
  local provider_config = self.provider.config or {}
  local provider_name = provider_config.provider_name

  local leaked = library_option_leak(options)
  if leaked then
    local message = leaked ..
      " is this library's own option and is not passed through" ..
      " request_options. Set it alongside request_options rather than inside" ..
      " it, or use the provider's own field shape if you meant that."
    return nil, message, Error.validation(provider_name, message,
      "library_option_in_request_options")
  end

  local level, level_error = Reasoning.level(options.reasoning)
  if options.reasoning ~= nil and not level then
    return nil, level_error, Error.validation(
      provider_name, level_error, "invalid_reasoning")
  end

  local spec, spec_error = Structured.spec(options.json_schema)
  if options.json_schema ~= nil and not spec then
    return nil, spec_error, Error.validation(
      provider_name, spec_error, "invalid_json_schema")
  end

  -- Two independent ladders. The schema is the outer one because a model that
  -- refuses a schema usually refuses it however hard it is thinking.
  local schema_attempts = Structured.attempts(provider_name, spec, options)
  local result, err, details

  for schema_index, build_schema in ipairs(schema_attempts) do
    local schema_options = build_schema()
    local reasoning_attempts =
      Reasoning.attempts(provider_name, level, schema_options)

    for index, build in ipairs(reasoning_attempts) do
      local attempt_options = build()
      -- These are this library's own options; providers never see them.
      attempt_options.reasoning = nil
      attempt_options.json_schema = nil
      result, err, details = invoke(attempt_options)

      if result then
        -- Report compliance separately from success, so a caller can tell a
        -- degraded request from one that did what was asked. Only meaningful
        -- when the caller asked for a level, so it stays nil when they did
        -- not; a provider with no control never applied one, however the
        -- attempt went.
        if level then
          result.reasoning_applied =
            Reasoning.control(provider_name) ~= false and index == 1
        end
        if spec then
          result.structured_applied = schema_index == 1
          Structured.attach(result, provider_name)
        end
        return result, err, details
      end

      if index == #reasoning_attempts then break end
      if not Reasoning.refused(err, details) then break end
    end

    if schema_index == #schema_attempts then return result, err, details end
    if not Structured.refused(err, details) then return result, err, details end
  end

  return result, err, details
end

-- Create a new LLM client
function Client.new(provider, config)
  local client = {
    provider = provider,
    config = Config.new(config),
  }

  setmetatable(client, { __index = Client })
  return client
end

-- Complete a prompt with text completion
function Client:complete(prompt, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:complete(prompt, opts)
  end)
end

-- Send a chat message
function Client:chat(messages, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:chat(messages, opts)
  end)
end

-- Process a chat message with tools
function Client:chat_with_tools(messages, tools, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Where a provider has no response-format field, a schema is delivered *as* a
  -- forced tool call. That cannot coexist with the caller's own tools: the
  -- model can be compelled to call the schema tool or left free to choose among
  -- theirs, not both. Say so here, rather than letting the provider reject a
  -- tool name the caller never supplied.
  if merged_options.json_schema ~= nil and tools and #tools > 0 then
    local provider_name = (self.provider.config or {}).provider_name
    if Structured.format(provider_name) == "tool" then
      local message = provider_name ..
        " carries a JSON schema as a forced tool call, so json_schema cannot be" ..
        " combined with tools. Request the schema in a follow-up call, or read" ..
        " the tool result directly."
      return nil, message,
        Error.validation(provider_name, message, "schema_tool_conflict")
    end
  end

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:chat_with_tools(messages, tools, opts)
  end)
end

-- Stream a text completion
function Client:stream_complete(prompt, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:stream_complete(prompt, callback, opts)
  end)
end

-- Stream a chat response
function Client:stream_chat(messages, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:stream_chat(messages, callback, opts)
  end)
end

-- Stream a chat response with tools
function Client:stream_chat_with_tools(messages, tools, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  return self:_with_reasoning(merged_options, function(opts)
    return self.provider:stream_chat_with_tools(messages, tools, callback, opts)
  end)
end

-- Get available models
function Client:list_models(options)
  return self.provider:list_models(options or {})
end

function Client:capabilities()
  return self.provider:capabilities()
end

-- OpenAI Responses API primitive. Kept explicit so callers can use typed input
-- items and built-in tools without forcing them through chat messages.
function Client:response(input, options)
  if not self.provider.response then
    local message = "Responses API is not supported by this provider"
    return nil, message, Error.validation(
      self.provider.config.provider_name, message, "capability_unsupported")
  end
  return self.provider:response(input, Config.merge(self.config, options or {}))
end

function Client:interaction(input, options)
  if not self.provider.interaction then
    local message = "Interactions API is not supported by this provider"
    return nil, message, Error.validation(
      self.provider.config.provider_name, message, "capability_unsupported")
  end
  return self.provider:interaction(input, Config.merge(self.config, options or {}))
end

return Client
