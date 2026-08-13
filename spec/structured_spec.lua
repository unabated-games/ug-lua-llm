local Structured = require("ug-lua-llm.core.structured")
local Client = require("ug-lua-llm.core.client")

local SCHEMA = {
  type = "object",
  properties = { answer = { type = "integer" } },
  required = { "answer" },
  additionalProperties = false,
}

describe("Structured", function()
  describe("spec", function()
    it("accepts a bare JSON Schema", function()
      local spec = Structured.spec(SCHEMA)
      assert.are.same(SCHEMA, spec.schema)
      assert.is_true(spec.strict)
      assert.is_not_nil(spec.name)
    end)

    it("accepts a named wrapper and honours strict = false", function()
      local spec = Structured.spec({
        name = "answer", schema = SCHEMA, strict = false,
      })
      assert.are.equal("answer", spec.name)
      assert.is_false(spec.strict)
    end)

    it("rejects values that are not a schema", function()
      assert.is_nil(Structured.spec("nope"))
      assert.is_nil(Structured.spec({ nothing = true }))
      assert.is_nil((Structured.spec(nil)))
    end)
  end)

  describe("format", function()
    it("reports how each provider carries a schema", function()
      assert.are.equal("responses", Structured.format("openai"))
      assert.are.equal("chat", Structured.format("grok"))
      assert.are.equal("schema", Structured.format("gemini"))
      assert.are.equal("tool", Structured.format("claude"))
      assert.is_false(Structured.format("nope"))
    end)
  end)

  describe("attempts", function()
    local spec = Structured.spec({ name = "answer", schema = SCHEMA })

    it("flattens the format for the Responses API", function()
      -- The Responses API rejects the nested json_schema wrapper that
      -- Chat Completions requires.
      local built = Structured.attempts("openai", spec, {})[1]()
      assert.are.equal("json_schema", built.text.format.type)
      assert.are.equal("answer", built.text.format.name)
      assert.are.same(SCHEMA, built.text.format.schema)
      assert.is_nil(built.response_format)
    end)

    it("wraps the schema for Chat Completions, then degrades", function()
      local attempts = Structured.attempts("grok", spec, {})
      assert.are.equal(3, #attempts)
      assert.are.equal("answer", attempts[1]().response_format.json_schema.name)
      -- A model refusing a schema often still honours plain JSON mode.
      assert.are.equal("json_object", attempts[2]().response_format.type)
      assert.is_nil(attempts[3]().response_format)
    end)

    it("strips keywords Gemini's restricted schema rejects", function()
      -- additionalProperties alone fails a request that every other provider
      -- accepts, and Gemini errors rather than ignoring it.
      local built = Structured.attempts("gemini", spec, {})[1]()
      local sent = built.request_options.generationConfig.responseSchema
      assert.is_nil(sent.additionalProperties)
      assert.are.equal("object", sent.type)
      assert.is_not_nil(sent.properties.answer)
      assert.are.equal("application/json",
        built.request_options.generationConfig.responseMimeType)
      -- The caller's schema must not be edited in place.
      assert.is_false(SCHEMA.additionalProperties)
    end)

    it("forces a tool call for Claude", function()
      local built = Structured.attempts("claude", spec, {})[1]()
      local tool = built.request_options.tools[1]
      assert.are.equal("answer", tool.name)
      assert.are.same(SCHEMA, tool.input_schema)
      assert.are.equal("answer", built.request_options.tool_choice.name)
    end)

    it("makes a single no-op attempt without a schema", function()
      assert.are.equal(1, #Structured.attempts("openai", nil, {}))
    end)
  end)

  describe("attach", function()
    it("decodes the JSON document from text", function()
      local result = Structured.attach({ text = '{"answer":408}' }, "grok")
      assert.are.equal(408, result.parsed.answer)
    end)

    it("takes Claude's result from the forced tool call", function()
      -- Claude answers with a tool_use block, so text is empty.
      local result = Structured.attach({
        text = "",
        tool_calls = { { name = "answer", arguments = { answer = 408 } } },
      }, "claude")
      assert.are.equal(408, result.parsed.answer)
    end)

    it("leaves parsed unset when the reply is not JSON", function()
      local result = Structured.attach({ text = "just prose" }, "grok")
      assert.is_nil(result.parsed)
    end)
  end)
end)

describe("Client structured output integration", function()
  local function provider(name, behaviour)
    return {
      config = { provider_name = name },
      calls = {},
      chat = function(self, messages, opts)
        self.calls[#self.calls + 1] = opts
        return behaviour(opts, #self.calls)
      end,
    }
  end

  it("hides the option from the provider and parses the reply", function()
    local p = provider("grok", function()
      return { text = '{"answer":408}' }
    end)
    local result = Client.new(p, {}):chat({}, { json_schema = SCHEMA })
    assert.is_nil(p.calls[1].json_schema)
    assert.is_not_nil(p.calls[1].response_format)
    assert.are.equal(408, result.parsed.answer)
    assert.is_true(result.structured_applied)
  end)

  it("degrades to JSON mode when the schema is refused", function()
    local p = provider("groq", function(_, call)
      if call == 1 then
        return nil, "This model does not support response format `json_schema`",
          { status = 400 }
      end
      return { text = '{"result":408}' }
    end)
    local result, err = Client.new(p, {}):chat({}, { json_schema = SCHEMA })
    assert.is_nil(err)
    assert.are.equal(2, #p.calls)
    assert.are.equal("json_object", p.calls[2].response_format.type)
    -- Success without the schema being enforced is reported as such.
    assert.is_false(result.structured_applied)
  end)

  it("does not retry an unrelated failure", function()
    local p = provider("grok", function()
      return nil, "rate limited", { status = 429 }
    end)
    local result, err = Client.new(p, {}):chat({}, { json_schema = SCHEMA })
    assert.is_nil(result)
    assert.are.equal("rate limited", err)
    assert.are.equal(1, #p.calls)
  end)

  it("rejects an unusable schema before making a request", function()
    local p = provider("grok", function() return { text = "{}" } end)
    local result, err, details = Client.new(p, {}):chat({}, { json_schema = 7 })
    assert.is_nil(result)
    assert.is_not_nil(err)
    assert.are.equal("validation", details.kind)
    assert.are.equal(0, #p.calls)
  end)

  it("combines a schema with reasoning control", function()
    local p = provider("grok", function()
      return { text = '{"answer":408}' }
    end)
    local result = Client.new(p, {}):chat({}, {
      json_schema = SCHEMA, reasoning = false,
    })
    assert.are.equal("none", p.calls[1].reasoning_effort)
    assert.is_not_nil(p.calls[1].response_format)
    assert.are.equal(408, result.parsed.answer)
  end)
end)
