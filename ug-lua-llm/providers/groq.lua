local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local GroqProvider = {}

function GroqProvider.new(config)
  return OpenAICompatible.with_defaults(config, {
    base_url = "https://api.groq.com/openai/v1",
    model = "llama-3.3-70b-versatile",
    provider_name = "Groq",
    tool_format = "groq",
  })
end

return GroqProvider
