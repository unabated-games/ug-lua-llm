local mock = require("spec.helpers.mock_http")

describe("OpenAI Provider", function()
  local OpenAIProvider

  before_each(function()
    mock.reset()
    OpenAIProvider = require("ug-lua-llm.providers.openai")
  end)

  describe("new", function()
    it("creates a provider with defaults", function()
      local p = OpenAIProvider.new({ api_key = "sk-test" })
      assert.are.equal("gpt-5.6-terra", p.config.model)
      assert.are.equal("responses", p.config.api)
      assert.are.equal("https://api.openai.com/v1", p.config.base_url)
    end)

    it("errors without api_key", function()
      assert.has_error(function()
        OpenAIProvider.new({})
      end, "OpenAI API key is required")
    end)

    it("sets Authorization header", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", api = "chat_completions" })
      assert.are.equal("Bearer sk-test", p.http.headers["Authorization"])
    end)
  end)

  describe("chat", function()
    it("sends correct payload and returns response", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", api = "chat_completions" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/chat/completions", {
        status = 200,
        body = {
          choices = {
            { message = { role = "assistant", content = "Hello!" }, finish_reason = "stop" },
          },
        },
      })

      local messages = { { role = "user", content = "Hi" } }
      local result, err = p:chat(messages)

      assert.is_nil(err)
      assert.are.equal("Hello!", result.choices[1].message.content)

      -- Verify the request payload
      local req = mock.last_request()
      assert.are.equal("POST", req.method)
      assert.are.equal("gpt-5.6-terra", req.payload.model)
      assert.are.equal("Hi", req.payload.messages[1].content)
    end)

    it("returns error on non-200 status", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", api = "chat_completions" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/chat/completions", {
        status = 400,
        body = { error = { message = "Bad request" } },
      })

      local result, err = p:chat({})
      assert.is_nil(result)
      assert.are.equal("Bad request", err)
    end)
  end)

  describe("chat_with_tools", function()
    it("includes tools in payload", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", api = "chat_completions" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/chat/completions", {
        status = 200,
        body = {
          choices = {
            {
              message = {
                role = "assistant",
                tool_calls = {
                  {
                    id = "call_1",
                    type = "function",
                    ["function"] = { name = "get_weather", arguments = '{"location":"Tokyo"}' },
                  },
                },
              },
              finish_reason = "tool_calls",
            },
          },
        },
      })

      local tools = {
        { name = "get_weather", description = "Get weather", parameters = { type = "object", properties = {} } },
      }
      local result, err = p:chat_with_tools({ { role = "user", content = "Weather?" } }, tools)

      assert.is_nil(err)
      assert.are.equal("call_1", result.choices[1].message.tool_calls[1].id)

      local req = mock.last_request()
      assert.is_not_nil(req.payload.tools)
    end)
  end)

  describe("complete", function()
    it("converts prompt to chat format for chat-only models", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", model = "gpt-4o", api = "chat_completions" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/chat/completions", {
        status = 200,
        body = {
          choices = {
            { message = { content = "response" }, finish_reason = "stop" },
          },
        },
      })

      local result, err = p:complete("Hello")
      assert.is_nil(err)
      assert.are.equal("response", result.choices[1].text)
    end)
  end)

  describe("reasoning models", function()
    it("uses max_completion_tokens for o-series models", function()
      local p = OpenAIProvider.new({ api_key = "sk-test", model = "o3", api = "chat_completions" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/chat/completions", {
        status = 200,
        body = { choices = { { message = { content = "thought" } } } },
      })

      p:chat({ { role = "user", content = "think" } }, { max_tokens = 500 })

      local req = mock.last_request()
      assert.are.equal(500, req.payload.max_completion_tokens)
      assert.is_nil(req.payload.max_tokens)
      assert.is_nil(req.payload.temperature) -- no temperature for reasoning
    end)
  end)

  describe("Responses API", function()
    it("uses typed output and normalizes text", function()
      local p = OpenAIProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("POST", "https://api.openai.com/v1/responses", {
        status = 200,
        body = { id = "resp_1", model = "gpt-5.6-terra", status = "completed", output = {
          { type = "message", content = { { type = "output_text", text = "Hello" } } },
        } },
      })
      local result = assert(p:chat({ { role = "user", content = "Hi" } }, {
        reasoning_effort = "low",
        response_format = { type = "json_schema", name = "answer", schema = { type = "object" } },
      }))
      assert.are.equal("Hello", result.text)
      local payload = mock.last_request().payload
      assert.is_not_nil(payload.input)
      assert.are.equal("low", payload.reasoning.effort)
      assert.are.equal("json_schema", payload.text.format.type)
      assert.is_nil(payload.messages)
    end)
  end)

  describe("list_models", function()
    it("returns model list", function()
      local p = OpenAIProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("GET", "https://api.openai.com/v1/models", {
        status = 200,
        body = { data = { { id = "gpt-4o" }, { id = "gpt-4o-mini" } } },
      })

      local models, err = p:list_models()
      assert.is_nil(err)
      assert.are.equal(2, #models)
    end)
  end)
end)
