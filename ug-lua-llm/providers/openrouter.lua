local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local OpenRouterProvider = {}
setmetatable(OpenRouterProvider, { __index = OpenAICompatible })

function OpenRouterProvider.new(config)
  config = config or {}
  config.base_url = config.base_url or "https://openrouter.ai/api/v1"
  config.model = config.model or "~openai/gpt-latest"
  config.provider_name = "OpenRouter"
  config.tool_format = "openrouter"

  local provider = OpenAICompatible.new(config)

  -- OpenRouter-specific headers
  if config.http_referer then
    provider.http.headers["HTTP-Referer"] = config.http_referer
  end
  if config.x_title then
    -- OpenRouter documents this header as X-Title; the longer name was
    -- simply ignored, so attribution never took effect.
    provider.http.headers["X-Title"] = config.x_title
  end

  setmetatable(provider, { __index = OpenRouterProvider })
  return provider
end

return OpenRouterProvider
