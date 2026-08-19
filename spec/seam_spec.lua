-- Composition tests: provider parsing and Response.normalize, run together,
-- asserting only what a caller actually receives.
--
-- The module specs cover each half alone. That is where a whole class of defect
-- hid: a field written under one name by a provider and read under another by
-- the normalizer is correct on both sides of the seam and broken across it.
-- Gemini's usage was reported as `prompt_tokens` and read as
-- `total_input_tokens`; its `thoughtsTokenCount` was dropped before the
-- normalizer that looks for it ever ran; a blocked prompt returned without
-- normalizing at all, leaving `text` nil. Each had a passing unit test.
--
-- These assert the normalized contract instead: `text` is always a string,
-- `provider` is always set, usage is reported under the normalized names, and
-- tool calls survive in the shape callers are told to expect.
local LLM = require("ug-lua-llm")

local function client_returning(provider, config, body)
  config = config or {}
  config.api_key = config.api_key or "test-key"
  local client = LLM.new(provider, config)
  client.provider.http.post = function()
    return { status = 200, body = body }
  end
  return client
end

local function chat(provider, config, body)
  local client = client_returning(provider, config, body)
  local response, err = client:chat({ { role = "user", content = "hi" } })
  assert(response, err)
  return response
end

-- One tool call and one line of text, in each service's own wire shape.
local BODIES = {
  {
    name = "openai (responses)", provider = "openai", config = {},
    body = {
      status = "completed",
      model = "gpt-test",
      output = {
        -- Real replies lead with a reasoning item the caller never sees. It is
        -- here because it is on the wire, not because anything reads it: an
        -- extractor that took output[1] on faith would return its contents as
        -- the answer.
        { type = "reasoning", id = "rs_1", encrypted_content = "gAAAAAB..." },
        { type = "message", content = { { type = "output_text", text = "hello" } } },
        { type = "function_call", call_id = "call_1", name = "f", arguments = '{"a":1}' },
      },
      usage = {
        input_tokens = 5, output_tokens = 7, total_tokens = 12,
        input_tokens_details = { cached_tokens = 0 },
      },
    },
    finish_reason = "tool_calls",
  },
  {
    name = "openai (chat completions)", provider = "openai",
    config = { api = "chat_completions" },
    body = {
      model = "gpt-test",
      choices = { {
        message = { content = "hello", tool_calls = { {
          id = "call_1", type = "function",
          ["function"] = { name = "f", arguments = '{"a":1}' },
        } } },
        finish_reason = "stop",
      } },
      usage = { prompt_tokens = 5, completion_tokens = 7, total_tokens = 12 },
    },
    finish_reason = "stop",
  },
  {
    name = "claude", provider = "claude", config = {},
    body = {
      model = "claude-test",
      content = {
        { type = "text", text = "hello" },
        { type = "tool_use", id = "call_1", name = "f", input = { a = 1 } },
      },
      stop_reason = "end_turn",
      usage = { input_tokens = 5, output_tokens = 7 },
    },
    finish_reason = "end_turn",
  },
  {
    name = "gemini", provider = "gemini", config = {},
    body = {
      modelVersion = "gemini-test",
      candidates = { {
        content = { parts = {
          { text = "hello" },
          { functionCall = { name = "f", args = { a = 1 } } },
        } },
        finishReason = "STOP",
      } },
      usageMetadata = {
        promptTokenCount = 5, candidatesTokenCount = 7, totalTokenCount = 12,
      },
    },
    finish_reason = "STOP",
  },
}

-- Every OpenAI-compatible service shares one wire shape but its own adapter.
for _, provider in ipairs({ "grok", "groq", "deepseek", "mistral", "openrouter",
    "ollama" }) do
  BODIES[#BODIES + 1] = {
    name = provider, provider = provider, config = {},
    body = {
      model = "m",
      choices = { {
        message = { content = "hello", tool_calls = { {
          id = "call_1", type = "function",
          ["function"] = { name = "f", arguments = '{"a":1}' },
        } } },
        finish_reason = "stop",
      } },
      usage = { prompt_tokens = 5, completion_tokens = 7, total_tokens = 12 },
    },
    finish_reason = "stop",
  }
end

