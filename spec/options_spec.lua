local Options = require("ug-lua-llm.utils.options")
local JSON = require("ug-lua-llm.utils.json")

describe("Options.payload", function()
  it("returns the generated payload when there is no escape hatch", function()
    local payload = Options.payload({ model = "m", messages = { "a" } }, nil)
    assert.are.equal("m", payload.model)
  end)

  it("keeps caller fields that the provider does not generate", function()
    local payload = Options.payload({ model = "m" },
      { request_options = { safety_settings = "strict" } })
    assert.are.equal("m", payload.model)
    assert.are.equal("strict", payload.safety_settings)
  end)

  it("lets generated fields win over the caller's", function()
    -- Callers must not be able to replace required protocol fields.
    local payload = Options.payload({ model = "generated" },
      { request_options = { model = "caller" } })
    assert.are.equal("generated", payload.model)
  end)

  it("merges into a generated container instead of replacing it", function()
    -- Providers build container fields such as Gemini's generationConfig.
    -- Replacing the whole container would discard anything the caller set
    -- inside it, which made options like thinkingConfig unreachable.
    local payload = Options.payload({
      contents = { "generated" },
      generationConfig = { temperature = 0, maxOutputTokens = 500 },
    }, {
      request_options = {
        generationConfig = { thinkingConfig = { thinkingBudget = 0 } },
      },
    })
    assert.are.equal(0, payload.generationConfig.temperature)
    assert.are.equal(500, payload.generationConfig.maxOutputTokens)
    assert.are.equal(0, payload.generationConfig.thinkingConfig.thinkingBudget)
  end)

  it("still lets a generated leaf win inside a merged container", function()
    local payload = Options.payload(
      { generationConfig = { temperature = 0 } },
      { request_options = { generationConfig = { temperature = 9 } } })
    assert.are.equal(0, payload.generationConfig.temperature)
  end)

  it("replaces arrays wholesale rather than interleaving them", function()
    -- A generated message list merged element-by-element with a caller's
    -- would produce a transcript neither side asked for.
    local payload = Options.payload({ messages = { "generated" } },
      { request_options = { messages = { "caller", "extra" } } })
    assert.are.equal(1, #payload.messages)
    assert.are.equal("generated", payload.messages[1])
  end)

  it("does not mutate the caller's request_options", function()
    local request_options = { generationConfig = { thinkingConfig = { thinkingBudget = 0 } } }
    local options = { request_options = request_options }
    Options.payload({ generationConfig = { temperature = 0 } }, options)
    assert.is_nil(request_options.generationConfig.temperature)
  end)

  it("treats a JSON null sentinel as a value, not a container", function()
    local decoded = JSON.decode('{"generationConfig":null}')
    local payload = Options.payload({ model = "m" },
      { request_options = decoded })
    assert.is_true(JSON.is_null(payload.generationConfig))
  end)

  it("rejects circular request_options rather than looping", function()
    local loop = {}
    loop.self = loop
    assert.has_error(function()
      Options.payload({ model = "m" }, { request_options = loop })
    end)
  end)
end)
