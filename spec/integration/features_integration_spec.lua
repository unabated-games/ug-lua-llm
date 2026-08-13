-- Live checks for the two normalized options, whose whole promise is that they
-- behave sensibly across providers that disagree about them.
--
-- The contract under test is not "the model complied" — several genuinely
-- cannot — but "the request still succeeded, and the response said what
-- happened".
local H = require("spec.integration.helpers.integration_helper")

local SCHEMA = {
  name = "answer",
  schema = {
    type = "object",
    properties = { answer = { type = "integer" } },
    required = { "answer" },
    additionalProperties = false,
  },
}

local providers = {
  { label = "OpenAI", key = "OPENAI_API_KEY", build = H.openai_client },
  { label = "Claude", key = "ANTHROPIC_API_KEY", build = H.claude_client },
  { label = "Gemini", key = "GEMINI_API_KEY", build = H.gemini_client },
  { label = "Grok", key = "GROK_API_KEY", build = H.grok_client },
  { label = "Groq", key = "GROQ_API_KEY", build = H.groq_client },
  { label = "Mistral", key = "MISTRAL_API_KEY", build = H.mistral_client },
  { label = "DeepSeek", key = "DEEPSEEK_API_KEY", build = H.deepseek_client },
  { label = "OpenRouter", key = "OPENROUTER_API_KEY", build = H.openrouter_client },
}

for _, provider in ipairs(providers) do
  describe(provider.label .. " normalized options", function()
    local function client(overrides)
      if not H.has_env(provider.key) then
        pending(provider.key .. " not set")
        return nil
      end
      return provider.build(overrides)
    end

    it("never fails a request by asking for less reasoning", function()
      local c = client({ max_tokens = 400 })
      if not c then return end
      local result, err, details = c:chat({
        { role = "user", content = "What is 17 * 24? Reply with only the number." },
      }, { reasoning = false })
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(provider.label .. " unavailable: " .. reason)
        return
      end
      -- Groq and Mistral reject the control outright, and some Gemini models
      -- refuse a zero budget. All of them must still answer.
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.are.equal("string", type(result.text))
      -- Reported honestly either way.
      if result.reasoning_applied ~= nil then
        assert.are.equal("boolean", type(result.reasoning_applied))
      end
    end)

    it("reports what reasoning it can control", function()
      local c = client()
      if not c then return end
      local control = c:capabilities().reasoning_control
      assert.is_true(control == false or type(control) == "string")
    end)

    it("never fails a request by asking for a schema", function()
      local c = client({ max_tokens = 400 })
      if not c then return end
      local result, err, details = c:chat({
        { role = "user", content = "What is 17 * 24? Respond as JSON." },
      }, { json_schema = SCHEMA })
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(provider.label .. " unavailable: " .. reason)
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.are.equal("boolean", type(result.structured_applied))
      -- Where the provider enforced the schema, the decoded object must match
      -- it. Where it degraded, the reply is still valid, just unconstrained.
      if result.structured_applied then
        assert.is_table(result.parsed)
        assert.are.equal("number", type(result.parsed.answer))
      end
    end)
  end)
end
