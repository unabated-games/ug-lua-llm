local H = require("spec.integration.helpers.integration_helper")

describe("Claude integration tests", function()
  local function needs(var)
    if not H.has_env(var) then pending(var .. " not set") end
  end

  describe("basic chat", function()
    it("returns a non-empty assistant message", function()
      needs("ANTHROPIC_API_KEY")
      local client = H.claude_client()
      local messages = { { role = "user", content = "Say hello in one word." } }

      local result, err = client:chat(messages)

      if H.is_account_problem(err) then
        pending("Claude account unavailable: " .. tostring(err))
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.content)
      assert.truthy(#result.content > 0, "content array should not be empty")
      assert.are.equal("text", result.content[1].type)
      H.assert_nonempty_string(result.content[1].text, "assistant text")
    end)
  end)

  describe("streaming chat", function()
    it("streams content and accumulates a response", function()
      needs("ANTHROPIC_API_KEY")
      local client = H.claude_client()
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
      needs("ANTHROPIC_API_KEY")
      local client = H.claude_client()
      local messages = { { role = "user", content = "What is the weather in Paris?" } }

      local result, err = client:chat_with_tools(messages, { H.get_weather_tool })

      if H.is_account_problem(err) then
        pending("Claude account unavailable: " .. tostring(err))
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.are.equal("tool_use", result.stop_reason)
      assert.is_not_nil(result.content)

      local tool_use = nil
      for _, block in ipairs(result.content) do
        if block.type == "tool_use" then
          tool_use = block
          break
        end
      end

      assert.is_not_nil(tool_use, "response should contain a tool_use block")
      assert.are.equal("get_weather", tool_use.name)
      assert.is_not_nil(tool_use.input, "tool_use should have input")
      assert.is_not_nil(tool_use.input.location, "input should contain location")
    end)
  end)

  describe("extended thinking", function()
    it("solves a simple math problem with thinking enabled", function()
      needs("ANTHROPIC_API_KEY")
      local client = H.claude_client({
        max_tokens = 2048,
      })
      local messages = { { role = "user", content = "What is 23 * 47? Reply with only the number." } }

      local result, err = client:chat(messages, {
        thinking = true,
        thinking_budget = 1024,
      })

      if H.is_account_problem(err) then
        pending("Claude account unavailable: " .. tostring(err))
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert.is_not_nil(result.content)
      assert.truthy(#result.content > 0, "content array should not be empty")

      -- Find the text block (there may also be a thinking block)
      local text = ""
      for _, block in ipairs(result.content) do
        if block.type == "text" then
          text = text .. block.text
        end
      end

      H.assert_nonempty_string(text, "thinking response text")
      assert.truthy(text:find("1081"), "answer should contain 1081")
    end)
  end)
end)
