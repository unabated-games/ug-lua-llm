local Config = require("ug-lua-llm.core.config")

describe("Config", function()
  describe("new", function()
    it("returns defaults when no options given", function()
      local cfg = Config.new()
      assert.are.equal(120, cfg.timeout)
      assert.are.equal(3, cfg.retries)
      assert.are.equal(1, cfg.retry_delay)
      assert.are.equal(0.7, cfg.temperature)
      assert.are.equal(1024, cfg.max_tokens)
      assert.are.equal(false, cfg.debug)
      assert.is_nil(cfg.api_key)
      assert.is_nil(cfg.model)
    end)

    it("keeps cancellation tokens by reference", function()
      local token = { cancelled = false }
      local cfg = Config.new({ cancel_token = token })
      token.cancelled = true
      assert.is_true(cfg.cancel_token.cancelled)
    end)

    it("does not share mutable default or caller tables", function()
      local headers = { nested = { value = 1 } }
      local first = Config.new({ headers = headers })
      local second = Config.new()
      first.headers.nested.value = 2
      first.headers.extra = true
      assert.are.equal(1, headers.nested.value)
      assert.is_nil(second.headers.extra)
    end)

    it("overrides defaults with user options", function()
      local cfg = Config.new({ timeout = 30, model = "gpt-4o" })
      assert.are.equal(30, cfg.timeout)
      assert.are.equal("gpt-4o", cfg.model)
      assert.are.equal(0.7, cfg.temperature) -- unchanged default
    end)

    it("passes through extra options not in defaults", function()
      local cfg = Config.new({ custom_field = "hello" })
      assert.are.equal("hello", cfg.custom_field)
    end)
  end)

  describe("merge", function()
    it("merges override into base", function()
      local base = { a = 1, b = 2 }
      local merged = Config.merge(base, { b = 3, c = 4 })
      assert.are.equal(1, merged.a)
      assert.are.equal(3, merged.b)
      assert.are.equal(4, merged.c)
    end)

    it("handles nil override", function()
      local base = { a = 1 }
      local merged = Config.merge(base, nil)
      assert.are.equal(1, merged.a)
    end)

    it("does not modify the original base", function()
      local base = { a = 1 }
      Config.merge(base, { a = 2 })
      assert.are.equal(1, base.a)
    end)
  end)
end)
