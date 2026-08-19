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

describe("embeddings speak each provider's own vocabulary", function()
  local function payload_for(provider, options)
    local embeddings = LLM.Embeddings.new(provider, { api_key = "k" })
    local sent
    embeddings.http.post = function(_, _, body)
      sent = body
      return { status = 200, body = { data = { { embedding = { 0.1 }, index = 0 } } } }
    end
    embeddings:embed({ "hello" }, options)
    return sent
  end

  it("defaults to each provider's own embedding model", function()
    -- One hardcoded OpenAI name was used for every OpenAI-compatible service,
    -- so Mistral was asked for a model it has never had.
    assert.are.equal("text-embedding-3-small", payload_for("openai").model)
    assert.are.equal("mistral-embed", payload_for("mistral").model)
    assert.are.equal("nomic-embed-text", payload_for("ollama").model)
  end)

  it("spells the requested width the way each provider does", function()
    assert.are.equal(256, payload_for("openai", { dimensions = 256 }).dimensions)
    assert.are.equal(256, payload_for("mistral", { dimensions = 256 }).output_dimension)
    assert.is_nil(payload_for("mistral", { dimensions = 256 }).dimensions)
  end)

  it("sends Gemini its width per request", function()
    local embeddings = LLM.Embeddings.new("gemini", { api_key = "k" })
    local sent
    embeddings.http.post = function(_, _, body)
      sent = body
      return { status = 200, body = { embeddings = { { values = { 0.1 } } } } }
    end
    embeddings:embed({ "hello" }, { dimensions = 256 })
    assert.are.equal(256, sent.requests[1].outputDimensionality)
    assert.are.equal("models/gemini-embedding-001", sent.requests[1].model)
  end)
end)

describe("echoing a provider's own structure back to it", function()
  local ToolRegistry = require("ug-lua-llm.tools.registry")
  local JSON = require("ug-lua-llm.utils.json")

  it("marks an empty container as an array on both JSON backends", function()
    -- An empty JSON array and an empty JSON object decode to the same Lua
    -- table. Re-encoding a decoded `"summary": []` produced `{}`, and the
    -- Responses API rejects that: "expected an array of objects, but got an
    -- object instead". Dropping the key fails the other way; it is required.
    assert.are.equal('{"s":[]}', JSON.encode({ s = JSON.empty_array() }))
    -- The default for an empty table is still an object, which JSON Schema
    -- `properties` and empty tool arguments depend on.
    assert.are.equal('{"p":{}}', JSON.encode({ p = {} }))
  end)

  it("echoes the Responses output items rather than rebuilding them", function()
    -- A reasoning model returns a `reasoning` item carrying encrypted_content
    -- beside the call. Rebuilding kept only the call, so the chain of thought
    -- was discarded and re-derived from scratch every round.
    local output = {
      { type = "reasoning", id = "rs_1", encrypted_content = "ENC", summary = {} },
      { type = "function_call", call_id = "call_1", name = "f", arguments = "{}" },
    }
    local messages = ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "go" } },
      { { id = "call_1", name = "f", arguments = {}, result = { ok = true },
          result_str = '{"ok":true}' } },
      "openai", { output = output }, true)

    assert.are.equal("reasoning", messages[2].type)
    assert.are.equal("ENC", messages[2].encrypted_content)
    assert.are.equal("function_call", messages[3].type)
    assert.are.equal("function_call_output", messages[4].type)
    -- The required-but-empty field survives as an array, not an object.
    assert.are.equal('[]', JSON.encode(messages[2].summary))
    -- The call is echoed once, not echoed and rebuilt.
    assert.are.equal(4, #messages)
  end)

  it("still builds the exchange when no output items were captured", function()
    local messages = ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "go" } },
      { { id = "call_1", name = "f", arguments = {}, result_str = "{}" } },
      "openai", nil, true)
    assert.are.equal("function_call", messages[2].type)
    assert.are.equal("call_1", messages[2].call_id)
  end)
end)

