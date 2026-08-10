local Provider = require("ug-lua-llm.core.provider")

describe("Provider", function()
  describe("new", function()
    it("creates a provider with config and http client", function()
      local p = Provider.new({ timeout = 30 })
      assert.is_not_nil(p.config)
      assert.is_not_nil(p.http)
      assert.are.equal(30, p.config.timeout)
    end)
  end)

  describe("unimplemented methods", function()
    local p = Provider.new({})

    it("errors on complete()", function()
      assert.has_error(function() p:complete("test") end)
    end)

    it("errors on chat()", function()
      assert.has_error(function() p:chat({}) end)
    end)

    it("errors on chat_with_tools()", function()
      assert.has_error(function() p:chat_with_tools({}, {}) end)
    end)

    it("errors on stream_complete()", function()
      assert.has_error(function() p:stream_complete("test", function() end) end)
    end)

    it("errors on stream_chat()", function()
      assert.has_error(function() p:stream_chat({}, function() end) end)
    end)

    it("errors on stream_chat_with_tools()", function()
      assert.has_error(function() p:stream_chat_with_tools({}, {}, function() end) end)
    end)

    it("errors on list_models()", function()
      assert.has_error(function() p:list_models() end)
    end)
  end)

  describe("format_error", function()
    local p = Provider.new({})

    it("returns error message from response body", function()
      local msg, details = p:format_error({
        status = 429,
        headers = { ["retry-after"] = "2" },
        body = { error = { message = "rate limited" } },
      }, "default")
      assert.are.equal("rate limited", msg)
      assert.are.equal("http", details.kind)
      assert.are.equal(429, details.status)
      assert.is_true(details.retryable)
    end)

    it("returns error string from response body", function()
      local msg = p:format_error({
        body = { error = "something went wrong" },
      }, "default")
      assert.are.equal("something went wrong", msg)
    end)

    it("returns message field from response body", function()
      local msg = p:format_error({
        body = { message = "not found" },
      }, "default")
      assert.are.equal("not found", msg)
    end)

    it("returns default when body is empty", function()
      local msg = p:format_error({}, "fallback")
      assert.are.equal("fallback", msg)
    end)

    it("returns default when response is nil", function()
      local msg = p:format_error(nil, "fallback")
      assert.are.equal("fallback", msg)
    end)
  end)
end)
