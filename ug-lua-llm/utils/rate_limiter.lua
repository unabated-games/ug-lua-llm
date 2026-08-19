local socket = require "socket"

local RateLimiter = {}

-- A backstop on the wait loop. Reaching it means the configured rate cannot
-- serve the caller, which is a configuration answer rather than a slow one.
local MAX_WAITS = 64

-- Token bucket. The clock is a parameter rather than a call to the wall clock,
-- so the waiting behaviour can be tested by advancing a number instead of
-- sleeping. Nothing below reads the real time.
local Bucket = {}
Bucket.__index = Bucket

function Bucket.new(capacity, refill_rate, now)
  return setmetatable({
    capacity = capacity,
    tokens = capacity,
    refill_rate = refill_rate,  -- tokens per second
    now = now,
    last_refill = now(),
  }, Bucket)
end

function Bucket:refill()
  local now = self.now()
  local elapsed = now - self.last_refill
  -- A clock that goes backwards must not manufacture tokens.
  if elapsed > 0 then
    self.tokens = math.min(self.capacity, self.tokens + elapsed * self.refill_rate)
  end
  self.last_refill = now
end

-- How long until `count` tokens are available, without taking any. A request
-- larger than the bucket can ever hold is unsatisfiable rather than slow, and
-- is reported as such instead of returning a wait that never ends.
function Bucket:peek(count)
  count = count or 1
  if count > self.capacity then
    return false, nil, "request of " .. count ..
      " exceeds the bucket capacity of " .. self.capacity
  end
  self:refill()
  if self.tokens >= count then return true, 0 end
  return false, (count - self.tokens) / self.refill_rate
end

function Bucket:take(count)
  self.tokens = self.tokens - (count or 1)
end

-- Per-provider rate limiters
local limiters = {}

local function positive_rate(name, value)
  local number = tonumber(value)
  if not number or number <= 0 then
    error("rate_limiter: " .. name .. " must be a positive number", 3)
  end
  return number
end

local function checked_clock(now)
  if now == nil then return socket.gettime end
  if type(now) ~= "function" then
    error("rate_limiter: now must be a function, not a " .. type(now), 3)
  end
  -- Call it once here so a clock reporting the wrong unit -- or nothing at all
  -- -- fails at configuration with a clear message, rather than producing a
  -- limiter that waits by a factor of a thousand.
  local at = now()
  if type(at) ~= "number" then
    error("rate_limiter: now must return seconds as a number, not a " ..
      type(at), 3)
  end
  return now
end

-- Configure rate limits for a provider.
--
-- `request_burst` and `token_burst` default to their rates, so behaviour is
-- unchanged unless a burst is asked for. `now` and `sleep` default to the wall
-- clock and a real sleep; supplying them is how the waiting path is tested.
-- Supplying `now` alone yields a limiter that never waits, only reports.
function RateLimiter.configure(provider_name, opts)
  opts = opts or {}

  if opts.sleep ~= nil and type(opts.sleep) ~= "function" then
    error("rate_limiter: sleep must be a function, not a " ..
      type(opts.sleep), 2)
  end

  local now = checked_clock(opts.now)
  local rpm = positive_rate("requests_per_minute", opts.requests_per_minute or 60)
  local request_burst = positive_rate("request_burst", opts.request_burst or rpm)

  -- Only pair the real sleep with the real clock. A caller who supplied a
  -- clock and no sleep gets a limiter that reports instead of waiting, because
  -- pausing for wall-clock seconds against a clock that does not advance is
  -- never what was meant.
  local sleep = opts.sleep
  if sleep == nil and opts.now == nil then sleep = socket.sleep end

  local limiter = {
    now = now,
    sleep = sleep,
    requests_per_minute = rpm,
    request_bucket = Bucket.new(request_burst, rpm / 60, now),
  }

  if opts.tokens_per_minute then
    local tpm = positive_rate("tokens_per_minute", opts.tokens_per_minute)
    local token_burst = positive_rate("token_burst", opts.token_burst or tpm)
    limiter.tokens_per_minute = tpm
    limiter.token_bucket = Bucket.new(token_burst, tpm / 60, now)
  end

  limiters[provider_name] = limiter
end

-- What a request would need right now, touching both buckets and spending from
-- neither. Everything that reports and everything that spends goes through
-- here, so a measurement can never consume a token by accident.
--
-- Returns the wait in seconds, which bucket bound the call, and an error when
-- the request can never be satisfied.
local function measure(limiter, token_count)
  local ok, wait, err = limiter.request_bucket:peek(1)
  if err then return nil, "requests", err end
  local limit = (not ok) and "requests" or nil
  wait = wait or 0

  if limiter.token_bucket and token_count and token_count > 0 then
    local token_ok, token_wait, token_err = limiter.token_bucket:peek(token_count)
    if token_err then return nil, "tokens", token_err end
    token_wait = token_wait or 0
    -- Report whichever limit actually bound the call. Waiting on tokens when
    -- you believed you were request-bound usually means the estimate is wrong.
    if not token_ok and token_wait > wait then
      wait, limit = token_wait, "tokens"
    end
  end

  return wait, limit
end

-- Take from both buckets, or from neither.
local function take(limiter, token_count)
  local wait, limit, err = measure(limiter, token_count)
  if err then
    return { ok = false, over_capacity = true, limit = limit, error = err }
  end
  if wait > 0 then
    return { ok = false, wait = wait, limit = limit }
  end
  limiter.request_bucket:take(1)
  if limiter.token_bucket and token_count and token_count > 0 then
    limiter.token_bucket:take(token_count)
  end
  return { ok = true, wait = 0 }
end

-- Acquire capacity, waiting when a sleep hook is available.
--
-- Reports rather than hangs: a request larger than the bucket returns at once,
-- a clock that does not move ends the loop, and a sleep hook that faults cannot
-- take the limiter's state with it.
function RateLimiter.acquire(provider_name, token_count)
  local limiter = limiters[provider_name]
  if not limiter then return { ok = true, wait = 0, waited = 0 } end

  local waited, rounds = 0, 0
  while true do
    local result = take(limiter, token_count)
    result.waited = waited
    if result.ok or result.over_capacity then return result end
    if type(limiter.sleep) ~= "function" then return result end

    rounds = rounds + 1
    if rounds > MAX_WAITS then
      result.gave_up = true
      return result
    end

    local before = limiter.now()
    pcall(limiter.sleep, result.wait)
    local after = limiter.now()
    if after <= before then
      -- The sleep did nothing, so looping would spin. Say so instead.
      result.stalled = true
      return result
    end
    waited = waited + (after - before)
  end
end

-- Wait until a request is allowed for the given provider.
-- Returns immediately if no limiter is configured.
function RateLimiter.wait(provider_name, token_count)
  local result = RateLimiter.acquire(provider_name, token_count)
  if result.ok then return true end
  return false, result.error or
    ("rate limit not satisfied after waiting " .. result.waited .. "s")
end

-- Whether a request would be allowed right now, and how long until it would
-- be. This only reports: it used to call acquire, so a caller that checked
-- before acting spent its budget twice as fast as configured.
function RateLimiter.check(provider_name, token_count)
  local limiter = limiters[provider_name]
  if not limiter then return true, 0 end

  local wait, limit, err = measure(limiter, token_count)
  if err then return false, nil, err, limit end
  return wait == 0, wait, nil, limit
end

-- Remove rate limits for a provider
function RateLimiter.remove(provider_name)
  limiters[provider_name] = nil
end

-- Reset all rate limiters
function RateLimiter.reset()
  limiters = {}
end

return RateLimiter
