-- Live checks for the behaviour that unit and fake-server tests can only
-- approximate: real endpoints, real TLS, real multi-kilobyte request bodies.
--
-- lua-http adds "Expect: 100-continue" above 1024 bytes and several providers
-- never answer it, so a request that works at smoke-test size stalls at
-- realistic size. These run against whichever providers have credentials.
local H = require("spec.integration.helpers.integration_helper")

local SIZES = { 1025, 4096, 16384 }

local function assert_normalized(result)
  -- The normalized contract: text is always a string, never a JSON-null
  -- sentinel from the active backend.
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

local providers = {
  {
    label = "OpenAI",
    key = "OPENAI_API_KEY",
    build = function(overrides) return H.openai_client(overrides) end,
  },
  {
    label = "OpenRouter",
    key = "OPENROUTER_API_KEY",
    build = function(overrides) return H.openrouter_client(overrides) end,
  },
  {
    label = "Claude",
    key = "ANTHROPIC_API_KEY",
    build = function(overrides) return H.claude_client(overrides) end,
  },
}

describe("large request bodies against live providers", function()
  for _, provider in ipairs(providers) do
    describe(provider.label, function()
      for _, size in ipairs(SIZES) do
        it("completes a " .. size .. "-byte prompt", function()
          if not H.has_env(provider.key) then
            pending(provider.key .. " not set")
            return
          end
          local client = provider.build({ timeout = 45 })
          local prompt = H.padded_prompt("Reply with the single word OK.", size)
          local started = os.time()
          local result, err, details = client:chat({
            { role = "user", content = prompt },
          })
          if not result and H.is_account_problem(err, details) then
            pending(provider.label .. " account unavailable: " .. tostring(err))
            return
          end
          assert.is_nil(err)
          assert.is_not_nil(result)
          assert_normalized(result)
          -- A stalled expectation shows up as a timeout, not a slow reply.
          assert.is_true(os.time() - started < 45)
        end)
      end

      it("streams a large prompt", function()
        if not H.has_env(provider.key) then
          pending(provider.key .. " not set")
          return
        end
        local client = provider.build({ timeout = 45 })
        local chunks = {}
        local result, err, details = client:stream_chat({
          { role = "user", content = H.padded_prompt("Count to three.", 4096) },
        }, require("ug-lua-llm.utils.stream_helpers").content_callback(
          function(text)
            assert.are.equal("string", type(text))
            chunks[#chunks + 1] = text
          end))
        if not result and H.is_account_problem(err, details) then
          pending(provider.label .. " account unavailable: " .. tostring(err))
          return
        end
        assert.is_nil(err)
        assert.is_not_nil(result)
        local joined = table.concat(chunks)
        -- A leaked backend sentinel would show up here as literal text.
        assert.is_nil(joined:find("userdata", 1, true))
        assert.is_nil(joined:find("table:", 1, true))
      end)
    end)
  end
end)

describe("output-limit responses stay within the normalized contract", function()
  it("returns a string when a model exhausts its output allowance", function()
    if not H.has_env("OPENROUTER_API_KEY") then
      pending("OPENROUTER_API_KEY not set")
      return
    end
    -- A very small allowance makes a reasoning-capable model likely to stop
    -- with finish_reason "length" and null content.
    local client = H.openrouter_client({ max_tokens = 16, timeout = 45 })
    local result, err, details = client:chat({
      { role = "user",
        content = H.padded_prompt("Explain quantum computing in depth.", 2048) },
    })
    if not result and H.is_account_problem(err, details) then
      pending("OpenRouter account unavailable: " .. tostring(err))
      return
    end
    assert.is_nil(err)
    assert.is_not_nil(result)
    assert_normalized(result)
    if result.finish_reason == "length" then
      -- The case that previously surfaced a userdata value.
      assert.are.equal("string", type(result.text))
    end
  end)
end)
