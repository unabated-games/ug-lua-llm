local RateLimiter = require("ug-lua-llm.utils.rate_limiter")

describe("RateLimiter", function()
  before_each(function()
    RateLimiter.reset()
  end)

  describe("configure", function()
    it("creates a rate limiter for a provider", function()
      RateLimiter.configure("test", { requests_per_minute = 60 })
      local ok, wait = RateLimiter.check("test")
      assert.is_true(ok)
      assert.are.equal(0, wait)
    end)
  end)

  describe("check", function()
    it("returns true with no wait when no limiter configured", function()
      local ok, wait = RateLimiter.check("unconfigured")
      assert.is_true(ok)
      assert.are.equal(0, wait)
    end)

    it("returns true when tokens are available", function()
      RateLimiter.configure("test", { requests_per_minute = 60 })
      local ok, wait = RateLimiter.check("test")
      assert.is_true(ok)
      assert.are.equal(0, wait)
    end)

    -- This previously asserted that a second check was denied, which only held
    -- because check consumed a token. A caller that checked before acting
    -- therefore spent its budget twice as fast as configured.
    it("does not consume, so repeated checks agree", function()
      RateLimiter.configure("test", { requests_per_minute = 1 })
      for _ = 1, 3 do
        local ok, wait = RateLimiter.check("test")
        assert.is_true(ok)
        assert.are.equal(0, wait)
      end
    end)

    it("returns false with a wait once the budget is actually spent", function()
      RateLimiter.configure("test", { requests_per_minute = 1 })
      RateLimiter.wait("test")

      local ok, wait = RateLimiter.check("test")
      assert.is_false(ok)
      assert.truthy(wait > 0)
    end)

    it("reports a request larger than the bucket instead of waiting forever", function()
      -- No amount of refilling can satisfy this, so it is unsatisfiable rather
      -- than slow, and saying so beats blocking indefinitely.
      RateLimiter.configure("test", {
        requests_per_minute = 60, tokens_per_minute = 100,
      })
      local ok, wait, err = RateLimiter.check("test", 1000)
      assert.is_false(ok)
      assert.is_nil(wait)
      assert.matches("exceeds the bucket capacity", err, 1, true)
    end)

    it("accounts for the token bucket, not just the request bucket", function()
      RateLimiter.configure("test", {
        requests_per_minute = 60, tokens_per_minute = 60,
      })
      RateLimiter.wait("test", 60)
      local ok, wait = RateLimiter.check("test", 60)
      assert.is_false(ok)
      assert.truthy(wait > 0)
    end)
  end)

  describe("wait", function()
    it("returns true immediately when no limiter configured", function()
      local ok = RateLimiter.wait("unconfigured")
      assert.is_true(ok)
    end)
  end)

  describe("remove", function()
    it("removes a configured limiter", function()
      RateLimiter.configure("test", { requests_per_minute = 1 })
      RateLimiter.check("test") -- consume the one token
      RateLimiter.remove("test")

      -- After removal, should behave as unconfigured
      local ok, wait = RateLimiter.check("test")
      assert.is_true(ok)
      assert.are.equal(0, wait)
    end)
  end)

  describe("reset", function()
    it("removes all limiters", function()
      RateLimiter.configure("a", { requests_per_minute = 1 })
      RateLimiter.configure("b", { requests_per_minute = 1 })
      RateLimiter.reset()

      local ok_a, _ = RateLimiter.check("a")
      local ok_b, _ = RateLimiter.check("b")
      assert.is_true(ok_a)
      assert.is_true(ok_b)
    end)
  end)
end)
