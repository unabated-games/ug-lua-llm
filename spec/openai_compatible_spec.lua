local mock = require("spec.helpers.mock_http")

describe("OpenAI-compatible providers", function()
  before_each(function()
    mock.reset()
  end)

  local function test_provider(name, module_path, expected_base_url, expected_model, extra_config)
    describe(name, function()
      local Provider = require(module_path)

      it("creates with correct defaults", function()
        local config = { api_key = "sk-test" }
        if extra_config then
          for k, v in pairs(extra_config) do config[k] = v end
        end
        local p = Provider.new(config)
        assert.are.equal(expected_base_url, p.config.base_url)
        assert.are.equal(expected_model, p.config.model)
      end)

      it("sends chat requests to correct endpoint", function()
        local config = { api_key = "sk-test" }
        if extra_config then
          for k, v in pairs(extra_config) do config[k] = v end
        end
        local p = Provider.new(config)
        mock.inject(p)
        mock.register("POST", expected_base_url .. "/chat/completions", {
          status = 200,
          body = {
            choices = {
              { message = { role = "assistant", content = "Hello from " .. name }, finish_reason = "stop" },
            },
          },
        })

        local result, err = p:chat({ { role = "user", content = "Hi" } })
        assert.is_nil(err)
        assert.are.equal("Hello from " .. name, result.choices[1].message.content)
        assert.are.equal("Hello from " .. name, result.text)
        assert.are.equal(name:lower(), result.provider)
        assert.is_not_nil(result.raw)
      end)

      it("handles errors gracefully", function()
        local config = { api_key = "sk-test" }
        if extra_config then
          for k, v in pairs(extra_config) do config[k] = v end
        end
        local p = Provider.new(config)
        mock.inject(p)
        mock.register("POST", expected_base_url .. "/chat/completions", {
          status = 500,
          body = { error = { message = "Internal error" } },
        })

        local result, err = p:chat({ { role = "user", content = "Hi" } })
        assert.is_nil(result)
        assert.are.equal("Internal error", err)
      end)
    end)
  end

  test_provider(
    "Groq",
    "ug-lua-llm.providers.groq",
    "https://api.groq.com/openai/v1",
    "llama-3.3-70b-versatile"
  )

  test_provider(
    "Grok",
    "ug-lua-llm.providers.grok",
    "https://api.x.ai/v1",
    "grok-4.3"
  )

  test_provider(
    "OpenRouter",
    "ug-lua-llm.providers.openrouter",
    "https://openrouter.ai/api/v1",
    "~openai/gpt-latest"
  )

  test_provider(
    "DeepSeek",
    "ug-lua-llm.providers.deepseek",
    "https://api.deepseek.com/v1",
    "deepseek-v4-flash"
  )

  test_provider(
    "Mistral",
    "ug-lua-llm.providers.mistral",
    "https://api.mistral.ai/v1",
    "mistral-large-latest"
  )

  describe("Ollama", function()
    local OllamaProvider = require("ug-lua-llm.providers.ollama")

    it("creates without requiring an API key", function()
      local p = OllamaProvider.new()
      assert.are.equal("http://localhost:11434/v1", p.config.base_url)
      assert.are.equal("llama3.2", p.config.model)
      assert.is_nil(p.http.headers.Authorization)
    end)

    it("sends chat requests", function()
      local p = OllamaProvider.new()
      mock.inject(p)
      mock.register("POST", "http://localhost:11434/v1/chat/completions", {
        status = 200,
        body = {
          choices = {
            { message = { role = "assistant", content = "Local response" }, finish_reason = "stop" },
          },
        },
      })

      local result, err = p:chat({ { role = "user", content = "Hi" } })
      assert.is_nil(err)
      assert.are.equal("Local response", result.choices[1].message.content)
    end)
  end)

  describe("custom endpoint capabilities", function()
    local UGLuaLLM = require("ug-lua-llm")

    it("returns actionable errors for explicitly unsupported features", function()
      local client = UGLuaLLM.openai_compatible({
        base_url = "http://localhost:8000/v1",
        model = "local-model",
        capabilities = { tools = false, streaming = false, models = false },
      })

      local _, tools_err = client:chat_with_tools({}, {})
      assert.are.equal(
        "Tool calling is disabled for this OpenAI-compatible endpoint", tools_err)

      local _, stream_err = client:stream_chat({}, function() end)
      assert.are.equal(
        "Streaming is disabled for this OpenAI-compatible endpoint", stream_err)

      local _, models_err = client:list_models()
      assert.are.equal(
        "Model listing is disabled for this OpenAI-compatible endpoint", models_err)
    end)

    it("builds shared payloads with tools and forwarded options", function()
      local client = UGLuaLLM.openai_compatible({
        base_url = "http://localhost:8000/v1",
        model = "local-model",
      })
      local payload = client.provider:_chat_payload(
        { { role = "user", content = "Hi" } },
        { seed = 42, response_format = { type = "json_object" } },
        { { name = "lookup", description = "Look up a value", parameters = {} } },
        true)
      assert.are.equal("local-model", payload.model)
      assert.are.equal(42, payload.seed)
      assert.are.equal("json_object", payload.response_format.type)
      assert.are.equal("lookup", payload.tools[1]["function"].name)
      assert.is_true(payload.stream)
    end)

    it("does not mutate caller configuration when applying adapter defaults", function()
      local config = { api_key = "sk-test" }
      local GroqProvider = require("ug-lua-llm.providers.groq")
      GroqProvider.new(config)
      assert.is_nil(config.base_url)
      assert.is_nil(config.model)
    end)

    it("sends mocked requests with and without authentication", function()
      for _, case in ipairs({
        { api_key = nil, authorization = nil },
        { api_key = "secret", authorization = "Bearer secret" },
      }) do
        mock.reset()
        local client = UGLuaLLM.openai_compatible({
          base_url = "http://localhost:8000/v1",
          model = "local-model",
          api_key = case.api_key,
        })
        assert.are.equal(case.authorization,
          client.provider.http.headers.Authorization)
        mock.inject(client.provider)
        mock.register("POST", "http://localhost:8000/v1/chat/completions", {
          status = 200,
          body = { choices = { { message = { content = "ok" } } } },
        })
        local response, err = client:chat({ { role = "user", content = "Hi" } })
        assert.is_nil(err)
        assert.are.equal("ok", response.text)
      end
    end)
  end)

  describe("Grok list_models", function()
    it("uses the provider models endpoint", function()
      local GrokProvider = require("ug-lua-llm.providers.grok")
      local p = GrokProvider.new({ api_key = "sk-test" })
      mock.inject(p)
      mock.register("GET", "https://api.x.ai/v1/models", {
        status = 200, body = { data = { { id = "grok-4.3" } } },
      })
      local models = p:list_models()
      assert.truthy(#models >= 1)
      assert.are.equal("grok-4.3", models[1].id)
    end)
  end)

  describe("OpenRouter headers", function()
    it("sets optional attribution headers with their canonical names", function()
      local OpenRouterProvider = require("ug-lua-llm.providers.openrouter")
      local p = OpenRouterProvider.new({ api_key = "sk-test",
        http_referer = "https://example.com", x_title = "Example" })
      assert.are.equal("https://example.com", p.http.headers["HTTP-Referer"])
      assert.are.equal("Example", p.http.headers["X-OpenRouter-Title"])
      assert.is_nil(p.http.headers["X-Title"])
    end)
  end)
end)
