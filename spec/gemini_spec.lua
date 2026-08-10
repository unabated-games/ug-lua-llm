local mock = require("spec.helpers.mock_http")

describe("Gemini Provider", function()
  local GeminiProvider

  before_each(function()
    mock.reset()
    GeminiProvider = require("ug-lua-llm.providers.gemini")
  end)

  describe("new", function()
    it("creates a provider with defaults", function()
      local p = GeminiProvider.new({ api_key = "test-key" })
      assert.are.equal("gemini-3.6-flash", p.config.model)
      assert.are.equal("https://generativelanguage.googleapis.com/v1beta", p.config.base_url)
    end)

    it("uses the API key header and never puts it in request URLs", function()
      local p = GeminiProvider.new({ api_key = "secret-key" })
      assert.are.equal("secret-key", p.http.headers["x-goog-api-key"])
      assert.is_nil(p:_url("gemini-3.6-flash", "generateContent"):match("secret%-key"))
    end)

    it("errors without api_key", function()
      assert.has_error(function()
        GeminiProvider.new({})
      end, "Gemini API key is required")
    end)
  end)

  describe("_format_contents", function()
    it("converts messages to Gemini format", function()
      local p = GeminiProvider.new({ api_key = "test" })
      local contents, sys = p:_format_contents({
        { role = "user", content = "Hello" },
        { role = "assistant", content = "Hi" },
      })
      assert.are.equal(2, #contents)
      assert.are.equal("user", contents[1].role)
      assert.are.equal("model", contents[2].role)
      assert.is_nil(sys)
    end)

    it("extracts system instruction", function()
      local p = GeminiProvider.new({ api_key = "test" })
      local contents, sys = p:_format_contents({
        { role = "system", content = "Be helpful" },
        { role = "user", content = "Hello" },
      })
      assert.are.equal(1, #contents) -- only user
      assert.is_not_nil(sys)
      assert.are.equal("Be helpful", sys.parts[1].text)
    end)
  end)

  describe("_format_response", function()
    it("converts Gemini response to normalized format", function()
      local p = GeminiProvider.new({ api_key = "test" })
      local result = p:_format_response({
        candidates = {
          {
            content = { parts = { { text = "Hello!" } } },
            finishReason = "STOP",
          },
        },
        modelVersion = "gemini-2.5-flash",
        usageMetadata = {
          promptTokenCount = 5,
          candidatesTokenCount = 2,
          totalTokenCount = 7,
        },
      })
      assert.are.equal("Hello!", result.content)
      assert.are.equal("STOP", result.finish_reason)
      assert.are.equal(5, result.usage.prompt_tokens)
    end)

    it("extracts tool calls from response", function()
      local p = GeminiProvider.new({ api_key = "test" })
      local result = p:_format_response({
        candidates = {
          {
            content = {
              parts = {
                {
                  functionCall = {
                    name = "get_weather",
                    args = { location = "Tokyo" },
                  },
                },
              },
            },
            finishReason = "STOP",
          },
        },
      })
      assert.is_not_nil(result.tool_calls)
      assert.are.equal(1, #result.tool_calls)
      assert.are.equal("get_weather", result.tool_calls[1]["function"].name)
    end)
  end)

  describe("chat", function()
    it("sends correct payload and returns response", function()
      local p = GeminiProvider.new({ api_key = "test-key" })
      mock.inject(p)

      local url_pattern = "https://generativelanguage%.googleapis%.com/v1beta/models/gemini%-3%.6%-flash:generateContent"
      mock.register("POST", url_pattern, {
        status = 200,
        body = {
          candidates = {
            { content = { parts = { { text = "Hi there!" } } }, finishReason = "STOP" },
          },
        },
      })

      local result, err = p:chat({ { role = "user", content = "Hello" } })
      assert.is_nil(err)
      assert.are.equal("Hi there!", result.content)

      local req = mock.last_request()
      assert.is_not_nil(req.payload.contents)
    end)
  end)

  describe("list_models", function()
    it("returns parsed model list", function()
      local p = GeminiProvider.new({ api_key = "test-key" })
      mock.inject(p)

      mock.register("GET", "https://generativelanguage%.googleapis%.com/v1beta/models", {
        status = 200,
        body = {
          models = {
            { name = "models/gemini-2.5-flash", displayName = "Gemini 2.5 Flash" },
          },
        },
      })

      local models, err = p:list_models()
      assert.is_nil(err)
      assert.are.equal(1, #models)
      assert.are.equal("gemini-2.5-flash", models[1].id)
    end)

    it("follows Gemini page tokens", function()
      local p = GeminiProvider.new({ api_key = "test-key" })
      mock.inject(p)
      local base = "https://generativelanguage.googleapis.com/v1beta/models"
      mock.register("GET", base, { status = 200, body = {
        models = {{ name = "models/first", displayName = "First" }},
        nextPageToken = "next page",
      } })
      mock.register("GET", base .. "?pageToken=next%20page", {
        status = 200,
        body = { models = {{ name = "models/second", displayName = "Second" }} },
      })

      local models = assert(p:list_models())
      assert.are.equal(2, #models)
      assert.are.equal("second", models[2].id)
      assert.are.equal(2, mock.request_count())
    end)
  end)

  describe("Interactions API", function()
    it("accepts typed input and normalizes model output steps", function()
      local p = GeminiProvider.new({ api_key = "test-key" })
      mock.inject(p)
      mock.register("POST", "https://generativelanguage.googleapis.com/v1beta/interactions", {
        status = 200, body = { id = "int_1", model = "gemini-3.5-flash",
          status = "completed", steps = {{ type = "model_output", content = {
            { type = "text", text = "A sunset" },
          } }} },
      })
      local result = assert(p:interaction({
        { type = "image", mime_type = "image/jpeg", data = "..." },
        { type = "text", text = "Describe it" },
      }))
      assert.are.equal("A sunset", result.text)
      assert.is_nil(mock.last_request().url:match("test%-key"))
    end)
  end)
end)