describe("provider parsing composed with normalization", function()
  for _, case in ipairs(BODIES) do
    describe(case.name, function()
      it("normalizes text, provider, and finish reason", function()
        local response = chat(case.provider, case.config, case.body)
        assert.are.equal("hello", response.text)
        assert.are.equal(case.provider, response.provider)
        assert.are.equal(case.finish_reason, response.finish_reason)
      end)

      it("reports usage under the normalized names", function()
        local response = chat(case.provider, case.config, case.body)
        assert.is_table(response.usage)
        assert.are.equal(5, response.usage.prompt_tokens)
        assert.are.equal(7, response.usage.completion_tokens)
        assert.are.equal(12, response.usage.total_tokens)
      end)

      it("surfaces the tool call the model asked for", function()
        local response = chat(case.provider, case.config, case.body)
        assert.is_table(response.tool_calls)
        assert.are.equal(1, #response.tool_calls)
        local parsed = LLM.Tool.parse_tool_calls(response)
        assert.are.equal("f", parsed[1].name)
        assert.are.same({ a = 1 }, parsed[1].arguments)
      end)
    end)
  end
end)

describe("normalized contract on empty and truncated replies", function()
  -- A model that stops before emitting content is the case where a leaked
  -- sentinel or a nil is most likely, and least likely to be guarded against.
  local cases = {
    { "openai", { api = "chat_completions" },
      { choices = { { message = { content = nil }, finish_reason = "length" } },
        usage = { prompt_tokens = 5, completion_tokens = 0, total_tokens = 5 } },
      "length" },
    { "claude", {},
      { content = {}, stop_reason = "max_tokens",
        usage = { input_tokens = 5, output_tokens = 0 } }, "max_tokens" },
    { "gemini", {},
      { candidates = { { content = {}, finishReason = "MAX_TOKENS" } },
        usageMetadata = { promptTokenCount = 5, candidatesTokenCount = 0,
          totalTokenCount = 5 } }, "MAX_TOKENS" },
  }

  for _, case in ipairs(cases) do
    it("gives " .. case[1] .. " an empty string rather than nil", function()
      local response = chat(case[1], case[2], case[3])
      assert.are.equal("string", type(response.text))
      assert.are.equal("", response.text)
      assert.are.equal(case[4], response.finish_reason)
      assert.is_nil(response.tool_calls)
    end)
  end
end)

describe("reasoning token reporting across the seam", function()
  it("uses Gemini's explicit thought count rather than deriving it", function()
    -- thoughtsTokenCount was dropped when the provider rebuilt usage from three
    -- fields, so the count had to be inferred from the gap between the total
    -- and its parts -- and vanished whenever the total excluded it.
    local response = chat("gemini", {}, {
      candidates = { { content = { parts = { { text = "x" } } },
        finishReason = "STOP" } },
      usageMetadata = {
        promptTokenCount = 5, candidatesTokenCount = 20, totalTokenCount = 25,
        thoughtsTokenCount = 15,
      },
    })
    assert.are.equal(15, response.usage.reasoning_tokens)
  end)

  it("keeps the provider's own usage fields reachable", function()
    local response = chat("gemini", {}, {
      candidates = { { content = { parts = { { text = "x" } } },
        finishReason = "STOP" } },
      usageMetadata = {
        promptTokenCount = 5, candidatesTokenCount = 20, totalTokenCount = 40,
        thoughtsTokenCount = 15, cachedContentTokenCount = 3,
      },
    })
    assert.are.equal(15, response.usage.raw.thoughtsTokenCount)
    assert.are.equal(3, response.usage.raw.cachedContentTokenCount)
  end)

  it("reports an OpenAI reasoning count from its own details block", function()
    local response = chat("openai", {}, {
      status = "completed",
      output = { { type = "message",
        content = { { type = "output_text", text = "x" } } } },
      usage = { input_tokens = 5, output_tokens = 20, total_tokens = 25,
        output_tokens_details = { reasoning_tokens = 15 } },
    })
    assert.are.equal(15, response.usage.reasoning_tokens)
  end)
end)

describe("tool follow-up turns keep what the provider signed", function()
  local ToolRegistry = require("ug-lua-llm.tools.registry")

  local function follow_up(provider, assistant_response)
    return ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "hi" } },
      { { id = "call_252", name = "find_city", result = { city = "Paris" },
          result_str = '{"city":"Paris"}', arguments = { landmark = "Eiffel Tower" } } },
      provider, assistant_response, false)
  end

  it("echoes Gemini's own parts rather than rebuilding them", function()
    -- Gemini 3.x signs each functionCall with a thoughtSignature and rejects a
    -- follow-up that replays the call without it: "Function call is missing a
    -- thought_signature in functionCall parts." Rebuilding the part from name
    -- and args dropped the signature and ended every exchange at one round.
    local parts = { {
      thoughtSignature = "SIGNED",
      functionCall = { id = "call_252", name = "find_city",
        args = { landmark = "Eiffel Tower" } },
    } }
    local messages = follow_up("gemini", { parts = parts })

    local model_turn = messages[2]
    assert.are.equal("assistant", model_turn.role)
    assert.are.equal("SIGNED", model_turn.content[1].thoughtSignature)
    assert.are.equal("find_city", model_turn.content[1].functionCall.name)

    -- The result correlates on the id the model issued, not a synthesized one.
    local result_turn = messages[3]
    assert.are.equal("call_252", result_turn.content[1].functionResponse.id)
    assert.are.same({ city = "Paris" },
      result_turn.content[1].functionResponse.response)
  end)

  it("omits an id Gemini never issued", function()
    -- Older models send no id, so the library synthesizes one for internal
    -- correlation. Echoing that back would reference a call Gemini never made.
    local messages = follow_up("gemini", { parts = { {
      functionCall = { name = "find_city", args = { landmark = "Eiffel Tower" } },
    } } })
    assert.is_nil(messages[3].content[1].functionResponse.id)
  end)

  it("still builds a turn when no parts were captured", function()
    local messages = follow_up("gemini", {})
    assert.are.equal("find_city", messages[2].content[1].functionCall.name)
  end)

  it("preserves Claude's original tool_use blocks", function()
    local blocks = { { type = "tool_use", id = "call_252", name = "find_city",
      input = { landmark = "Eiffel Tower" } } }
    local messages = follow_up("claude", { content = blocks })
    assert.are.same(blocks, messages[2].content)
    assert.are.equal("call_252", messages[3].content[1].tool_use_id)
  end)
