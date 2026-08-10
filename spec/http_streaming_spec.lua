local HttpStreaming = require("ug-lua-llm.utils.http_streaming")

describe("SSE parser", function()
  it("handles fragmented CRLF frames, comments, multiline data, and DONE", function()
    local events = {}
    local parser = HttpStreaming.new_sse_parser(function(event)
      events[#events + 1] = event
    end)
    parser:feed(": keepalive\r\nda")
    parser:feed("ta: {\"value\":")
    parser:feed("1}\r\n\r\ndata: first\n")
    parser:feed("data: second\n\ndata: [DONE]\n\n")
    parser:finish()
    assert.are.equal(2, #events)
    assert.are.equal(1, events[1].value)
    assert.are.equal("first\nsecond", events[2])
    assert.is_true(parser.done)
  end)
end)
