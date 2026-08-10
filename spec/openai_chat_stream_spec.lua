local ChatStream = require("ug-lua-llm.utils.openai_chat_stream")

describe("OpenAI Chat Completions stream normalization", function()
  it("emits normalized deltas and accumulates compatibility content", function()
    local stream = ChatStream.new("local-model", "openai-compatible", false)
    local deltas = {}
    local function capture(delta) deltas[#deltas + 1] = delta end

    stream:consume({ id = "chat_1", model = "served-model", choices = {{
      index = 0, delta = { role = "assistant", content = "hel" },
    }} }, capture)
    stream:consume({ choices = {{
      index = 0, delta = { content = "lo" }, finish_reason = "stop",
    }} }, capture)

    assert.are.equal("hel", deltas[1].content)
    assert.are.equal("hello", stream.current.text)
    assert.are.equal("hello", stream.current.choices[1].message.content)
    assert.are.equal("stop", stream.current.finish_reason)
    assert.are.equal("chat_1", stream.current.id)
    assert.are.equal("served-model", stream.current.model)
    assert.are.equal(2, #stream.current.raw_events)
    assert.are.equal("openai-compatible", deltas[1].provider)
  end)

  it("uses wire choice indexes rather than array positions", function()
    local stream = ChatStream.new("model", "openai", false)
    stream:consume({ choices = {{ index = 1, delta = { content = "second" } }} },
      function() end)
    assert.is_nil(stream.current.choices[1])
    assert.are.equal("second", stream.current.choices[2].message.content)
  end)

  it("assembles fragmented tool names and arguments", function()
    local stream = ChatStream.new("model", "openai", true)
    local seen
    stream:consume({ choices = {{ index = 0, delta = { tool_calls = {{
      index = 0, id = "call_1", type = "function",
      ["function"] = { name = "get_", arguments = '{"city":' },
    }} } }} }, function(delta) seen = delta end)
    stream:consume({ choices = {{ index = 0, delta = { tool_calls = {{
      index = 0, ["function"] = { name = "weather", arguments = '"Paris"}' },
    }} }, finish_reason = "tool_calls" }} }, function(delta) seen = delta end)

    local call = stream.current.tool_calls[1]
    assert.are.equal("call_1", call.id)
    assert.are.equal("get_weather", call["function"].name)
    assert.are.equal('{"city":"Paris"}', call["function"].arguments)
    assert.are.equal("tool_calls", seen.finish_reason)
    assert.is_not_nil(seen.tool_calls)
  end)

  it("normalizes non-streaming text and tool fallbacks", function()
    local text = ChatStream.fallback_delta({ choices = {{
      message = { content = "hello" }, finish_reason = "stop",
    }} }, "openai")
    assert.are.equal("hello", text.content)
    assert.are.equal("hello", text.choices[1].delta.content)

    local calls = {{ id = "call_1", type = "function", ["function"] = {
      name = "lookup", arguments = "{}",
    } }}
    local tool = ChatStream.fallback_delta({ choices = {{
      message = { content = "", tool_calls = calls },
      finish_reason = "tool_calls",
    }} }, "openai")
    assert.are.equal(calls, tool.tool_calls)
    assert.are.equal(calls, tool.choices[1].delta.tool_calls)
  end)
end)
