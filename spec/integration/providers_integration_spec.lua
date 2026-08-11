-- Live coverage for the providers that had no integration spec of their own.
--
-- OpenAI, Claude and Gemini have dedicated specs with provider-specific
-- assertions. These five previously had adapters but no live verification, so
-- a broken default model or a changed response shape would only have surfaced
-- in someone's application.
--
-- Each provider is exercised through its own documented default model rather
-- than a pinned one, so a retired default shows up here rather than in a bug
-- report.
local H = require("spec.integration.helpers.integration_helper")

local providers = {
  { label = "Grok", key = "GROK_API_KEY", tools = true,
    build = function(o) return H.grok_client(o) end },
  { label = "Groq", key = "GROQ_API_KEY", tools = true,
    build = function(o) return H.groq_client(o) end },
  { label = "Mistral", key = "MISTRAL_API_KEY", tools = true,
    build = function(o) return H.mistral_client(o) end },
  { label = "DeepSeek", key = "DEEPSEEK_API_KEY", tools = true,
    build = function(o) return H.deepseek_client(o) end },
  { label = "OpenRouter", key = "OPENROUTER_API_KEY", tools = false,
    build = function(o) return H.openrouter_client(o) end },
}

-- Every normalized field carries a type contract regardless of provider.
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
  if result.provider ~= nil and type(result.provider) ~= "string" then
    error("provider should be a string, got " .. type(result.provider), 2)
  end
end

for _, provider in ipairs(providers) do
  describe(provider.label .. " integration", function()
    local function client(overrides)
      if not H.has_env(provider.key) then
        pending(provider.key .. " not set")
        return nil
      end
      return provider.build(overrides)
    end

    it("returns a normalized non-empty reply", function()
      local c = client()
      if not c then return end
      local result, err, details = c:chat({
        { role = "user", content = "Reply with the single word OK." },
      })
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(provider.label .. " unavailable: " .. reason)
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert_contract(result)
      -- A reasoning model can spend the whole output allowance thinking and
      -- stop with finish_reason "length" before emitting content. That is the
      -- model's choice, not a transport or normalization failure, so only the
      -- contract is required in that case.
      if result.finish_reason ~= "length" then
        H.assert_nonempty_string(result.text, provider.label .. " text")
      end
    end)

    it("streams text as strings and accumulates a reply", function()
      local c = client()
      if not c then return end
      local chunks = {}
      local result, err, details = c:stream_chat({
        { role = "user", content = "Count from one to five." },
      }, require("ug-lua-llm.utils.stream_helpers").content_callback(
        function(text)
          -- A leaked JSON-null sentinel would arrive here as a non-string.
          assert.are.equal("string", type(text))
          chunks[#chunks + 1] = text
        end))
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(provider.label .. " unavailable: " .. reason)
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      local joined = table.concat(chunks)
      -- The sentinel check is the point here, and it holds whether or not the
      -- model produced content within its allowance.
      assert.is_nil(joined:find("userdata", 1, true))
      assert.is_nil(joined:find("table:", 1, true))
      if result.finish_reason ~= "length" then
        assert.is_true(#joined > 0)
      end
    end)

    it("handles a multi-kilobyte request body", function()
      local c = client({ timeout = 45 })
      if not c then return end
      local result, err, details = c:chat({
        { role = "user",
          content = H.padded_prompt("Reply with the single word OK.", 4096) },
      })
      local reason = H.unavailable_reason(err, details)
      if not result and reason then
        pending(provider.label .. " unavailable: " .. reason)
        return
      end
      assert.is_nil(err)
      assert.is_not_nil(result)
      assert_contract(result)
    end)

    if provider.tools then
      it("requests a tool call", function()
        local c = client()
        if not c then return end
        local result, err, details = c:chat_with_tools({
          { role = "user", content = "What is the weather in Paris?" },
        }, { H.get_weather_tool })
        local reason = H.unavailable_reason(err, details)
        if not result and reason then
          pending(provider.label .. " unavailable: " .. reason)
          return
        end
        assert.is_nil(err)
        assert.is_not_nil(result)
        assert_contract(result)
        -- Whether the model chooses the tool is its own decision; the contract
        -- is that a normalized call is well formed when one is returned.
        local calls = require("ug-lua-llm.tools.tool").parse_tool_calls(result)
        for _, call in ipairs(calls or {}) do
          assert.are.equal("string", type(call.name))
          assert.is_not_nil(call.arguments)
        end
      end)
    end
  end)
end
