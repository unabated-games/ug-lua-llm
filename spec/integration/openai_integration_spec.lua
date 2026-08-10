local H = require("spec.integration.helpers.integration_helper")
local json = require("ug-lua-llm.utils.json")

describe("OpenAI integration tests", function()
  local function needs(var)
    if not H.has_env(var) then pending(var .. " not set") end
  end

  describe("basic chat", function()
    it("returns a non-empty assistant message", function()
      needs("OPENAI_API_KEY")
      local client = H.openai_client()
      local messages = { { role = "user", content = "Say hello in one word." } }

      local result, err = client:chat(messages)

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.choices)
      assert.is_not_nil(result.choices[1])
      H.assert_nonempty_string(result.choices[1].message.content, "assistant content")
    end)
  end)

  describe("streaming chat", function()
    it("streams content and accumulates a response", function()
      needs("OPENAI_API_KEY")
      local client = H.openai_client()
      local messages = { { role = "user", content = "Say hello in one word." } }

      local chunks = {}
      local result = client:stream_chat(messages, function(delta, _full)
        if delta.choices and delta.choices[1] and delta.choices[1].delta
            and delta.choices[1].delta.content and delta.choices[1].delta.content ~= "" then
          table.insert(chunks, delta.choices[1].delta.content)
        end
      end)

      assert.is_not_nil(result)
      assert.is_not_nil(result.choices)
      H.assert_nonempty_string(result.choices[1].message.content, "accumulated content")
    end)
  end)

  describe("tool calling", function()
    it("invokes the get_weather tool with a location argument", function()
      needs("OPENAI_API_KEY")
      local client = H.openai_client()
      local messages = { { role = "user", content = "What is the weather in Paris?" } }

      local result, err = client:chat_with_tools(messages, { H.get_weather_tool })

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.choices)

      local tool_calls = result.choices[1].message.tool_calls
      assert.is_not_nil(tool_calls, "response should contain tool_calls")
      assert.truthy(#tool_calls > 0, "should have at least one tool call")

      local tc = tool_calls[1]
      assert.are.equal("get_weather", tc["function"].name)

      local args = json.decode(tc["function"].arguments)
      assert.is_not_nil(args.location, "arguments should contain location")
    end)
  end)

  describe("embeddings", function()
    it("returns a valid embedding vector for a single string", function()
      needs("OPENAI_API_KEY")
      local emb = H.openai_embeddings()

      local result, err = emb.embed("Hello, world!")

      assert.is_nil(err)
      H.assert_valid_embeddings(result)
    end)
  end)

  describe("reasoning (o4-mini)", function()
    it("solves a simple math problem", function()
      needs("OPENAI_API_KEY")
      local client = H.openai_client({
        model = "o4-mini",
        max_tokens = 1024,
        reasoning_effort = "low",
      })
      local messages = { { role = "user", content = "What is 23 * 47? Reply with only the number." } }

      local result, err = client:chat(messages)

      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.choices)

      local content = result.choices[1].message.content
      H.assert_nonempty_string(content, "reasoning response")
      assert.truthy(content:find("1081"), "answer should contain 1081")
    end)
  end)
end)
