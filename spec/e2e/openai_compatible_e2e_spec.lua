local base_url = os.getenv("FAKE_LLM_BASE_URL")
if not base_url then return end

local UGLuaLLM = require("ug-lua-llm")
local Tool = require("ug-lua-llm.tools.tool")

local function client(model, options)
  options = options or {}
  options.base_url = base_url
  options.model = model
  options.retries = options.retries or 0
  options.retry_delay = 0
  return UGLuaLLM.openai_compatible(options)
end

describe("real HTTP transport against a fake LLM", function()
  it("sends JSON, authentication, and custom headers", function()
    local response, err = client("fake-chat", {
      api_key = "test-secret",
      headers = { ["X-Test-Header"] = "present" },
    }):chat({ { role = "user", content = "hello" } })
    assert.is_nil(err)
    assert.are.equal("fake chat works", response.text)
    assert.are.equal("Bearer test-secret", response.raw.received_authorization)
    assert.are.equal("present", response.raw.received_test_header)
  end)

  it("lists models through the real GET path", function()
    local models, err = client("fake-chat"):list_models()
    assert.is_nil(err)
    assert.are.equal(3, #models)
    assert.are.equal("fake-stream", models[2].id)
  end)

  it("automatically follows OpenAI-style model pages", function()
    local models, err = client("fake-chat"):list_models({ page_size = 2 })
    assert.is_nil(err)
    assert.are.equal(3, #models)
    assert.are.equal("fake-tools", models[3].id)
  end)

  it("preserves useful non-2xx API errors", function()
    local response, err, details = client("fake-error"):chat({
      { role = "user", content = "fail" },
    })
    assert.is_nil(response)
    assert.are.equal("deliberate fake error", err)
    assert.are.equal("http", details.kind)
    assert.are.equal("openai-compatible", details.provider)
    assert.are.equal(400, details.status)
    assert.are.equal("bad_request", details.code)
    assert.is_false(details.retryable)
    assert.are.equal("req_fake_error", details.headers["x-request-id"])
    assert.is_nil(details.headers.authorization)
    assert.are.equal("[REDACTED]", details.body.error.api_key)
  end)

  it("classifies rate limits as retryable and exposes retry metadata", function()
    local response, err, details = client("fake-rate-limit"):chat({
      { role = "user", content = "retry later" },
    })
    assert.is_nil(response)
    assert.are.equal("rate limited", err)
    assert.are.equal(429, details.status)
    assert.are.equal("rate_limit", details.code)
    assert.is_true(details.retryable)
    assert.are.equal("0", details.headers["retry-after"])
  end)

  it("returns decoding details for malformed successful JSON", function()
    local response, err, details = client("fake-malformed"):chat({
      { role = "user", content = "decode" },
    })
    assert.is_nil(response)
    assert.are.equal("Failed to decode HTTP response JSON", err)
    assert.are.equal("decoding", details.kind)
    assert.are.equal("openai-compatible", details.provider)
    assert.are.equal(200, details.status)
  end)

  it("retries transient HTTP failures", function()
    local response, err = client("fake-retry", { retries = 1 }):chat({
      { role = "user", content = "retry" },
    })
    assert.is_nil(err)
    assert.are.equal("retry succeeded after 2 requests", response.text)
  end)

  it("emits sanitized lifecycle hooks and accepts custom backoff", function()
    local events, delays = {}, {}
    local response, err = client("fake-hook-retry", {
      retries = 1,
      on_request = function(meta) events[#events + 1] = { "request", meta } end,
      on_response = function(meta) events[#events + 1] = { "response", meta } end,
      on_retry = function(meta) events[#events + 1] = { "retry", meta } end,
      on_error = function(meta) events[#events + 1] = { "error", meta } end,
      retry_predicate = function(meta)
        return meta.status == 503
      end,
      backoff = function(meta)
        delays[#delays + 1] = meta.suggested_delay
        return 0
      end,
    }):chat({ { role = "user", content = "retry hooks" } })

    assert.is_nil(err)
    assert.are.equal("fake chat works", response.text)
    assert.are.equal(1, #delays)
    assert.is_true(math.abs(delays[1] - 0.005) < 0.0001)
    assert.are.equal("request", events[1][1])
    assert.are.equal("response", events[2][1])
    assert.are.equal(503, events[2][2].status)
    assert.are.equal("retry", events[3][1])
    assert.are.equal(0, events[3][2].delay)
    assert.are.equal(2, events[4][2].attempt)
    assert.are.equal("response", events[5][1])
    assert.are.equal(200, events[5][2].status)
    assert.are.equal(base_url .. "/chat/completions", events[1][2].url)
  end)

  it("allows a custom retry predicate to stop default retries", function()
    local response, err, details = client("fake-no-retry", {
      retries = 3,
      retry_predicate = function() return false end,
    }):chat({ { role = "user", content = "once" } })
    assert.is_nil(response)
    assert.are.equal("do not retry", err)
    assert.are.equal(1, details.attempts)
  end)

  it("supports cooperative cancellation before a request", function()
    local token = { cancelled = true }
    local errors = {}
    local response, err, details = client("fake-chat", {
      cancel_token = token,
      on_error = function(meta) errors[#errors + 1] = meta end,
    }):chat({ { role = "user", content = "cancel" } })
    assert.is_nil(response)
    assert.are.equal("Request cancelled", err)
    assert.are.equal("cancelled", details.kind)
    assert.is_false(details.retryable)
    assert.are.equal("cancelled", errors[1].error.kind)
  end)

  it("uses the configured timeout and classifies timeouts", function()
    local response, err, details = client("fake-timeout", {
      timeout = 0.02,
      retries = 0,
    }):chat({ { role = "user", content = "timeout" } })
    assert.is_nil(response)
    assert.is_truthy(err)
    assert.are.equal("timeout", details.kind)
    assert.is_true(details.retryable)
  end)

  it("can cancel an active stream between chunks", function()
    local token = { cancelled = false }
    local chunks = 0
    local response, err, details = client("fake-stream", {
      cancel_token = token,
    }):stream_chat({ { role = "user", content = "cancel stream" } }, function(delta)
      if delta.content ~= "" then
        chunks = chunks + 1
        token.cancelled = true
      end
    end)
    assert.is_nil(response)
    assert.are.equal("Request cancelled", err)
    assert.are.equal("cancelled", details.kind)
    assert.are.equal(1, chunks)
  end)

  it("runs the reusable OpenAI-compatible conformance checks", function()
    local report = UGLuaLLM.Conformance.run({
      base_url = base_url,
      model = "fake-stream",
      retries = 0,
    })
    assert.is_true(report.ok)
    assert.are.equal("models", report.checks[1].name)
    assert.are.equal("chat", report.checks[2].name)
    assert.are.equal("streaming", report.checks[3].name)
    assert.is_true(report.checks[3].chunks > 0)
  end)

  it("does not hide missing SSE support behind conformance fallback", function()
    local report = UGLuaLLM.Conformance.run({
      base_url = base_url,
      model = "fake-chat",
      retries = 0,
    })
    assert.is_false(report.ok)
    assert.is_false(report.checks[3].ok)
    assert.matches("without content chunks", report.checks[3].error, 1, true)
  end)

  it("runs the doctor's opt-in endpoint connectivity check", function()
    local report = UGLuaLLM.Doctor.run({
      endpoint = base_url,
      model = "fake-chat",
      timeout = 2,
    })
    assert.is_true(report.ok)
    assert.is_false(report.offline)
    local endpoint
    for _, check in ipairs(report.checks) do
      if check.name == "endpoint" then endpoint = check end
    end
    assert.are.equal("pass", endpoint.status)
    assert.matches("received 3 models", endpoint.message, 1, true)
  end)

  it("parses chunked, CRLF, and multiline SSE through the real stack", function()
    local chunks = {}
    local response, err = client("fake-stream"):stream_chat({
      { role = "user", content = "stream" },
    }, function(delta)
      if delta.content ~= "" then chunks[#chunks + 1] = delta.content end
    end)
    assert.is_nil(err)
    assert.are.same({ "hel", "lo" }, chunks)
    assert.are.equal("hello", response.text)
    assert.are.equal("stop", response.finish_reason)
    assert.are.equal(2, #response.raw_events)
  end)

  it("assembles fragmented streaming tool calls", function()
    local tools = {{
      name = "get_weather",
      description = "Get weather",
      parameters = { type = "object", properties = {
        city = { type = "string" },
      }, required = { "city" } },
    }}
    local response, err = client("fake-tools"):stream_chat_with_tools(
      { { role = "user", content = "weather" } }, tools, function() end)
    assert.is_nil(err)
    local calls = Tool.parse_tool_calls(response, "openai-compatible")
    assert.are.equal(1, #calls)
    assert.are.equal("get_weather", calls[1].name)
    assert.are.equal("Paris", calls[1].arguments.city)
  end)
end)
