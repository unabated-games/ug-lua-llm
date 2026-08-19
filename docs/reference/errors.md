# Errors, retries, and observability

All operations return `result, err, details`:

```lua
local response, err, details = client:chat(messages)
if not response then
  io.stderr:write(err, "\n")
  if details then
    print(details.kind, details.status, details.retryable)
  end
end
```

`details.kind` distinguishes validation, transport, timeout, serialization,
decoding, and HTTP failures. Details can also include provider, status,
provider code, retryability, safe headers, and a sanitized response body.
Credentials, tokens, passwords, secrets, and authorization headers are
redacted.

## Lifecycle hooks

Set `on_request`, `on_retry`, `on_response`, and `on_error` in client
configuration. Hooks receive sanitized metadata such as request ID, provider,
model, attempt, status, and elapsed time. Hook failures do not fail requests.

## Client-side rate limiting

`UGLuaLLM.RateLimiter` paces your own requests before a provider has to. It
holds a token bucket for requests and, optionally, one for tokens:

```lua
local RateLimiter = require("ug-lua-llm").RateLimiter

RateLimiter.configure("openai", {
  requests_per_minute = 60,
  tokens_per_minute = 90000,
  request_burst = 5,   -- defaults to the rate
})

local result = RateLimiter.acquire("openai", estimated_tokens)
if not result.ok then
  print(result.limit .. " limit; " .. result.wait .. "s short")
end
```

`acquire` waits and returns `{ ok, wait, limit, waited }`. `check` reports
without spending anything, returning `ok, wait, err, limit`. `limit` names the
bucket that bound the call — waiting on tokens when you believed you were
request-bound usually means the token estimate is wrong.

Both measure the request and token buckets before spending from either, so a
call blocked by one never loses capacity already taken from the other.

It reports rather than hangs. A request larger than the bucket can never be
satisfied by waiting, so it returns at once with `over_capacity = true` instead
of sleeping toward a refill that cannot arrive.

### Supplying the clock

`now` and `sleep` default to the wall clock and a real sleep. Supply them to
pace against a different scheduler, or to test the waiting behaviour without
waiting:

```lua
local clock = { seconds = 0 }
RateLimiter.configure("openai", {
  requests_per_minute = 60,
  request_burst = 1,
  now = function() return clock.seconds end,
  sleep = function(duration) clock.seconds = clock.seconds + duration end,
})
```

`now` must return seconds as a number and is called once at configuration, so a
clock reporting the wrong unit fails immediately rather than producing a
limiter that waits by a factor of a thousand. Supplying `now` alone yields a
limiter that reports instead of waiting, since pausing for wall-clock seconds
against a clock that does not advance is never what was meant. A `sleep` hook
that cannot pause is reported as `stalled` rather than spun on, and one that
raises cannot corrupt the limiter.

## Retry and cancellation control

Set `retry_predicate(meta)` to decide which failures retry and `backoff(meta)`
to choose the delay. Server `Retry-After` and common rate-limit reset headers
are honored.

Cancellation is cooperative:

```lua
local cancellation = { cancelled = false }
local client = require("ug-lua-llm").new("openai", {
  api_key = os.getenv("OPENAI_API_KEY"),
  cancel_token = cancellation,
})

cancellation.cancelled = true
```

Checks occur before requests, between retries, and between stream chunks. A
currently blocked network operation returns when its configured timeout does.
