local UGLuaLLM = require("ug-lua-llm")

describe("ug-lua-llm init", function()
  it("has version string", function()
    assert.is_not_nil(UGLuaLLM._VERSION)
    assert.truthy(type(UGLuaLLM._VERSION) == "string")
  end)

  it("exposes core modules", function()
    assert.is_not_nil(UGLuaLLM.Config)
    assert.is_not_nil(UGLuaLLM.Embeddings)
    assert.is_not_nil(UGLuaLLM.Error)
    assert.is_not_nil(UGLuaLLM.Conformance)
    assert.is_not_nil(UGLuaLLM.Doctor)
    assert.is_not_nil(UGLuaLLM.Logger)
    assert.is_not_nil(UGLuaLLM.RateLimiter)
    assert.is_not_nil(UGLuaLLM.Tool)
    assert.is_not_nil(UGLuaLLM.ToolRegistry)
  end)

  describe("new", function()
    it("creates an OpenAI client", function()
      local client = UGLuaLLM.new("openai", { api_key = "sk-test" })
      assert.is_not_nil(client)
      assert.is_not_nil(client.provider)
    end)

    it("creates a Claude client", function()
      local client = UGLuaLLM.new("claude", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates a Gemini client", function()
      local client = UGLuaLLM.new("gemini", { api_key = "test-key" })
      assert.is_not_nil(client)
    end)

    it("creates a Groq client", function()
      local client = UGLuaLLM.new("groq", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates a Grok client", function()
      local client = UGLuaLLM.new("grok", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates an OpenRouter client", function()
      local client = UGLuaLLM.new("openrouter", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates an Ollama client", function()
      local client = UGLuaLLM.new("ollama", {})
      assert.is_not_nil(client)
    end)

    it("creates a DeepSeek client", function()
      local client = UGLuaLLM.new("deepseek", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates a Mistral client", function()
      local client = UGLuaLLM.new("mistral", { api_key = "sk-test" })
      assert.is_not_nil(client)
    end)

    it("creates an unauthenticated OpenAI-compatible client", function()
      local client = UGLuaLLM.openai_compatible({
        base_url = "http://localhost:8000/v1/",
        model = "local-model",
      })
      assert.are.equal("http://localhost:8000/v1", client.provider.config.base_url)
      assert.is_nil(client.provider.http.headers.Authorization)
    end)

    it("adds custom endpoint authentication and headers when configured", function()
      local client = UGLuaLLM.new("openai-compatible", {
        base_url = "https://models.example.test/v1",
        model = "team-model",
        api_key = "secret",
        headers = { ["X-Tenant"] = "example" },
      })
      assert.are.equal("Bearer secret", client.provider.http.headers.Authorization)
      assert.are.equal("example", client.provider.http.headers["X-Tenant"])
    end)

    it("requires a base URL and model for custom endpoints", function()
      assert.has_error(function()
        UGLuaLLM.openai_compatible({ model = "local-model" })
      end, "openai-compatible base_url is required")
      assert.has_error(function()
        UGLuaLLM.openai_compatible({ base_url = "http://localhost:8000/v1" })
      end, "openai-compatible model is required")
    end)

    it("errors on unsupported provider", function()
      assert.has_error(function()
        UGLuaLLM.new("unknown_provider", {})
      end)
    end)
  end)
end)
