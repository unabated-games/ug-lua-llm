-- JSON null must never reach the normalized API.
--
-- Both backends use a truthy sentinel for null: lua-cjson a light userdata,
-- dkjson a table. Either survives `value or default`, so a provider returning
-- {"content": null} would otherwise hand callers a non-string `text`. This
-- spec runs against whichever backend is active; CI runs it under both.
local JSON = require("ug-lua-llm.utils.json")
local Response = require("ug-lua-llm.core.response")
local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
local ChatStream = require("ug-lua-llm.utils.openai_chat_stream")

local function decode(text)
  return JSON.decode(text)
end

describe("JSON null sentinel handling", function()
  it("recognises the active backend's null sentinel", function()
    local decoded = decode('{"value":null}')
    assert.is_true(JSON.is_null(decoded.value))
    assert.is_nil(JSON.value(decoded.value))
    assert.is_nil(JSON.string_value(decoded.value))
  end)

  it("is truthy, which is why plain fallbacks are unsafe", function()
    local decoded = decode('{"value":null}')
    -- Documents the trap rather than the fix: `or` does not rescue this.
    assert.is_not_nil(decoded.value)
    assert.are_not.equal("", decoded.value or "")
  end)

  it("leaves genuine values untouched", function()
    assert.are.equal("text", JSON.value("text"))
    assert.are.equal("text", JSON.string_value("text"))
    assert.are.equal(7, JSON.value(7))
    -- string_value guards a string contract, so a number is not a string.
    assert.is_nil(JSON.string_value(7))
  end)
end)

describe("Response.normalize with null fields", function()
  it("returns an empty string for null OpenAI-compatible content", function()
    local raw = decode([[{
      "choices": [{
        "finish_reason": "length",
        "message": {"role":"assistant","content":null,
                    "reasoning":null,"refusal":null}
      }]
    }]])
    local result = Response.normalize("openrouter", raw)
    assert.are.equal("string", type(result.text))
    assert.are.equal("", result.text)
    assert.are.equal("length", result.finish_reason)
    assert.is_nil(result.tool_calls)
  end)

  it("keeps real content when it is present", function()
    local raw = decode([[{
      "choices": [{"finish_reason":"stop",
                   "message":{"role":"assistant","content":"hello"}}]
    }]])
    local result = Response.normalize("openai", raw)
    assert.are.equal("hello", result.text)
    assert.are.equal("stop", result.finish_reason)
  end)

  it("treats a null finish_reason and tool_calls as absent", function()
    local raw = decode([[{
      "choices": [{"finish_reason":null,
                   "message":{"role":"assistant","content":"hi","tool_calls":null}}]
    }]])
    local result = Response.normalize("openai", raw)
    assert.are.equal("hi", result.text)
    assert.is_nil(result.finish_reason)
    assert.is_nil(result.tool_calls)
  end)

  it("does not fall through a null content to a sibling field", function()
    -- output_text must not be selected just because content is null-but-truthy.
    local raw = decode([[{
      "choices": [{"message":{"role":"assistant","content":null}}],
      "output_text": "fallback"
    }]])
    local result = Response.normalize("openai", raw)
    assert.are.equal("fallback", result.text)
  end)

  it("survives a null text block in a Claude response", function()
    -- A null here previously aborted table.concat with a hard error.
    local raw = decode([[{
      "content": [{"type":"text","text":null},{"type":"text","text":"ok"}],
      "stop_reason": null
    }]])
    local result = Response.normalize("claude", raw)
    assert.are.equal("ok", result.text)
    assert.is_nil(result.finish_reason)
  end)

  it("returns an empty string for null Gemini content", function()
    local result = Response.normalize("gemini", decode('{"content":null}'))
    assert.are.equal("string", type(result.text))
    assert.are.equal("", result.text)
  end)

  it("leaves the untouched provider payload alone", function()
    local raw = decode('{"choices":[{"message":{"content":null}}]}')
    local result = Response.normalize("openai", raw)
    assert.are.equal("", result.text)
    -- `raw` is documented as the provider's own response, sentinel included.
    assert.is_true(JSON.is_null(result.raw.choices[1].message.content))
  end)
end)

describe("streaming never emits the null sentinel", function()
  it("skips a null content delta", function()
    local seen = {}
    local callback = StreamHelpers.content_callback(function(text)
      seen[#seen + 1] = text
    end)
    -- The opening chunk of an OpenAI-compatible stream.
    callback(decode('{"choices":[{"delta":{"role":"assistant","content":null}}]}'), {})
    callback(decode('{"choices":[{"delta":{"content":"real"}}]}'), {})
    assert.are.equal("real", table.concat(seen))
    for _, chunk in ipairs(seen) do
      assert.are.equal("string", type(chunk))
    end
  end)

  it("skips a null Claude content delta", function()
    local seen = {}
    local callback = StreamHelpers.content_callback(function(text)
      seen[#seen + 1] = text
    end)
    callback(decode('{"content":null}'), {})
    callback(decode('{"content":"real"}'), {})
    assert.are.equal("real", table.concat(seen))
  end)

  it("does not accumulate the sentinel into streamed text", function()
    local stream = ChatStream.new("fake-model", "openai-compatible", false)
    local emitted = {}
    -- The role-only opening chunk carries content: null.
    stream:consume(
      decode('{"choices":[{"index":0,"delta":{"role":"assistant","content":null}}]}'),
      function(delta) emitted[#emitted + 1] = delta end)
    stream:consume(
      decode('{"choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":"stop"}]}'),
      function(delta) emitted[#emitted + 1] = delta end)

    assert.are.equal("string", type(stream.current.text))
    assert.are.equal("hello", stream.current.text)
    assert.is_nil(stream.current.text:find("userdata", 1, true))
    assert.is_nil(stream.current.text:find("table:", 1, true))
    for _, delta in ipairs(emitted) do
      assert.are.equal("string", type(delta.content))
    end
  end)

  it("keeps fallback_delta text a string when content is null", function()
    local response = decode('{"choices":[{"message":{"role":"assistant","content":null}}]}')
    local delta = ChatStream.fallback_delta(response, "openai")
    assert.are.equal("string", type(delta.text))
    assert.are.equal("", delta.text)
    assert.is_nil(tostring(delta.text):find("userdata", 1, true))
    assert.is_nil(tostring(delta.text):find("table:", 1, true))
  end)
end)
