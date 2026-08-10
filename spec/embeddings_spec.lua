local mock = require("spec.helpers.mock_http")
local Embeddings = require("ug-lua-llm.core.embeddings")

describe("Embeddings", function()
  before_each(function()
    mock.reset()
  end)

  describe("new", function()
    it("creates an OpenAI embeddings client", function()
      local emb = Embeddings.new("openai", {
        api_key = "sk-test",
        base_url = "https://api.openai.com/v1",
      })
      assert.are.equal("openai", emb.provider)
      assert.is_not_nil(emb.embed)
    end)

    it("creates a Gemini embeddings client", function()
      local emb = Embeddings.new("gemini", { api_key = "test-key" })
      assert.are.equal("gemini", emb.provider)
    end)

    it("errors for unsupported provider", function()
      assert.has_error(function()
        Embeddings.new("claude", { api_key = "sk-test" })
      end)
    end)

    it("aliases mistral, ollama, deepseek to openai adapter", function()
      for _, name in ipairs({ "mistral", "ollama", "deepseek" }) do
        local emb = Embeddings.new(name, {
          api_key = "sk-test",
          base_url = "http://localhost",
        })
        assert.are.equal(name, emb.provider)
      end
    end)
  end)
end)
