local OpenAICompatible = require 'ug-lua-llm.providers.openai_compatible'

local GroqProvider = {}

function GroqProvider.new(config)
  return OpenAICompatible.with_defaults(config, {
    base_url = "https://api.groq.com/openai/v1",
    -- Groq retires models without notice, and a stale default fails only for
    -- users who did not set one -- which is the newest users.
    model = "openai/gpt-oss-20b",
    provider_name = "Groq",
    tool_format = "groq",
  })
end

return GroqProvider
