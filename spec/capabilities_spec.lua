local UGLuaLLM = require("ug-lua-llm")

describe("client capabilities", function()
  it("describes a hosted provider without network access", function()
    local capabilities = UGLuaLLM.new("openai", { api_key = "test" }):capabilities()
    assert.are.equal("openai", capabilities.provider)
    assert.are.equal("configured", capabilities.source)
    assert.is_true(capabilities.chat)
    assert.is_true(capabilities.streaming)
    assert.is_true(capabilities.tools)
    assert.is_true(capabilities.responses)
    assert.is_true(capabilities.embeddings)
    assert.is_true(capabilities.authentication_required)
    assert.is_false(capabilities.local_model)
  end)

  it("identifies Ollama as local and unauthenticated", function()
    local capabilities = UGLuaLLM.new("ollama", {}):capabilities()
    assert.is_true(capabilities.local_model)
    assert.is_false(capabilities.authentication_required)
    assert.is_true(capabilities.embeddings)
  end)

  it("applies custom endpoint capability overrides", function()
    local capabilities = UGLuaLLM.openai_compatible({
      base_url = "http://localhost:8000/v1",
      model = "custom",
      capabilities = { tools = false, streaming = false, models = false },
    }):capabilities()
    assert.is_false(capabilities.tools)
    assert.is_false(capabilities.streaming)
    assert.is_false(capabilities.models)
    assert.is_true(capabilities.chat)
  end)
end)
