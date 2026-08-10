local Error = require("ug-lua-llm.core.error")

describe("structured errors", function()
  it("classifies retryable HTTP failures and keeps only safe headers", function()
    local details = Error.http("OpenAI-Compatible", {
      status = 429,
      headers = {
        ["Retry-After"] = "3",
        ["X-Request-ID"] = "req_123",
        Authorization = "Bearer secret",
      },
      body = { error = { message = "slow down", code = "rate_limit" } },
    }, "slow down")

    assert.are.equal("http", details.kind)
    assert.are.equal("openai-compatible", details.provider)
    assert.are.equal(429, details.status)
    assert.are.equal("rate_limit", details.code)
    assert.is_true(details.retryable)
    assert.are.equal("3", details.headers["retry-after"])
    assert.are.equal("req_123", details.headers["x-request-id"])
    assert.is_nil(details.headers.authorization)
  end)

  it("redacts sensitive fields recursively without changing the input", function()
    local body = {
      api_key = "secret",
      error = { access_token = "token", message = "invalid key" },
    }
    local details = Error.http("Test", { status = 401, body = body }, "failed")

    assert.are.equal("[REDACTED]", details.body.api_key)
    assert.are.equal("[REDACTED]", details.body.error.access_token)
    assert.are.equal("invalid key", details.body.error.message)
    assert.are.equal("secret", body.api_key)
  end)

  it("distinguishes timeouts from other transport failures", function()
    local timeout = Error.transport("Gemini", "request failed", "operation timed out")
    local transport = Error.transport("Gemini", "request failed", "connection refused")

    assert.are.equal("timeout", timeout.kind)
    assert.is_true(timeout.retryable)
    assert.are.equal("transport", transport.kind)
  end)

  it("sanitizes circular response data", function()
    local value = {}
    value.self = value
    assert.are.equal("[circular]", Error.sanitize(value).self)
  end)
end)