end)

describe("a failed tool is reported as failed, not as content", function()
  local ToolRegistry = require("ug-lua-llm.tools.registry")

  local function blocks(ok)
    local messages = ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "hi" } },
      { { id = "call_1", name = "t", result_str = '{"error":"no such city"}',
          arguments = {}, ok = ok, error = (not ok) and "no such city" or nil } },
      "claude", { content = {} }, false)
    return messages[#messages].content[1]
  end

  it("flags a failure on Anthropic's tool_result block", function()
    assert.is_true(blocks(false).is_error)
  end)

  it("leaves a successful result unflagged", function()
    -- Present and false is not the same as absent; Anthropic treats the flag's
    -- presence as meaningful, so a success must not carry it at all.
    assert.is_nil(blocks(true).is_error)
  end)
end)

describe("a schema carried as a tool cannot also carry the caller's tools", function()
  local tools = { { name = "find_city", description = "d",
    parameters = { type = "object", properties = {} } } }
  local schema = { name = "answer", schema = { type = "object",
    properties = { city = { type = "string" } } } }

  it("reports the conflict on Claude instead of a missing tool", function()
    -- Claude has no response-format field, so the schema is a forced tool call.
    -- The provider used to reject it as "Tool 'answer' not found in provided
    -- tools", which sends the caller hunting for a registration bug.
    local client = LLM.new("claude", { api_key = "k" })
    local result, err, details = client:chat_with_tools(
      { { role = "user", content = "hi" } }, tools, { json_schema = schema })

    assert.is_nil(result)
    assert.is_truthy(err:find("forced tool call", 1, true))
    assert.are.equal("schema_tool_conflict", details.code)
  end)

  it("leaves providers with a real response format alone", function()
    -- OpenAI and Gemini carry the schema beside the tools, so the combination
    -- is the model's choice to make rather than a contradiction.
    local client = LLM.new("openai", { api_key = "k" })
    client.provider.http.post = function()
      return { status = 200, body = { status = "completed", output = {
        { type = "message", content = { { type = "output_text", text = "{}" } } } } } }
    end
    local result = client:chat_with_tools(
      { { role = "user", content = "hi" } }, tools, { json_schema = schema })
    assert.is_table(result)
  end)

  it("still allows a schema with no tools", function()
    local client = LLM.new("claude", { api_key = "k" })
    client.provider.http.post = function()
      return { status = 200, body = { content = { { type = "text", text = "hi" } },
        stop_reason = "end_turn" } }
    end
    assert.is_table(client:chat({ { role = "user", content = "hi" } },
      { json_schema = schema }))
  end)
end)

