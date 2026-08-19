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

describe("with an injected clock", function()
  -- The clock is a parameter, so waiting is tested by advancing a number.
  -- None of these sleep, and none of them can flake on a slow machine.
  local function fake()
    local state = { seconds = 1000, slept = {} }
    state.now = function() return state.seconds end
    state.sleep = function(duration)
      state.slept[#state.slept + 1] = duration
      state.seconds = state.seconds + duration
    end
    return state
  end

  before_each(function() RateLimiter.reset() end)

  it("refills over time rather than by wall clock", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 1, now = clock.now,
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    assert.is_false(RateLimiter.acquire("test").ok)

    clock.seconds = clock.seconds + 1  -- one second buys one request at 60/min
    assert.is_true(RateLimiter.acquire("test").ok)
  end)

  it("sleeps only as long as the bucket actually needs", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 1,
      now = clock.now, sleep = clock.sleep,
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    local result = RateLimiter.acquire("test")

    assert.is_true(result.ok)
    assert.are.equal(1, #clock.slept)
    assert.is_true(math.abs(clock.slept[1] - 1) < 0.001)
    -- Measured from the clock, not assumed from the delay requested.
    assert.is_true(math.abs(result.waited - 1) < 0.001)
  end)

  it("says which bucket bound the call", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 600, tokens_per_minute = 60,
      token_burst = 10, now = clock.now,
    })

    assert.is_true(RateLimiter.acquire("test", 10).ok)
    local ok, wait, err, limit = RateLimiter.check("test", 10)
    assert.is_false(ok)
    assert.is_nil(err)
    assert.is_true(wait > 0)
    -- Requests were plentiful; tokens were not.
    assert.are.equal("tokens", limit)
  end)

  it("returns at once when the request exceeds the bucket entirely", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, tokens_per_minute = 60, token_burst = 10,
      now = clock.now, sleep = clock.sleep,
    })

    local result = RateLimiter.acquire("test", 5000)
    assert.is_false(result.ok)
    assert.is_true(result.over_capacity)
    -- Waiting can never satisfy it, so nothing waited.
    assert.are.equal(0, #clock.slept)
  end)

  it("reports a stalled clock instead of spinning", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 1,
      now = clock.now,
      sleep = function() end,  -- a hook that cannot actually pause
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    local result = RateLimiter.acquire("test")
    assert.is_false(result.ok)
    assert.is_true(result.stalled)
  end)

  it("reports rather than waits when given a clock and no sleep hook", function()
    -- Pausing for wall-clock seconds against a clock that does not advance is
    -- never what was meant, so no sleep is inherited from the real one.
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 1, now = clock.now,
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    local result = RateLimiter.acquire("test")
    assert.is_false(result.ok)
    assert.is_nil(result.stalled)
    assert.is_true(result.wait > 0)
    assert.are.equal(0, result.waited)
  end)

  it("survives a sleep hook that raises", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 1,
      now = clock.now,
      sleep = function() error("scheduler said no") end,
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    local result = RateLimiter.acquire("test")
    assert.is_false(result.ok)
    assert.is_true(result.stalled)
    -- The limiter is still usable afterwards.
    clock.seconds = clock.seconds + 60
    assert.is_true(RateLimiter.acquire("test").ok)
  end)

  it("never manufactures tokens when the clock goes backwards", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 2, now = clock.now,
    })

    assert.is_true(RateLimiter.acquire("test").ok)
    assert.is_true(RateLimiter.acquire("test").ok)
    clock.seconds = clock.seconds - 3600
    assert.is_false(RateLimiter.acquire("test").ok)
  end)

  it("keeps a burst separate from the rate", function()
    local clock = fake()
    RateLimiter.configure("test", {
      requests_per_minute = 60, request_burst = 5, now = clock.now,
    })

    for _ = 1, 5 do assert.is_true(RateLimiter.acquire("test").ok) end
    assert.is_false(RateLimiter.acquire("test").ok)
  end)

  it("defaults the burst to the rate, leaving behaviour unchanged", function()
    local clock = fake()
    RateLimiter.configure("test", { requests_per_minute = 60, now = clock.now })
    for _ = 1, 60 do assert.is_true(RateLimiter.acquire("test").ok) end
    assert.is_false(RateLimiter.acquire("test").ok)
  end)
end)

describe("configuration errors", function()
  it("rejects a clock reporting the wrong unit at configuration time", function()
    -- A clock returning a string, or nothing, would otherwise produce a
    -- limiter that fails much later and much less clearly.
    assert.has_error(function()
      RateLimiter.configure("test", { now = function() return "12:00" end })
    end, "rate_limiter: now must return seconds as a number, not a string")
  end)

  it("rejects hooks that are not functions", function()
    assert.has_error(function()
      RateLimiter.configure("test", { now = 5 })
    end, "rate_limiter: now must be a function, not a number")
    assert.has_error(function()
      RateLimiter.configure("test", { sleep = "later" })
    end, "rate_limiter: sleep must be a function, not a string")
  end)

  it("rejects a non-positive rate", function()
    assert.has_error(function()
      RateLimiter.configure("test", { requests_per_minute = 0 })
    end, "rate_limiter: requests_per_minute must be a positive number")
  end)
end)
