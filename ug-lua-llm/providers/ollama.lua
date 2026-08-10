local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local OllamaProvider = {}

function OllamaProvider.new(config)
  return OpenAICompatible.with_defaults(config, {
    base_url = "http://localhost:11434/v1",
    model = "llama3.2",
    provider_name = "Ollama",
    tool_format = "openai",
    require_api_key = false,
  })
end

return OllamaProvider
