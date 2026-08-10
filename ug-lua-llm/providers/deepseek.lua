local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local DeepSeekProvider = {}

function DeepSeekProvider.new(config)
  return OpenAICompatible.with_defaults(config, {
    base_url = "https://api.deepseek.com/v1",
    model = "deepseek-v4-flash",
    provider_name = "DeepSeek",
    tool_format = "openai",
  })
end

return DeepSeekProvider
