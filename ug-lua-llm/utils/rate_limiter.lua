local socket = require "socket"

local RateLimiter = {}

-- Token bucket implementation
local Bucket = {}
Bucket.__index = Bucket

function Bucket.new(capacity, refill_rate)
  return setmetatable({
    capacity = capacity,
    tokens = capacity,
    refill_rate = refill_rate,  -- tokens per second
    last_refill = socket.gettime(),
  }, Bucket)
end

function Bucket:refill()
  local now = socket.gettime()
  local elapsed = now - self.last_refill
  local new_tokens = elapsed * self.refill_rate
  self.tokens = math.min(self.capacity, self.tokens + new_tokens)
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

function Bucket:acquire(count)
  count = count or 1
  local ok, wait_time, err = self:peek(count)
  if err then return false, nil, err end
  if ok then
    self.tokens = self.tokens - count
    return true, 0
  end
  return false, wait_time
end

function Bucket:wait_and_acquire(count)
  count = count or 1
  local ok, wait_time = self:acquire(count)
  if ok then
    return true
  end

  socket.sleep(wait_time)
  -- After sleeping, refill and take tokens
  self:refill()
  self.tokens = self.tokens - count
  return true
end

-- Per-provider rate limiters
local limiters = {}

-- Configure rate limits for a provider
function RateLimiter.configure(provider_name, opts)
  opts = opts or {}

  local rpm = opts.requests_per_minute or 60
  local tpm = opts.tokens_per_minute

  limiters[provider_name] = {
    request_bucket = Bucket.new(rpm, rpm / 60),
  }

  if tpm then
    limiters[provider_name].token_bucket = Bucket.new(tpm, tpm / 60)
  end
end

-- Wait until a request is allowed for the given provider.
-- Returns immediately if no limiter is configured.
function RateLimiter.wait(provider_name, token_count)
  local limiter = limiters[provider_name]
  if not limiter then
    return true
  end

  local use_tokens = limiter.token_bucket and token_count
  -- Measure both buckets before spending from either. Taking the request
  -- token first and then waiting on the token bucket discarded the request
  -- token that had already been spent.
  while true do
    local request_ok, request_wait, request_err = limiter.request_bucket:peek(1)
    if request_err then return false, request_err end

    local token_ok, token_wait = true, 0
    if use_tokens then
      local token_err
      token_ok, token_wait, token_err = limiter.token_bucket:peek(token_count)
      if token_err then return false, token_err end
    end

    if request_ok and token_ok then
      limiter.request_bucket:acquire(1)
      if use_tokens then limiter.token_bucket:acquire(token_count) end
      return true
    end

    socket.sleep(math.max(request_wait or 0, token_wait or 0))
  end
end

-- Whether a request would be allowed right now, and how long until it would
-- be. This only reports: it used to call acquire, so a caller that checked
-- before acting spent its budget twice as fast as configured.
function RateLimiter.check(provider_name, token_count)
  local limiter = limiters[provider_name]
  if not limiter then
    return true, 0
  end

  local ok, wait_time, err = limiter.request_bucket:peek(1)
  if err then return false, nil, err end
  if limiter.token_bucket and token_count then
    local token_ok, token_wait, token_err =
      limiter.token_bucket:peek(token_count)
    if token_err then return false, nil, token_err end
    if not token_ok then
      return false, math.max(wait_time or 0, token_wait or 0)
    end
  end
  return ok, wait_time
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
