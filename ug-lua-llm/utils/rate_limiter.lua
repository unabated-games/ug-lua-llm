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

function Bucket:acquire(count)
  count = count or 1
  self:refill()

  if self.tokens >= count then
    self.tokens = self.tokens - count
    return true, 0
  end

  -- Calculate wait time needed
  local deficit = count - self.tokens
  local wait_time = deficit / self.refill_rate
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

  limiter.request_bucket:wait_and_acquire(1)

  if limiter.token_bucket and token_count then
    limiter.token_bucket:wait_and_acquire(token_count)
  end

  return true
end

-- Check if a request is allowed without blocking
function RateLimiter.check(provider_name)
  local limiter = limiters[provider_name]
  if not limiter then
    return true, 0
  end

  return limiter.request_bucket:acquire(1)
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
