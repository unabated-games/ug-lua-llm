local mock = require("spec.helpers.mock_http")

describe("Claude Provider", function()
  local ClaudeProvider

  before_each(function()
    mock.reset()
    ClaudeProvider = require("ug-lua-llm.providers.claude")
  end)

  describe("new", function()
    it("creates a provider with defaults", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      assert.are.equal("claude-sonnet-4-6", p.config.model)
      assert.are.equal("https://api.anthropic.com/v1", p.config.base_url)
    end)

    it("errors without api_key", function()
      assert.has_error(function()
        ClaudeProvider.new({})
      end, "Claude API key is required")
    end)

    it("sets Claude-specific headers", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      assert.are.equal("sk-test", p.http.headers["x-api-key"])
      assert.are.equal("2023-06-01", p.http.headers["anthropic-version"])
    end)
  end)

  describe("chat", function()
    it("sends correct payload and returns response", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200,
        body = {
          id = "msg_1",
          content = { { type = "text", text = "Hello!" } },
          model = "claude-sonnet-4-6",
          stop_reason = "end_turn",
        },
      })

      local messages = { { role = "user", content = "Hi" } }
      local result, err = p:chat(messages)

      assert.is_nil(err)
      assert.is_not_nil(result)

      local req = mock.last_request()
      assert.are.equal("POST", req.method)
      assert.are.equal("claude-sonnet-4-6", req.payload.model)
    end)

    it("returns error on non-200 status", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 429,
        body = { error = { message = "Rate limited" } },
      })

      local result, err = p:chat({})
      assert.is_nil(result)
      assert.are.equal("Rate limited", err)
    end)
  end)

  describe("extended thinking", function()
    it("includes thinking config when enabled", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200,
        body = { content = { { type = "text", text = "thought about it" } } },
      })

      p:chat(
        { { role = "user", content = "think hard" } },
        { thinking = true, thinking_budget = 5000 }
      )

      local req = mock.last_request()
      assert.is_not_nil(req.payload.thinking)
      assert.are.equal("enabled", req.payload.thinking.type)
      assert.are.equal(5000, req.payload.thinking.budget_tokens)
      assert.is_nil(req.payload.temperature)
    end)

    it("omits thinking when not enabled", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200,
        body = { content = { { type = "text", text = "ok" } } },
      })

      p:chat({ { role = "user", content = "hi" } })

      local req = mock.last_request()
      assert.is_nil(req.payload.thinking)
      -- No library temperature default, so nothing is sent unless asked for.
      assert.is_nil(req.payload.temperature)
    end)

    it("sends a temperature the caller chose", function()
      local p = ClaudeProvider.new({ api_key = "sk-test", temperature = 0.2 })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200,
        body = { content = { { type = "text", text = "ok" } } },
      })

      p:chat({ { role = "user", content = "hi" } })
      assert.are.equal(0.2, mock.last_request().payload.temperature)
    end)
  end)

  describe("_format_messages", function()
    it("converts system messages", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      local result, system = p:_format_messages({
        { role = "system", content = "You are helpful." },
        { role = "user", content = "Hi" },
      })
      assert.are.equal("You are helpful.", system)
      assert.are.equal("Hi", result[1].content)
      assert.are.equal(1, #result)
      assert.are.equal("user", result[1].role)
    end)

    it("passes through user and assistant messages", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      local result = p:_format_messages({
        { role = "user", content = "Hello" },
        { role = "assistant", content = "Hi there" },
      })
      assert.are.equal(2, #result)
      assert.are.equal("user", result[1].role)
      assert.are.equal("assistant", result[2].role)
    end)
  end)

  describe("system instructions and thinking validation", function()
    it("sends system separately without duplicating the user message", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200, body = { content = { { type = "text", text = "ok" } } },
      })
      p:chat({ { role = "system", content = "SYS" }, { role = "user", content = "HELLO" } })
      local payload = mock.last_request().payload
      assert.are.equal("SYS", payload.system)
      assert.are.equal(1, #payload.messages)
      assert.are.equal("HELLO", payload.messages[1].content)
    end)

    it("rejects an explicit thinking budget that consumes max_tokens", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      local result, err = p:chat({ { role = "user", content = "think" } }, {
        thinking = true, thinking_budget = 1000, max_tokens = 1000,
      })
      assert.is_nil(result)
      assert.are.equal("max_tokens must be greater than thinking_budget", err)
    end)
  end)

  describe("list_models", function()
    it("returns hardcoded model list", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      local models = p:list_models()
      assert.truthy(#models >= 3)
      assert.are.equal("claude-opus-4-6", models[1].id)
    end)
  end)

  describe("chat_with_tools", function()
    it("includes tools in payload", function()
      local p = ClaudeProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.anthropic.com/v1/messages", {
        status = 200,
        body = {
          content = {
            { type = "tool_use", id = "tool_1", name = "get_weather", input = { location = "Paris" } },
          },
          stop_reason = "tool_use",
        },
      })

      local tools = {
        { name = "get_weather", description = "Get weather", parameters = { type = "object", properties = {}, required = {} } },
      }
      local result, err = p:chat_with_tools({ { role = "user", content = "Weather?" } }, tools)

      assert.is_nil(err)
      assert.is_not_nil(result)

      local req = mock.last_request()
      assert.is_not_nil(req.payload.tools)
      assert.are.equal("get_weather", req.payload.tools[1].name)
    end)
  end)
end)
