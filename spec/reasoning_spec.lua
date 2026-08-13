local Reasoning = require("ug-lua-llm.core.reasoning")
local Client = require("ug-lua-llm.core.client")

describe("Reasoning", function()
  describe("level", function()
    it("accepts booleans and the documented levels", function()
      assert.are.equal("none", Reasoning.level(false))
      assert.are.equal("medium", Reasoning.level(true))
      for _, level in ipairs({ "none", "low", "medium", "high" }) do
        assert.are.equal(level, Reasoning.level(level))
      end
      assert.are.equal("high", Reasoning.level("HIGH"))
    end)

    it("returns nil when unset, and an error for nonsense", function()
      assert.is_nil(Reasoning.level(nil))
      local level, err = Reasoning.level("very hard")
      assert.is_nil(level)
      assert.is_not_nil(err)
    end)
  end)

  describe("control", function()
    it("reports how each provider expresses reasoning", function()
      assert.are.equal("effort", Reasoning.control("openai"))
      assert.are.equal("effort", Reasoning.control("grok"))
      assert.are.equal("opt_in", Reasoning.control("claude"))
      assert.are.equal("budget", Reasoning.control("gemini"))
      assert.is_false(Reasoning.control("something-else"))
    end)
  end)

  describe("attempts", function()
    it("sets an effort string, then falls back to no control", function()
      local attempts = Reasoning.attempts("grok", "none", { model = "m" })
      assert.are.equal(2, #attempts)
      assert.are.equal("none", attempts[1]().reasoning_effort)
      -- Groq and Mistral reject the field outright, so the last attempt has to
      -- send nothing rather than fail the call.
      assert.is_nil(attempts[2]().reasoning_effort)
      assert.are.equal("m", attempts[2]().model)
    end)

    it("tries a zero budget, then the smallest accepted one", function()
      local attempts = Reasoning.attempts("gemini", "none", {})
      assert.are.equal(3, #attempts)
      local function budget(index)
        return attempts[index]().request_options
          .generationConfig.thinkingConfig.thinkingBudget
      end
      assert.are.equal(0, budget(1))
      assert.are.equal(1, budget(2))
      assert.is_nil(attempts[3]().request_options)
    end)

    it("keeps other request_options while setting a budget", function()
      local attempts = Reasoning.attempts("gemini", "low", {
        request_options = {
          safety = "strict",
          generationConfig = { candidateCount = 2 },
        },
      })
      local built = attempts[1]().request_options
      assert.are.equal("strict", built.safety)
      assert.are.equal(2, built.generationConfig.candidateCount)
      assert.are.equal(512, built.generationConfig.thinkingConfig.thinkingBudget)
    end)

    it("does not mutate the caller's options", function()
      local options = { request_options = { generationConfig = {} } }
      Reasoning.attempts("gemini", "high", options)[1]()
      assert.is_nil(options.request_options.generationConfig.thinkingConfig)
    end)

    it("turns Claude off by simply not asking", function()
      local attempts = Reasoning.attempts("claude", "none",
        { thinking = true, thinking_budget = 4096 })
      assert.are.equal(1, #attempts)
      assert.is_nil(attempts[1]().thinking)
      assert.is_nil(attempts[1]().thinking_budget)
    end)

    it("raises Claude's max_tokens above the thinking budget", function()
      -- Thinking is spent from max_tokens, so a ceiling at or below the budget
      -- leaves no room for an answer.
      local built = Reasoning.attempts("claude", "medium", { max_tokens = 64 })[1]()
      assert.is_true(built.thinking)
      assert.are.equal(4096, built.thinking_budget)
      assert.is_true(built.max_tokens > built.thinking_budget)
    end)

    it("makes a single no-op attempt when there is no control", function()
      assert.are.equal(1, #Reasoning.attempts("unknown", "none", {}))
      assert.are.equal(1, #Reasoning.attempts("grok", nil, {}))
    end)
  end)

  describe("refused", function()
    it("recognises a provider rejecting the control", function()
      assert.is_true(Reasoning.refused(
        "`reasoning_effort` is not supported with this model", { status = 400 }))
      assert.is_true(Reasoning.refused(
        "reasoning_effort is not enabled for this model", { status = 400 }))
      assert.is_true(Reasoning.refused(
        "Request contains an invalid argument.", { status = 400 }))
    end)

    it("leaves unrelated failures alone", function()
      -- Retrying these would hide a real error behind a second request.
      assert.is_false(Reasoning.refused("rate limited", { status = 429 }))
      assert.is_false(Reasoning.refused("server exploded", { status = 500 }))
      assert.is_false(Reasoning.refused("invalid api key", { status = 401 }))
    end)
  end)
end)

describe("Client reasoning integration", function()
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

  it("translates the option and hides it from the provider", function()
    local p = provider("grok", function(opts) return { opts = opts } end)
    Client.new(p, {}):chat({}, { reasoning = "low" })
    assert.are.equal("low", p.calls[1].reasoning_effort)
    assert.is_nil(p.calls[1].reasoning)
  end)

  it("retries without the control when the provider refuses it", function()
    local p = provider("mistral", function(opts, call)
      if call == 1 then
        return nil, "reasoning_effort is not enabled for this model",
          { status = 400 }
      end
      return { ok = true, opts = opts }
    end)
    local result, err = Client.new(p, {}):chat({}, { reasoning = false })
    assert.is_nil(err)
    assert.is_true(result.ok)
    assert.are.equal(2, #p.calls)
    assert.are.equal("none", p.calls[1].reasoning_effort)
    assert.is_nil(p.calls[2].reasoning_effort)
    -- Success without compliance is reported, not silently equated with it.
    assert.is_false(result.reasoning_applied)
  end)

  it("marks a complying request as applied", function()
    local p = provider("grok", function(opts) return { opts = opts } end)
    local result = Client.new(p, {}):chat({}, { reasoning = false })
    assert.is_nil(result.reasoning_applied)
  end)

  it("does not retry an unrelated failure", function()
    local p = provider("grok", function()
      return nil, "rate limited", { status = 429 }
    end)
    local result, err = Client.new(p, {}):chat({}, { reasoning = false })
    assert.is_nil(result)
    assert.are.equal("rate limited", err)
    assert.are.equal(1, #p.calls)
  end)

  it("rejects an unusable reasoning value before making a request", function()
    local p = provider("grok", function() return { ok = true } end)
    local result, err, details = Client.new(p, {}):chat({}, { reasoning = "max" })
    assert.is_nil(result)
    assert.is_not_nil(err)
    assert.are.equal("validation", details.kind)
    assert.are.equal(0, #p.calls)
  end)

  it("leaves requests without the option untouched", function()
    local p = provider("grok", function(opts) return { opts = opts } end)
    Client.new(p, {}):chat({}, { temperature = 0 })
    assert.is_nil(p.calls[1].reasoning_effort)
    assert.are.equal(0, p.calls[1].temperature)
  end)
end)
