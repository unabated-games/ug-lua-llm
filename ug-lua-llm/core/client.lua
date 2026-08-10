local Config = require 'ug-lua-llm.core.config'
local Error = require 'ug-lua-llm.core.error'

local Client = {}

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

  -- Delegate to provider's completion method
  return self.provider:complete(prompt, merged_options)
end

-- Send a chat message
function Client:chat(messages, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Delegate to provider's chat method
  return self.provider:chat(messages, merged_options)
end

-- Process a chat message with tools
function Client:chat_with_tools(messages, tools, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Delegate to provider's chat_with_tools method
  return self.provider:chat_with_tools(messages, tools, merged_options)
end

-- Stream a text completion
function Client:stream_complete(prompt, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Delegate to provider's stream_complete method
  return self.provider:stream_complete(prompt, callback, merged_options)
end

-- Stream a chat response
function Client:stream_chat(messages, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Delegate to provider's stream_chat method
  return self.provider:stream_chat(messages, callback, merged_options)
end

-- Stream a chat response with tools
function Client:stream_chat_with_tools(messages, tools, callback, options)
  options = options or {}
  local merged_options = Config.merge(self.config, options)

  -- Delegate to provider's stream_chat_with_tools method
  return self.provider:stream_chat_with_tools(messages, tools, callback, merged_options)
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
