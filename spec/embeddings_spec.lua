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

    it("aliases mistral and ollama to the openai adapter", function()
      -- DeepSeek was aliased here too, which is what let the documentation
      -- claim embeddings it does not serve. Its endpoint answers 404.
      for _, name in ipairs({ "mistral", "ollama" }) do
        local emb = Embeddings.new(name, {
          api_key = "sk-test",
          base_url = "http://localhost",
        })
        assert.are.equal(name, emb.provider)
      end
    end)

    -- The documented example passes only an api_key. Without a per-provider
    -- default the URL was built from a nil base_url and failed inside the
    -- adapter rather than at construction.
    it("defaults base_url per provider so none is required", function()
      local expected = {
        openai = "https://api.openai.com/v1",
        ollama = "http://localhost:11434/v1",
        mistral = "https://api.mistral.ai/v1",
        gemini = "https://generativelanguage.googleapis.com/v1beta",
      }
      for name, url in pairs(expected) do
        local emb = Embeddings.new(name, { api_key = "sk-test" })
        assert.are.equal(name, emb.provider)
        assert.are.equal(url, emb.config.base_url)
        -- Confirm the default is the URL actually requested, not just stored.
        if name ~= "gemini" then -- gemini builds a different path
          mock.reset()
          mock.inject(emb)
          mock.set_default({ status = 200,
            body = { data = { { embedding = { 0.1 } } } } })
          assert.is_not_nil(emb:embed({ "text" }))
          assert.are.equal(url .. "/embeddings", mock.last_request().url)
        end
      end
    end)

    it("respects an explicit base_url over the default", function()
      local emb = Embeddings.new("openai", {
        api_key = "sk-test", base_url = "http://custom",
      })
      mock.reset()
      mock.inject(emb)
      mock.set_default({ status = 200,
        body = { data = { { embedding = { 0.1 } } } } })
      assert.is_not_nil(emb:embed({ "text" }))
      assert.are.equal("http://custom/embeddings", mock.last_request().url)
    end)
  end)

  describe("call style", function()
    local emb

    before_each(function()
      emb = Embeddings.new("openai", { api_key = "sk-test" })
      mock.reset()
      mock.inject(emb)
      mock.set_default({ status = 200,
        body = { data = { { embedding = { 0.1, 0.2 } } } } })
    end)

    -- The docs and the agent reference both use a colon, matching the rest of
    -- the library. A colon call used to pass the object itself as the input.
    it("accepts the documented colon form", function()
      local result, err = emb:embed({ "first", "second" })
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.are.equal(1, #result.embeddings)
    end)

    it("still accepts the dot form", function()
      local result, err = emb.embed({ "first", "second" })
      assert.is_nil(err)
      assert.is_not_nil(result)
    end)

    it("passes options through in both forms", function()
      assert.is_not_nil(emb:embed({ "a" }, { dimensions = 256 }))
      assert.are.equal(256, mock.last_request().payload.dimensions)
      assert.is_not_nil(emb.embed({ "a" }, { dimensions = 512 }))
      assert.are.equal(512, mock.last_request().payload.dimensions)
    end)

    it("sends the input, not the receiver, under both forms", function()
      emb:embed({ "colon" })
      assert.are.same({ "colon" }, mock.last_request().payload.input)
      emb.embed({ "dot" })
      assert.are.same({ "dot" }, mock.last_request().payload.input)
    end)
  end)
end)

describe("providers without embeddings", function()
  it("says so rather than serving a bare 404", function()
    -- DeepSeek exposes no embeddings endpoint at all, so a caller following the
    -- documentation got a 404 that read like a misconfiguration.
    assert.has_error(function()
      Embeddings.new("deepseek", { api_key = "sk-test" })
    end)
  end)
end)
