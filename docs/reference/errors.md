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
