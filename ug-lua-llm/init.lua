local UGLuaLLM = {
  _VERSION = '0.4.0',
  _DESCRIPTION = 'Unified Lua client for cloud LLM APIs, local Ollama models, and OpenAI-compatible endpoints',
  _LICENSE = 'MIT',
}

-- Import core modules
local Client = require 'ug-lua-llm.core.client'
local Config = require 'ug-lua-llm.core.config'
local Embeddings = require 'ug-lua-llm.core.embeddings'
local Error = require 'ug-lua-llm.core.error'

-- Import providers
local OpenAIProvider = require 'ug-lua-llm.providers.openai'
local ClaudeProvider = require 'ug-lua-llm.providers.claude'
local GrokProvider = require 'ug-lua-llm.providers.grok'
local GroqProvider = require 'ug-lua-llm.providers.groq'
local OpenRouterProvider = require 'ug-lua-llm.providers.openrouter'
local GeminiProvider = require 'ug-lua-llm.providers.gemini'
local OllamaProvider = require 'ug-lua-llm.providers.ollama'
local DeepSeekProvider = require 'ug-lua-llm.providers.deepseek'
local MistralProvider = require 'ug-lua-llm.providers.mistral'
local OpenAICompatibleProvider = require 'ug-lua-llm.providers.openai_compatible'

-- Import tools
local Tool = require 'ug-lua-llm.tools.tool'
local ToolRegistry = require 'ug-lua-llm.tools.registry'

-- Create a new client with the specified provider
function UGLuaLLM.new(providerName, config)
  -- Providers apply defaults to their config; copy first so constructing a
  -- client never mutates the caller's table.
  config = Config.new(config)
  local provider

  if providerName == 'openai' then
    provider = OpenAIProvider.new(config)
  elseif providerName == 'claude' then
    provider = ClaudeProvider.new(config)
  elseif providerName == 'grok' then
    provider = GrokProvider.new(config)
  elseif providerName == 'groq' then
    provider = GroqProvider.new(config)
  elseif providerName == 'openrouter' then
    provider = OpenRouterProvider.new(config)
  elseif providerName == 'gemini' then
    provider = GeminiProvider.new(config)
  elseif providerName == 'ollama' then
    provider = OllamaProvider.new(config)
  elseif providerName == 'deepseek' then
    provider = DeepSeekProvider.new(config)
  elseif providerName == 'mistral' then
    provider = MistralProvider.new(config)
  elseif providerName == 'openai-compatible' then
    config.provider_name = 'openai-compatible'
    config.tool_format = config.tool_format or 'openai'
    if config.require_api_key == nil then config.require_api_key = false end
    provider = OpenAICompatibleProvider.new(config)
  else
    error('Unsupported provider: ' .. providerName)
  end

  return Client.new(provider, config)
end

-- Convenience constructor for local gateways, self-hosted inference servers,
-- and vendor endpoints that implement OpenAI Chat Completions.
function UGLuaLLM.openai_compatible(config)
  return UGLuaLLM.new('openai-compatible', config)
end

-- Expose core modules
UGLuaLLM.Config = Config
UGLuaLLM.Embeddings = Embeddings
UGLuaLLM.Error = Error
UGLuaLLM.Conformance = require 'ug-lua-llm.conformance'
UGLuaLLM.Doctor = require 'ug-lua-llm.doctor'

-- Expose utilities
UGLuaLLM.Logger = require 'ug-lua-llm.utils.logger'
UGLuaLLM.RateLimiter = require 'ug-lua-llm.utils.rate_limiter'

-- Expose tools
UGLuaLLM.Tool = Tool
UGLuaLLM.ToolRegistry = ToolRegistry

return UGLuaLLM
