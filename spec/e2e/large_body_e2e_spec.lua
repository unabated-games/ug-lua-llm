-- Real HTTP transport behaviour for request bodies around lua-http's
-- 1024-byte "Expect: 100-continue" threshold.
--
-- lua-http's request:set_body() appends "expect: 100-continue" whenever the
-- body exceeds 1024 bytes. Endpoints that never send the interim 100 response
-- leave the client waiting, and one that answers with a final response instead
-- makes lua-http drop the body entirely. The symptom is that small prompts
-- succeed while realistic ones hang, so the boundary is worth pinning exactly.
local base_url = os.getenv("FAKE_LLM_BASE_URL")
if not base_url then return end

local UGLuaLLM = require("ug-lua-llm")
local JSON = require("ug-lua-llm.utils.json")
local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")

-- base_url arrives as http://127.0.0.1:PORT/v1; the /silent variant routes to
-- a handler that deliberately never answers the expectation.
local silent_base_url = base_url:gsub("/v1$", "/silent/v1")

local function client(model, options)
  options = options or {}
  options.base_url = options.base_url or base_url
  options.model = model
  options.retries = 0
  options.retry_delay = 0
  options.timeout = options.timeout or 10
  return UGLuaLLM.openai_compatible(options)
end

-- Did the server ever see an Expect header for this model?
local function expect_seen(model)
  local http = require("ug-lua-llm.utils.http").new({ timeout = 5, retries = 0 })
  local response, err = http:get(base_url .. "/expect-log?model=" .. model)
  assert(response, tostring(err))
  return response.body.expect_seen, response.body.requests
end

-- The client adds its own fields to the payload, so the wire body is larger
-- than an encoded {model, messages} pair. Measure the real envelope by asking
-- the server what it received, then size the filler against that.
local function envelope_size(model, options)
  local response, err = client(model, options):chat({
    { role = "user", content = "" },
  })
  assert(response, tostring(err))
  return response.raw.received_content_length
end

local function content_for_body_size(model, target, options)
  local overhead = envelope_size(model, options)
  return string.rep("a", math.max(target - overhead, 1))
end

describe("request bodies around the 100-continue threshold", function()
  -- Each case gets its own model so its Expect record is independent of the
  -- order the cases run in.
  local sizes = {
    { label = "at the threshold", bytes = 1024, model = "fake-body-size-a" },
    { label = "one byte over the threshold", bytes = 1025, model = "fake-body-size-b" },
    { label = "a realistic multi-kilobyte prompt", bytes = 8192, model = "fake-body-size-c" },
  }

  for _, case in ipairs(sizes) do
    it("never negotiates 100-continue " .. case.label, function()
      local content = content_for_body_size(case.model, case.bytes)
      local response, err = client(case.model):chat({
        { role = "user", content = content },
      })
      assert.is_nil(err)
      assert.are.equal("sized", response.text)
      -- Assert the body really landed on the intended side of the boundary
      -- rather than trusting the arithmetic that built it.
      assert.are.equal(case.bytes, response.raw.received_content_length)
      assert.is_false((expect_seen(case.model)))
    end)
  end

  it("completes against a server that never sends 100 Continue", function()
    local model = "fake-body-size-silent"
    local options = { base_url = silent_base_url }
    local content = content_for_body_size(model, 4096, options)
    local started = os.time()
    local response, err = client(model, options)
      :chat({ { role = "user", content = content } })
    assert.is_nil(err)
    assert.are.equal("sized", response.text)
    assert.are.equal(4096, response.raw.received_content_length)
    assert.is_false((expect_seen(model)))
    -- A client waiting on the expectation would stall for lua-http's
    -- expect_100_timeout before recovering.
    assert.is_true(os.time() - started < 5)
  end)

  it("never negotiates 100-continue on the streaming path", function()
    local model = "fake-stream-large"
    local chunks = {}
    local response, err = client(model):stream_chat({
      { role = "user", content = string.rep("a", 4096) },
    }, StreamHelpers.content_callback(function(text)
      chunks[#chunks + 1] = text
    end))
    assert.is_nil(err)
    assert.is_not_nil(response)
    assert.are.equal("streamed", table.concat(chunks))
    assert.is_false((expect_seen(model)))
  end)

  it("streams against a server that never sends 100 Continue", function()
    local model = "fake-stream-large-silent"
    local chunks = {}
    local response, err = client(model, { base_url = silent_base_url })
      :stream_chat({
        { role = "user", content = string.rep("a", 4096) },
      }, StreamHelpers.content_callback(function(text)
        chunks[#chunks + 1] = text
      end))
    assert.is_nil(err)
    assert.is_not_nil(response)
    assert.are.equal("streamed", table.concat(chunks))
    assert.is_false((expect_seen(model)))
  end)
end)

describe("configured timeouts cover the whole exchange", function()
  it("fails when headers never arrive", function()
    local response, err, details = client("fake-timeout", { timeout = 0.05 })
      :chat({ { role = "user", content = "slow" } })
    assert.is_nil(response)
    assert.is_not_nil(err)
    assert.are.equal("timeout", details.kind)
  end)

  it("fails when the body stalls after the headers arrive", function()
    -- Without a deadline on the body read this blocks until the server gives
    -- up, and a nil body would otherwise be reported as a successful empty
    -- response.
    local started = os.time()
    local response, err, details = client("fake-slow-body", { timeout = 1 })
      :chat({ { role = "user", content = "stall" } })
    assert.is_nil(response)
    assert.is_not_nil(err)
    assert.is_not_nil(details)
    assert.is_true(os.time() - started < 8)
  end)
end)

describe("JSON null never escapes through the normalized response", function()
  it("returns an empty string when content is null", function()
    local response, err = client("fake-null"):chat({
      { role = "user", content = "exhaust the allowance" },
    })
    assert.is_nil(err)
    assert.are.equal("string", type(response.text))
    assert.are.equal("", response.text)
    assert.are.equal("length", response.finish_reason)
    assert.is_nil(response.tool_calls)
    -- The untouched provider payload still carries the sentinel by design.
    assert.is_true(JSON.is_null(response.raw.choices[1].message.content))
  end)

  it("does not emit the null sentinel while streaming", function()
    local chunks = {}
    local response, err = client("fake-null-stream"):stream_chat({
      { role = "user", content = "stream nulls" },
    }, StreamHelpers.content_callback(function(text)
      chunks[#chunks + 1] = text
    end))
    assert.is_nil(err)
    assert.is_not_nil(response)
    local joined = table.concat(chunks)
    assert.are.equal("real", joined)
    assert.is_nil(joined:find("userdata", 1, true))
    assert.is_nil(joined:find("table:", 1, true))
  end)
end)