describe("a streamed reply satisfies the same contract as a whole one", function()
  -- The accumulators built each provider's own shape and returned it directly,
  -- so a streamed Claude reply carried `stop_reason` instead of `finish_reason`,
  -- no `provider` -- which breaks the documented one-argument
  -- `Tool.parse_tool_calls(response)` -- and a nil `text` against a contract
  -- saying it is always a string.
  local Claude = require("ug-lua-llm.providers.claude")
  local HttpStreaming = require("ug-lua-llm.utils.http_streaming")

  local function streamed(events)
    local provider = Claude.new({ api_key = "k" })
    local original = HttpStreaming.stream_claude
    HttpStreaming.stream_claude = function(_, _, _, on_chunk)
      for _, event in ipairs(events) do on_chunk(event) end
      return true
    end
    local result = provider:stream_chat_with_tools(
      { { role = "user", content = "hi" } },
      { { name = "get_weather", description = "d",
          parameters = { type = "object", properties = {} } } },
      function() end)
    HttpStreaming.stream_claude = original
    return result
  end

  local EVENTS = {
    { type = "content_block_start", index = 0,
      content_block = { type = "text", text = "" } },
    { type = "content_block_delta", index = 0,
      delta = { type = "text_delta", text = "Looking that up." } },
    { type = "content_block_start", index = 1,
      content_block = { type = "tool_use", id = "call_1", name = "get_weather" } },
    { type = "content_block_delta", index = 1,
      delta = { type = "input_json_delta", partial_json = '{"city":' } },
    { type = "content_block_delta", index = 1,
      delta = { type = "input_json_delta", partial_json = '"Paris"}' } },
    { type = "message_delta", delta = { stop_reason = "tool_use" } },
  }

  it("normalizes provider, text and finish reason", function()
    local result = streamed(EVENTS)
    assert.are.equal("claude", result.provider)
    assert.are.equal("Looking that up.", result.text)
    assert.are.equal("tool_use", result.finish_reason)
  end)

  it("keeps the tool call reachable through the documented parser", function()
    -- parse_tool_calls infers the provider from the response, so a missing
    -- `provider` made the documented single-argument form raise.
    local result = streamed(EVENTS)
    local parsed = LLM.Tool.parse_tool_calls(result)
    assert.are.equal(1, #parsed)
    assert.are.equal("get_weather", parsed[1].name)
  end)

  it("leaves content as blocks a tool follow-up can echo", function()
    -- The follow-up sends assistant_response.content straight back to
    -- Anthropic, which requires blocks; a string would be the wrong type.
    local result = streamed(EVENTS)
    assert.is_table(result.content)
    assert.are.equal("text", result.content[1].type)
    assert.are.equal("tool_use", result.content[2].type)
  end)
end)

describe("a tool loop run against a streamed reply", function()
  -- Neither feature tests this path alone: streaming specs stop at the first
  -- turn, and tool-loop specs start from a whole response. The follow-up sends
  -- the streamed reply's `content` back to Anthropic, which requires blocks --
  -- so while the accumulator kept a string there, the loop found no tool calls
  -- and ended having run none, silently.
  local ToolRegistry = require("ug-lua-llm.tools.registry")
  local Claude = require("ug-lua-llm.providers.claude")
  local HttpStreaming = require("ug-lua-llm.utils.http_streaming")

  before_each(function()
    ToolRegistry.register("find_city", {
      description = "Find the city a landmark is in",
      parameters = { type = "object", properties = {} },
      handler = function() return { city = "Paris" } end,
    }, true)
  end)

  it("carries the streamed call into the follow-up and finishes", function()
    local provider = Claude.new({ api_key = "k" })
    local original = HttpStreaming.stream_claude
    HttpStreaming.stream_claude = function(_, _, _, on_chunk)
      on_chunk({ type = "content_block_start", index = 0,
        content_block = { type = "text", text = "" } })
      on_chunk({ type = "content_block_delta", index = 0,
        delta = { type = "text_delta", text = "Looking that up." } })
      on_chunk({ type = "content_block_start", index = 1,
        content_block = { type = "tool_use", id = "call_1", name = "find_city" } })
      on_chunk({ type = "content_block_delta", index = 1,
        delta = { type = "input_json_delta", partial_json = '{"landmark":"Eiffel"}' } })
      on_chunk({ type = "message_delta", delta = { stop_reason = "tool_use" } })
      return true
    end

    local tools = assert(ToolRegistry.collection({ "find_city" }))
    local streamed = provider:stream_chat_with_tools(
      { { role = "user", content = "where?" } }, tools, function() end)
    HttpStreaming.stream_claude = original

    assert.are.equal(1, #streamed.tool_calls)

    -- The follow-up turn must receive blocks, not a string.
    local sent
    local client = { provider = provider, config = { provider_name = "claude" } }
    client.chat_with_tools = function(_, messages)
      sent = messages
      return { text = "It is in Paris.", provider = "claude" }
    end
    client.chat = client.chat_with_tools
    client.capabilities = function() return {} end

    local final
    ToolRegistry.process_response(client, streamed,
      { { role = "user", content = "where?" } },
      function(result) final = result end, { tools = tools })

    assert.are.equal("It is in Paris.", final.text)
    assert.are.equal(1, #final.tool_results)
    assert.is_table(sent[2].content)
    assert.are.equal("tool_use", sent[2].content[2].type)
  end)
end)

describe("a schema the caller would actually write", function()
  local Structured = require("ug-lua-llm.core.structured")

  it("seals every object node, not just the root", function()
    -- OpenAI strict mode requires additionalProperties: false on every object,
    -- and rejects the schema without it. Objects inside `items` are the shape a
    -- one-level pass misses, and a list of records is exactly what a caller has.
    local spec = Structured.spec({ name = "cities", schema = {
      type = "object",
      properties = {
        cities = { type = "array", items = { type = "object",
          properties = { name = { type = "string" } } } },
      },
    } })
    assert.is_false(spec.schema.additionalProperties)
    assert.is_false(spec.schema.properties.cities.items.additionalProperties)
  end)

  it("leaves an explicit additionalProperties alone", function()
    -- Someone who wrote `true` meant it; reversing that silently is the thing
    -- this library keeps refusing to do.
    local spec = Structured.spec({ schema = {
      type = "object", additionalProperties = true, properties = {} } })
    assert.is_true(spec.schema.additionalProperties)
  end)

  it("does not seal when strict is declined", function()
    local spec = Structured.spec({ strict = false, schema = {
      type = "object", properties = { a = { type = "string" } } } })
    assert.is_nil(spec.schema.additionalProperties)
  end)

  it("does not mutate the caller's own table", function()
    local schema = { type = "object", properties = {} }
    Structured.spec({ schema = schema })
    assert.is_nil(schema.additionalProperties)
  end)

  it("follows the API in use rather than the provider's default", function()
    -- The Responses carrier writes text.format, which a Chat Completions
    -- payload never reads, so the schema was dropped and reported as applied.
    local spec = Structured.spec({ name = "answer",
      schema = { type = "object", properties = {} } })
    local attempts = Structured.attempts("openai", spec,
      { api = "chat_completions" })
    local built = attempts[1]()
    assert.is_table(built.response_format)
    assert.are.equal("json_schema", built.response_format.type)
    assert.is_nil(built.text)
  end)

  it("still uses the Responses carrier by default", function()
    local spec = Structured.spec({ name = "answer",
      schema = { type = "object", properties = {} } })
    local built = Structured.attempts("openai", spec, {})[1]()
    assert.are.equal("json_schema", built.text.format.type)
  end)
end)

describe("the Chat Completions payload carries what it is given", function()
  it("sends response_format so a schema reaches the wire", function()
    local client = LLM.new("openai",
      { api_key = "k", api = "chat_completions", max_tokens = 64 })
    local sent
    client.provider.http.post = function(_, _, payload)
      sent = payload
      return { status = 200, body = { choices = { {
        message = { content = '{"city":"Paris"}' }, finish_reason = "stop" } } } }
    end
    local result = client:chat({ { role = "user", content = "hi" } },
      { json_schema = { name = "answer", schema = { type = "object",
        properties = { city = { type = "string" } } } } })

    assert.is_table(sent.response_format)
    assert.are.equal("Paris", result.parsed.city)
    assert.is_true(result.structured_applied)
  end)
end)

describe("structured_applied cannot claim a schema that was never sent", function()
  local Structured = require("ug-lua-llm.core.structured")

  it("covers every provider with a reasoning control too", function()
    -- The sibling map. Both flags answer the same question about different
    -- ladders, so a completeness test for one without the other is the same
    -- omission that produced the defect.
    local Reasoning = require("ug-lua-llm.core.reasoning")
    for _, provider in ipairs({ "openai", "claude", "gemini", "grok", "groq",
        "openrouter", "ollama", "deepseek", "mistral", "openai-compatible" }) do
      assert.is_truthy(Reasoning.control(provider),
        provider .. " has no reasoning control entry")
    end
  end)

  it("asks each module rather than testing an index at the call site", function()
    local Reasoning = require("ug-lua-llm.core.reasoning")
    -- A provider with no carrier or control never complied, whatever rung ran.
    assert.is_false(Structured.applied("nosuchprovider", 1))
    assert.is_false(Reasoning.applied("nosuchprovider", 1))
    assert.is_true(Structured.applied("openai", 1))
    assert.is_true(Reasoning.applied("openai", 1))
    -- And a later rung is a degradation on both.
    assert.is_false(Structured.applied("openai", 2))
    assert.is_false(Reasoning.applied("openai", 2))
  end)

  it("covers every provider the library can construct", function()
    -- The flag was derived from the rung index alone, which reads correctly
    -- while every provider is in the format map. A provider missing from it has
    -- one attempt -- the unchanged one -- so rung 1 carries no schema, and the
    -- caller is told their schema was honoured by a request without it. This
    -- keeps the map's completeness from being the only thing holding that off.
    for _, provider in ipairs({ "openai", "claude", "gemini", "grok", "groq",
        "openrouter", "ollama", "deepseek", "mistral", "openai-compatible" }) do
      assert.is_truthy(Structured.format(provider),
        provider .. " has no structured-output carrier")
    end
  end)

  it("reports false when no carrier resolved", function()
    local real = Structured.format
    Structured.format = function(name)
      if name == "openai" then return false end
      return real(name)
    end

    local client = LLM.new("openai", { api_key = "k", api = "chat_completions" })
    client.provider.http.post = function()
      return { status = 200, body = { choices = { {
        message = { content = "hi" }, finish_reason = "stop" } } } }
    end
    local result = client:chat({ { role = "user", content = "hi" } },
      { json_schema = { name = "a", schema = { type = "object", properties = {} } } })

    Structured.format = real
    assert.is_false(result.structured_applied)
  end)
end)

describe("completion routing follows what the endpoints actually serve", function()
  -- The rule was an allow-list of chat-only models, written when /completions
  -- served most of them. A model absent from it went to the legacy endpoint, so
  -- everything released since failed with "This is a chat model and not
  -- supported in the v1/completions endpoint". Correct when written, and able
  -- to rot in only one direction.
  local function endpoint_for(model, method)
    local client = LLM.new("openai",
      { api_key = "k", api = "chat_completions", model = model, max_tokens = 32 })
    local seen
    client.provider.http.post = function(_, url)
      seen = url
      return { status = 200, body = { choices = { {
        message = { content = "ok" }, text = "ok", finish_reason = "stop" } } } }
    end
    method(client)
    return seen
  end

  local complete = function(c) c:complete("hi") end

  it("sends an unknown model to the endpoint that serves everything", function()
    assert.is_truthy(endpoint_for("gpt-5.6-terra", complete):find("/chat/completions"))
    assert.is_truthy(endpoint_for("a-model-released-tomorrow", complete)
      :find("/chat/completions"))
  end)

  it("still uses the legacy endpoint for what it serves", function()
    local url = endpoint_for("gpt-3.5-turbo-instruct", complete)
    assert.is_truthy(url:find("/completions"))
    assert.is_nil(url:find("/chat/completions"))
  end)

  it("gives stream_complete deltas the documented fields", function()
    -- Every streaming callback is documented to expose content and text; this
    -- one emitted only the completion-shaped `choices` entry.
    local client = LLM.new("openai",
      { api_key = "k", api = "chat_completions", model = "gpt-4o-mini" })
    local seen
    client.provider.stream_chat = function(_, _, callback)
      callback({ choices = { { index = 0, delta = { content = "ok" },
        finish_reason = nil } } }, {})
      return { text = "ok" }
    end
    client:stream_complete("hi", function(delta) seen = delta end)
    assert.are.equal("ok", seen.content)
    assert.are.equal("ok", seen.text)
    assert.are.equal("ok", seen.choices[1].text)
  end)
end)
