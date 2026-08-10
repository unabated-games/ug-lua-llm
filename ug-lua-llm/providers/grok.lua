local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local GrokProvider = {}
setmetatable(GrokProvider, { __index = OpenAICompatible })

function GrokProvider.new(config)
  config = config or {}
  config.base_url = config.base_url or "https://api.x.ai/v1"
  config.model = config.model or "grok-4.3"
  config.provider_name = "Grok"
  config.tool_format = "grok"

  local provider = OpenAICompatible.new(config)
  setmetatable(provider, { __index = GrokProvider })
  return provider
end

return GrokProvider
