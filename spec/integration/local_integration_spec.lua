-- Live coverage for the two adapters that need no cloud account.
--
-- Local-first use is a headline feature, and the generic openai-compatible
-- adapter is what every unnamed service goes through, yet neither had a live
-- test: the fake server in spec/e2e exercises the transport, not a real model.
-- Ollama serves both here, since it also exposes an OpenAI-compatible API.
--
-- Everything skips cleanly when no server is running, so these cost nothing to
-- have in the default integration run.
local H = require("spec.integration.helpers.integration_helper")
local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
local Embeddings = require("ug-lua-llm.core.embeddings")

local function assert_contract(result)
  if type(result.text) ~= "string" then
    error("response.text should be a string, got " .. type(result.text), 2)
  end
  if result.finish_reason ~= nil and type(result.finish_reason) ~= "string" then
    error("finish_reason should be a string or nil, got "
      .. type(result.finish_reason), 2)
  end
  if result.tool_calls ~= nil and type(result.tool_calls) ~= "table" then
    error("tool_calls should be a table or nil, got "
      .. type(result.tool_calls), 2)
  end
end

local adapters = {
  { label = "Ollama", build = function(o) return H.ollama_client(o) end },
  { label = "openai-compatible",
    build = function(o) return H.openai_compatible_client(o) end },
}

for _, adapter in ipairs(adapters) do
  describe(adapter.label .. " against a local server", function()
    local function client(overrides)
      if not H.ollama_available() then
        pending("no Ollama server at the configured base URL")
        return nil
      end
      if not H.ollama_chat_model() then
        pending("Ollama is running but has no non-embedding model pulled")
        return nil
      end
      return adapter.build(overrides)
    end

    it("completes a chat without any credential", function()
      local c = client()
      if not c then return end
      local result, err = c:chat({
        { role = "user", content = "Reply with the single word OK." },
      })
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert_contract(result)
    end)

    it("streams deltas as strings", function()
      local c = client()
      if not c then return end
      local chunks = {}
      local result, err = c:stream_chat({
        { role = "user", content = "Count from one to three." },
      }, StreamHelpers.content_callback(function(text)
        -- A leaked JSON-null sentinel would arrive here as a non-string.
        assert.are.equal("string", type(text))
        chunks[#chunks + 1] = text
      end))
      assert.is_nil(err)
      assert.is_not_nil(result)
      local joined = table.concat(chunks)
      assert.is_nil(joined:find("userdata", 1, true))
      assert.is_nil(joined:find("table:", 1, true))
    end)

    it("handles a request body past the 100-continue threshold", function()
      -- The regression that motivated 0.1.1, on a transport that never leaves
      -- the machine.
      local c = client()
      if not c then return end
      local result, err = c:chat({
        { role = "user",
          content = H.padded_prompt("Reply with the single word OK.", 4096) },
      })
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert_contract(result)
    end)

    it("lists models", function()
      local c = client()
      if not c then return end
      local models, err = c:list_models()
      assert.is_nil(err)
      assert.is_not_nil(models)
      assert.is_true(#models > 0)
      assert.are.equal("string", type(models[1].id))
    end)
  end)
end

describe("Ollama embeddings", function()
  it("embeds a batch without any credential", function()
    if not H.ollama_available() then
      pending("no Ollama server at the configured base URL")
      return
    end
    local model = H.ollama_embedding_model()
    if not model then
      pending("Ollama has no embedding model pulled")
      return
    end
    -- No base_url and no api_key: the provider default has to supply the
    -- endpoint, which is the case the documented example relies on.
    local embeddings = Embeddings.new("ollama", {
      embedding_model = model, timeout = 120, retries = 0,
    })
    local result, err = embeddings:embed({ "first", "second" })
    assert.is_nil(err)
    H.assert_valid_embeddings(result)
    assert.are.equal(2, #result.embeddings)
  end)
end)
