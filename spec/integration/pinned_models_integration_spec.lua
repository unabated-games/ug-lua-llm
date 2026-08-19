-- Every model this repository names, checked against the service.
--
-- Providers retire models without notice, and a stale default fails only for
-- users who did not set one -- which is the newest users, on their first call.
-- This has already happened twice: Groq's default and the examples helper's
-- Grok pin both went dead between releases, and nothing noticed until someone
-- reading the source tried them.
local H = require("spec.integration.helpers.integration_helper")

local UGLuaLLM = require("ug-lua-llm")

-- The provider defaults, exercised by creating a client with no model at all.
local provider_defaults = {
  { label = "OpenAI", provider = "openai", key = "OPENAI_API_KEY" },
  { label = "Claude", provider = "claude", key = "ANTHROPIC_API_KEY" },
  { label = "Gemini", provider = "gemini", key = "GEMINI_API_KEY" },
  { label = "Grok", provider = "grok", key = "GROK_API_KEY" },
  { label = "Groq", provider = "groq", key = "GROQ_API_KEY" },
  { label = "DeepSeek", provider = "deepseek", key = "DEEPSEEK_API_KEY" },
  { label = "Mistral", provider = "mistral", key = "MISTRAL_API_KEY" },
  { label = "OpenRouter", provider = "openrouter", key = "OPENROUTER_API_KEY" },
}

describe("pinned models still exist", function()
  for _, entry in ipairs(provider_defaults) do
    it(entry.label .. " serves its default model", function()
      if not H.has_env(entry.key) then
        pending(entry.key .. " not set")
        return
      end
      -- No model: this is exactly what a new user gets.
      local client = UGLuaLLM.new(entry.provider, {
        api_key = H.get_env(entry.key),
        max_tokens = 16, timeout = 45, retries = 0,
      })
      local result, err, details = client:chat({
        { role = "user", content = "Reply with just: OK" },
      })
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(entry.label .. " unavailable: " .. reason)
        return
      end
      -- A 404 or "model not found" here means the default has been retired.
      assert.is_nil(err)
      assert.is_not_nil(result)
    end)
  end

  it("the examples helper pins models that still resolve", function()
    local factory = require("examples.helpers.client_factory")
    local providers = factory.PROVIDER_CONFIGS
    assert.is_table(providers)
    local checked = 0
    for name, config in pairs(providers) do
      local key = config.env_key
      if config.default_model and key and H.has_env(key) then
        local client = UGLuaLLM.new(name, {
          api_key = H.get_env(key), model = config.default_model,
          max_tokens = 16, timeout = 45, retries = 0,
        })
        local result, err, details = client:chat({
          { role = "user", content = "Reply with just: OK" },
        })
        if not result and not H.unavailable_reason(err, details) then
          error(string.format("examples helper pins %s for %s, which the service rejected: %s",
            config.default_model, name, tostring(err)), 0)
        end
        checked = checked + 1
      end
    end
    -- A test that silently checks nothing is worse than no test.
    assert.is_true(checked > 0)
  end)
end)

describe("pinned embedding models still exist", function()
  -- The chat defaults have rotted twice and the embedding defaults had rotted
  -- silently the whole time: Gemini's was retired outright, and Mistral was
  -- being asked for an OpenAI model it has never had. Both only ever failed
  -- users who did not pass a model of their own.
  local LLM = require("ug-lua-llm")
  local env = require("ug-lua-llm.utils.env")
  env.load(".env")
  env.load("examples/.env")

  local PROVIDERS = {
    { name = "openai", key = "OPENAI_API_KEY" },
    { name = "gemini", key = "GEMINI_API_KEY" },
    { name = "mistral", key = "MISTRAL_API_KEY" },
  }

  for _, provider in ipairs(PROVIDERS) do
    it(provider.name .. " serves its default embedding model", function()
      local api_key = env.get(provider.key)
      if not api_key then return end

      local embeddings = LLM.Embeddings.new(provider.name, { api_key = api_key })
      local result, err = embeddings:embed({ "pinned model check" })

      assert.is_table(result, tostring(err))
      assert.is_table(result.embeddings[1].embedding)
      assert.is_true(#result.embeddings[1].embedding > 0)
    end)
  end

  it("does not claim embeddings for a provider that serves none", function()
    -- DeepSeek has no embeddings endpoint; aliasing it produced a bare 404.
    assert.has_error(function()
      LLM.Embeddings.new("deepseek", { api_key = "k" })
    end)
  end)
end)
