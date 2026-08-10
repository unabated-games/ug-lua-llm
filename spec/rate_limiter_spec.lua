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

    it("returns false with wait time when exhausted", function()
      -- Configure with 1 request per minute
      RateLimiter.configure("test", { requests_per_minute = 1 })
      local ok1, _ = RateLimiter.check("test")
      assert.is_true(ok1)

      -- Second request should be denied
      local ok2, wait = RateLimiter.check("test")
      assert.is_false(ok2)
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