describe("reasoning means the same thing on the escape hatch", function()
  -- `client:response` takes the provider's own typed input, but `reasoning` is
  -- this library's option and had been passed straight through. The Responses
  -- API wants an object, so a caller moving a working `reasoning = "high"` from
  -- chat to the escape hatch got "Invalid type for 'reasoning': expected an
  -- object, but got a string instead".
  local function payload_for(options)
    local client = LLM.new("openai", { api_key = "k", max_tokens = 64 })
    local sent
    client.provider.http.post = function(_, _, body)
      sent = body
      return { status = 200, body = { status = "completed", output = {} } }
    end
    client:response({ { role = "user", content = "hi" } }, options)
    return sent
  end

  it("translates a normalized level into the object the API takes", function()
    assert.are.same({ effort = "high" }, payload_for({ reasoning = "high" }).reasoning)
  end)

  it("translates the boolean forms too", function()
    assert.are.same({ effort = "none" }, payload_for({ reasoning = false }).reasoning)
    assert.are.same({ effort = "medium" }, payload_for({ reasoning = true }).reasoning)
  end)

  it("leaves a caller's own object alone", function()
    local reasoning = { effort = "low", summary = "auto" }
    assert.are.same(reasoning, payload_for({ reasoning = reasoning }).reasoning)
  end)

  it("sends nothing when nothing was asked for", function()
    assert.is_nil(payload_for({}).reasoning)
  end)
end)

describe("tool_choice reaches every provider in its own spelling", function()
  local tools = { { name = "get_time", description = "d",
    parameters = { type = "object", properties = {} } } }

  local function payload_for(provider, choice, body)
    local client = LLM.new(provider, { api_key = "k", max_tokens = 64 })
    local sent
    client.provider.http.post = function(_, _, p)
      sent = p
      return { status = 200, body = body }
    end
    client:chat_with_tools({ { role = "user", content = "hi" } }, tools,
      { tool_choice = choice })
    return sent
  end

  local CLAUDE = { content = { { type = "text", text = "x" } }, stop_reason = "end_turn" }
  local GEMINI = { candidates = { { content = { parts = { { text = "x" } } },
    finishReason = "STOP" } } }

  it("translates Claude's object form", function()
    -- Nothing translated this, so tool_choice never reached the payload and a
    -- caller forbidding tool use had tools called anyway.
    assert.are.same({ type = "none" }, payload_for("claude", "none", CLAUDE).tool_choice)
    assert.are.same({ type = "any" }, payload_for("claude", "required", CLAUDE).tool_choice)
    assert.are.same({ type = "tool", name = "get_time" },
      payload_for("claude", { name = "get_time" }, CLAUDE).tool_choice)
  end)

  it("translates Gemini's nested toolConfig", function()
    assert.are.same({ functionCallingConfig = { mode = "NONE" } },
      payload_for("gemini", "none", GEMINI).toolConfig)
    assert.are.same({ functionCallingConfig = { mode = "ANY",
      allowedFunctionNames = { "get_time" } } },
      payload_for("gemini", { name = "get_time" }, GEMINI).toolConfig)
  end)

  it("leaves an unrecognized choice out rather than guessing", function()
    assert.is_nil(payload_for("claude", "nonsense", CLAUDE).tool_choice)
    assert.is_nil(payload_for("gemini", "nonsense", GEMINI).toolConfig)
  end)
end)

describe("a library option nested in request_options", function()
  local function attempt(request_options)
    local client = LLM.new("openai", { api_key = "k", max_tokens = 64 })
    client.provider.http.post = function(_, _, sent)
      return { status = 200, body = { status = "completed", output = {},
        _sent = sent } }
    end
    return client:chat({ { role = "user", content = "hi" } },
      { request_options = request_options })
  end

  it("is refused rather than forwarded raw", function()
    -- request_options reaches the provider untouched, which is what makes a
    -- name this library also owns dangerous inside it: the ladder consumes the
    -- top-level one, so a nested copy is forwarded and the provider rejects a
    -- parameter the caller was told to use.
    local result, err, details = attempt({ reasoning = "high" })
    assert.is_nil(result)
    assert.are.equal("library_option_in_request_options", details.code)
    assert.is_truthy(err:find("request_options", 1, true))
  end)

  it("lets a provider's own object shape through", function()
    -- An object is this provider's vocabulary, not ours, so the caller means it.
    assert.is_table(attempt({ reasoning = { effort = "high" } }))
  end)

  it("does not interfere with ordinary passthrough", function()
    assert.is_table(attempt({ top_p = 0.5 }))
  end)
end)
