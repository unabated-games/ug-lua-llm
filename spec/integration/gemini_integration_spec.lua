local H = require("spec.integration.helpers.integration_helper")
local json = require("ug-lua-llm.utils.json")

describe("Gemini integration tests", function()
  local function needs(var)
    if not H.has_env(var) then pending(var .. " not set") end
  end

  describe("basic chat", function()
    it("returns a non-empty response", function()
      needs("GEMINI_API_KEY")
      local client = H.gemini_client()
      local messages = { { role = "user", content = "Say hello in one word." } }

      local result, err = client:chat(messages)

      assert.is_nil(err)
      assert.is_not_nil(result)
      H.assert_nonempty_string(result.content, "response content")
    end)
  end)

  describe("streaming chat", function()
    it("streams content and accumulates a response", function()
      needs("GEMINI_API_KEY")
      local client = H.gemini_client()
      local messages = { { role = "user", content = "Say hello in one word." } }

      local chunks = {}
      local result = client:stream_chat(messages, function(delta, _full)
        if delta.content and delta.content ~= "" then
          table.insert(chunks, delta.content)
        end
      end)

      assert.is_not_nil(result)
      H.assert_nonempty_string(result.content, "accumulated content")
    end)
  end)

  describe("tool calling", function()
    it("invokes the get_weather tool with a location argument", function()
      needs("GEMINI_API_KEY")
      local client = H.gemini_client()
      local messages = { { role = "user", content = "What is the weather in Paris?" } }

      local result, err = client:chat_with_tools(messages, { H.get_weather_tool })

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.tool_calls, "response should contain tool_calls")
      assert.truthy(#result.tool_calls > 0, "should have at least one tool call")

      local tc = result.tool_calls[1]
      assert.are.equal("get_weather", tc["function"].name)

      local args = json.decode(tc["function"].arguments)
      assert.is_not_nil(args.location, "arguments should contain location")
    end)
  end)

  describe("embeddings", function()
    it("returns a valid embedding vector for a single string", function()
      needs("GEMINI_API_KEY")
      local emb = H.gemini_embeddings()

      local result, err = emb.embed("Hello, world!")

      assert.is_nil(err)
      H.assert_valid_embeddings(result)
    end)
  end)
end)
