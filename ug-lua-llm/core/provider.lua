local HttpClient = require 'ug-lua-llm.utils.http'
local Config = require 'ug-lua-llm.core.config'
local Error = require 'ug-lua-llm.core.error'

local Provider = {}

-- Create a new provider instance
function Provider.new(config)
  local provider = {
    config = Config.new(config),
    http = HttpClient.new(config),
  }

  setmetatable(provider, { __index = Provider })
  return provider
end

-- These methods should be implemented by specific providers
function Provider:complete(prompt, options)
  error("Provider:complete() not implemented")
end

function Provider:chat(messages, options)
  error("Provider:chat() not implemented")
end

function Provider:chat_with_tools(messages, tools, options)
  error("Provider:chat_with_tools() not implemented")
end

function Provider:stream_complete(prompt, callback, options)
  error("Provider:stream_complete() not implemented")
end

function Provider:stream_chat(messages, callback, options)
  error("Provider:stream_chat() not implemented")
end

function Provider:stream_chat_with_tools(messages, tools, callback, options)
  error("Provider:stream_chat_with_tools() not implemented")
end

function Provider:list_models()
  error("Provider:list_models() not implemented")
end

-- Must agree with the adapters in core/embeddings.lua. DeepSeek was left here
-- after its adapter was removed, so a caller who checked the capability first
-- was told yes and then got an error from the constructor.
local EMBEDDINGS = {
  openai = true, gemini = true, mistral = true, ollama = true,
}

-- Return configured capabilities without making a network request. Endpoint
-- conformance is intentionally separate because advertised compatibility and
-- actual wire behavior are not always the same.
function Provider:capabilities()
  local name = tostring(self.config.provider_name or "unknown"):lower()
  local function implemented(method)
    return type(self[method]) == "function" and self[method] ~= Provider[method]
  end
  local Reasoning = require "ug-lua-llm.core.reasoning"
  local result = {
    provider = name,
    model = self.config.model,
    source = "configured",
    -- What `reasoning` can achieve here: an effort string, a token budget that
    -- may refuse zero, an opt-in block that is off by default, or false when
    -- the provider offers no control at all. Model-level support still varies,
    -- which is why an unsupported request degrades rather than failing.
    reasoning_control = Reasoning.control(name),
    -- How a schema is carried: "responses", "chat", "schema", "tool", or
    -- false. Model support varies within a provider, so an unsupported
    -- request degrades to plain JSON mode and then to an ordinary reply.
    structured_output = require("ug-lua-llm.core.structured").format(name),
    chat = implemented("chat"),
    completion = implemented("complete"),
    tools = implemented("chat_with_tools"),
    streaming = implemented("stream_chat"),
    models = implemented("list_models"),
    responses = type(self.response) == "function",
    interactions = type(self.interaction) == "function",
    embeddings = EMBEDDINGS[name] == true,
    authentication_required = self.config.require_api_key ~= false,
    local_model = name == "ollama" or self.config.local_model == true,
  }
  for capability, enabled in pairs(self.config.capabilities or {}) do
    result[capability] = enabled == true
  end
  return result
end

function Provider:supports(capability)
  return self:capabilities()[capability] == true
end

-- Helper method to format a generic error
function Provider:format_error(response, default_message)
  local message
  if not response or not response.body then
    message = default_message or "Unknown error"
  else
    local body = response.body
    if type(body) == "table" then
      if body.error then
        if type(body.error) == "table" then
          message = body.error.message or default_message
        else
          message = body.error
        end
      elseif body.message then
        message = body.message
      end
    end
  end
  message = message or default_message or "Unknown error"
  return message, Error.http(self.config.provider_name, response, message)
end

function Provider:transport_error(message, details, default_message)
  message = message or default_message or "Request failed"
  return message, details or Error.transport(self.config.provider_name, message)
end

function Provider:validation_error(message, code)
  return message, Error.validation(self.config.provider_name, message, code)
end

return Provider
