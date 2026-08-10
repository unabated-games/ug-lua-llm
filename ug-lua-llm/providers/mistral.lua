local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local MistralProvider = {}

function MistralProvider.new(config)
  return OpenAICompatible.with_defaults(config, {
    base_url = "https://api.mistral.ai/v1",
    model = "mistral-large-latest",
    provider_name = "Mistral",
    tool_format = "openai",
  })
end

return MistralProvider
