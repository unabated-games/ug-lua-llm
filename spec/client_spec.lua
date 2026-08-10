local Client = require("ug-lua-llm.core.client")

describe("Client", function()
  -- Create a minimal mock provider
  local function mock_provider()
    return {
      complete = function(self, prompt, opts)
        return { text = "completed: " .. prompt, opts = opts }
      end,
      chat = function(self, messages, opts)
        return { content = "chat response", messages = messages, opts = opts }
      end,
      chat_with_tools = function(self, messages, tools, opts)
        return { content = "tool response", tools = tools, opts = opts }
      end,
      stream_complete = function(self, prompt, callback, opts)
        callback({ text = prompt }, { text = prompt })
        return { text = prompt }
      end,
      stream_chat = function(self, messages, callback, opts)
        callback({ content = "hi" }, { content = "hi" })
        return { content = "hi" }
      end,
      stream_chat_with_tools = function(self, messages, tools, callback, opts)
        callback({ content = "tool" }, { content = "tool" })
        return { content = "tool" }
      end,
      list_models = function(self)
        return { { id = "model-1" } }
      end,
    }
  end

  describe("new", function()
    it("creates a client with provider and config", function()
      local client = Client.new(mock_provider(), { temperature = 0.5 })
      assert.is_not_nil(client.provider)
      assert.are.equal(0.5, client.config.temperature)
    end)
  end)

  describe("complete", function()
    it("delegates to provider", function()
      local client = Client.new(mock_provider(), {})
      local result = client:complete("hello")
      assert.are.equal("completed: hello", result.text)
    end)
  end)

  describe("chat", function()
    it("delegates to provider", function()
      local client = Client.new(mock_provider(), {})
      local msgs = { { role = "user", content = "hi" } }
      local result = client:chat(msgs)
      assert.are.equal("chat response", result.content)
    end)
  end)

  describe("chat_with_tools", function()
    it("delegates to provider", function()
      local client = Client.new(mock_provider(), {})
      local result = client:chat_with_tools({}, { { name = "test" } })
      assert.are.equal("tool response", result.content)
    end)
  end)

  describe("list_models", function()
    it("delegates to provider", function()
      local client = Client.new(mock_provider(), {})
      local models = client:list_models()
      assert.are.equal(1, #models)
      assert.are.equal("model-1", models[1].id)
    end)
  end)

  describe("stream_chat", function()
    it("delegates to provider and calls callback", function()
      local client = Client.new(mock_provider(), {})
      local called = false
      client:stream_chat({}, function(delta, full)
        called = true
        assert.are.equal("hi", delta.content)
      end)
      assert.is_true(called)
    end)
  end)
end)
