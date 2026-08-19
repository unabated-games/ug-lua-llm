-- Regressions for defects found while porting the library to another runtime.
-- Each was visible in the source rather than in a failing test, which is why
-- they survived: the behaviour was wrong but nothing asserted otherwise.
local Response = require("ug-lua-llm.core.response")
local Tool = require("ug-lua-llm.tools.tool")
local Embeddings = require("ug-lua-llm.core.embeddings")
local GeminiProvider = require("ug-lua-llm.providers.gemini")
local mock = require("spec.helpers.mock_http")

describe("Gemini usage normalization", function()
  it("populates usage from the provider's own field names", function()
    -- The provider emits prompt/completion names while the reader wanted
    -- total_input_tokens, so the branch never fired and usage stayed empty.
    local result = Response.normalize("gemini", {
      content = "hi",
      usage = { prompt_tokens = 17, completion_tokens = 3, total_tokens = 156 },
    })
    assert.is_not_nil(result.usage)
    assert.are.equal(17, result.usage.prompt_tokens)
    assert.are.equal(3, result.usage.completion_tokens)
    assert.are.equal(156, result.usage.total_tokens)
    -- 156 - 17 - 3 is the thinking nobody was being shown.
    assert.are.equal(136, result.usage.reasoning_tokens)
  end)

  it("still accepts the Interactions naming", function()
    local result = Response.normalize("gemini", {
      content = "hi",
      usage = { total_input_tokens = 5, total_output_tokens = 2, total_tokens = 7 },
    })
    assert.are.equal(5, result.usage.prompt_tokens)
  end)
end)

describe("Gemini system instructions", function()
  local function instruction_for(messages)
    local provider = setmetatable({ config = {} }, { __index = GeminiProvider })
    local _, system_instruction = provider:_format_contents(messages)
    return system_instruction
  end

  it("joins every system message instead of keeping the last", function()
    local system_instruction = instruction_for({
      { role = "system", content = "First rule." },
      { role = "system", content = "Second rule." },
      { role = "user", content = "hello" },
    })
    local text = system_instruction.parts[1].text
    assert.matches("First rule.", text, 1, true)
    assert.matches("Second rule.", text, 1, true)
  end)

  it("returns nothing when there is no system message", function()
    assert.is_nil(instruction_for({ { role = "user", content = "hi" } }))
  end)
end)

describe("Gemini blocked prompts", function()
  it("normalizes a refusal instead of returning the raw body", function()
    -- Gemini answers 200 with promptFeedback and no candidates.
    local provider = setmetatable({ config = {} }, { __index = GeminiProvider })
    local result = provider:_format_response({
      promptFeedback = { blockReason = "SAFETY", safetyRatings = {} },
      modelVersion = "gemini-3.6-flash",
    })
    assert.are.equal("", result.content)
    assert.is_true(result.blocked)
    assert.are.equal("SAFETY", result.block_reason)
    assert.are.equal("content_filter", result.finish_reason)
  end)
end)

describe("Claude tool schemas", function()
  it("carries the caller's whole schema, not just properties and required", function()
    local out = Tool.to_claude_format({ {
      name = "t", description = "d",
      parameters = {
        type = "object",
        properties = { a = { type = "string", description = "keep me" } },
        required = { "a" },
        additionalProperties = false,
        ["$defs"] = { X = { type = "string" } },
      },
    } })
    local schema = out[1].input_schema
    assert.is_false(schema.additionalProperties)
    assert.is_not_nil(schema["$defs"])
    assert.are.equal("keep me", schema.properties.a.description)
    assert.are.same({ "a" }, schema.required)
  end)

  it("omits an empty required list rather than encoding it as an object", function()
    -- An empty Lua table encodes as {}, the wrong JSON type for a list, which
    -- strict validators reject.
    local out = Tool.to_claude_format({ {
      name = "t", description = "d",
      parameters = { type = "object", properties = {}, required = {} },
    } })
    assert.is_nil(out[1].input_schema.required)
  end)
end)

describe("Embedding order", function()
  it("pairs vectors by reported index, not arrival order", function()
    -- The API documents that results may come back out of order, so a caller
    -- pairing embeddings[i] with inputs[i] would get the wrong vector.
    local emb = Embeddings.new("openai", { api_key = "sk-test" })
    mock.reset()
    mock.inject(emb)
    mock.set_default({ status = 200, body = { data = {
      { index = 2, embedding = { 0.3 } },
      { index = 0, embedding = { 0.1 } },
      { index = 1, embedding = { 0.2 } },
    } } })

    local result = assert(emb:embed({ "a", "b", "c" }))
    assert.are.equal(0, result.embeddings[1].index)
    assert.are.equal(1, result.embeddings[2].index)
    assert.are.equal(2, result.embeddings[3].index)
    assert.are.equal(0.1, result.embeddings[1].embedding[1])
    assert.are.equal(0.3, result.embeddings[3].embedding[1])
  end)
end)

describe("Groq default model", function()
  it("is one the service still serves", function()
    -- A retired default fails only for users who did not set a model, which is
    -- the newest users, and it fails on their very first call.
    local provider = require("ug-lua-llm.providers.groq").new({ api_key = "k" })
    assert.are_not.equal("llama-3.3-70b-versatile", provider.config.model)
    assert.are.equal("openai/gpt-oss-20b", provider.config.model)
  end)
end)

describe("Tool loop", function()
  local ToolRegistry = require("ug-lua-llm.tools.registry")

  -- A client that returns a scripted sequence of responses, recording calls.
  local function scripted_client(responses)
    local calls = 0
    return {
      calls = function() return calls end,
      provider = { config = { provider_name = "openai" } },
      chat = function(_, messages, options)
        calls = calls + 1
        local next_response = responses[calls + 1]
        if next_response == nil then return { text = "done", provider = "openai" } end
        return next_response
      end,
    }
  end

  local function tool_response(name, id)
    return {
      provider = "openai",
      tool_calls = { { id = id, type = "function",
        ["function"] = { name = name, arguments = "{}" } } },
    }
  end

  before_each(function()
    ToolRegistry.register("step_one", {
      description = "first", parameters = { type = "object", properties = {} },
      handler = function() return { ok = 1 } end,
    }, true)
    ToolRegistry.register("step_two", {
      description = "second", parameters = { type = "object", properties = {} },
      handler = function() return { ok = 2 } end,
    }, true)
  end)

  it("keeps going when the model asks for a second tool", function()
    -- Look up a city, then look up its weather. Returning after one round meant
    -- the second request was never made and the conversation simply stopped.
    local client = scripted_client({
      [2] = tool_response("step_two", "call_2"),
      [3] = { text = "final answer", provider = "openai" },
    })
    local final
    ToolRegistry.process_response(client, tool_response("step_one", "call_1"),
      { { role = "user", content = "go" } }, function(response) final = response end)

    assert.is_not_nil(final)
    assert.are.equal("final answer", final.text)
    assert.are.equal(2, client.calls())
  end)

  it("stops at the round cap instead of looping forever", function()
    -- A model that keeps asking for the same tool must terminate.
    local client = {
      provider = { config = { provider_name = "openai" } },
      chat = function() return tool_response("step_one", "call_n") end,
    }
    local final
    ToolRegistry.process_response(client, tool_response("step_one", "call_1"),
      { { role = "user", content = "go" } },
      function(response) final = response end, { max_tool_rounds = 3 })

    assert.is_not_nil(final)
    assert.is_true(final.tool_rounds_exhausted)
    assert.are.equal(3, final.tool_rounds)
  end)

  it("surfaces a failed follow-up rather than returning nothing", function()
    local client = {
      provider = { config = { provider_name = "openai" } },
      chat = function() return nil, "rate limited", { status = 429 } end,
    }
    local seen_response, seen_err = "unset", nil
    ToolRegistry.process_response(client, tool_response("step_one", "call_1"),
      { { role = "user", content = "go" } },
      function(response, err) seen_response, seen_err = response, err end)

    assert.is_nil(seen_response)
    assert.are.equal("rate limited", seen_err)
  end)

  it("passes a response through untouched when no tools are requested", function()
    local client = scripted_client({})
    local final
    ToolRegistry.process_response(client, { text = "plain", provider = "openai" },
      {}, function(response) final = response end)
    assert.are.equal("plain", final.text)
    assert.are.equal(0, client.calls())
  end)
end)

describe("OpenAI request shape", function()
  local Config = require("ug-lua-llm.core.config")
  local OpenAIProvider = require("ug-lua-llm.providers.openai")

  local function payload_for(config, options)
    config.api_key = config.api_key or "sk-test"
    local provider = OpenAIProvider.new(config)
    return provider:_build_chat_payload({ { role = "user", content = "hi" } },
      Config.merge(provider.config, options or {}))
  end

  it("uses the parameter Chat Completions actually takes", function()
    -- Current models reject max_tokens outright. The old rule guessed from the
    -- model name (^o%d) and stopped matching once the naming changed.
    local payload = payload_for({ model = "gpt-5.6-terra", max_tokens = 32 })
    assert.are.equal(32, payload.max_completion_tokens)
    assert.is_nil(payload.max_tokens)
  end)

  it("does not force a temperature the caller never chose", function()
    -- Several current models accept only their own default and reject any
    -- explicit value, so sending the library default failed the request.
    local payload = payload_for({ model = "gpt-5.6-terra", max_tokens = 32 })
    assert.is_nil(payload.temperature)
  end)

  it("still sends a temperature the caller did choose", function()
    local payload = payload_for({ model = "gpt-4o-mini", temperature = 0.2 })
    assert.are.equal(0.2, payload.temperature)
  end)

  it("sends a temperature chosen per call", function()
    local payload = payload_for({ model = "gpt-4o-mini" }, { temperature = 0.5 })
    assert.are.equal(0.5, payload.temperature)
  end)
end)

describe("Config explicit tracking", function()
  local Config = require("ug-lua-llm.core.config")

  it("separates caller values from defaults", function()
    local config = Config.new({ api_key = "k", max_tokens = 32 })
    assert.is_true(Config.is_explicit(config, "max_tokens"))
    assert.is_false(Config.is_explicit(config, "temperature"))
  end)

  it("survives being wrapped again on the way through the stack", function()
    -- Config.new runs once in the entry point, once in the provider and once
    -- in the client. Recomputing from a resolved config would mark every
    -- default as a deliberate choice.
    local config = Config.new({ api_key = "k", max_tokens = 32 })
    for _ = 1, 3 do config = Config.new(config) end
    assert.is_false(Config.is_explicit(config, "temperature"))
    assert.is_true(Config.is_explicit(config, "max_tokens"))
  end)

  it("marks per-call overrides as explicit", function()
    local merged = Config.merge(Config.new({ api_key = "k" }), { temperature = 0.2 })
    assert.is_true(Config.is_explicit(merged, "temperature"))
  end)
end)

describe("Tool follow-up wire shape", function()
  local ToolRegistry = require("ug-lua-llm.tools.registry")

  local results = { { id = "call_1", name = "t", arguments = { a = 1 },
                      result = { ok = true }, result_str = '{"ok":true}' } }

  it("uses typed items for the Responses API", function()
    -- Sending the Chat Completions shape was rejected with "Unknown parameter:
    -- input[N].tool_calls", so the follow-up never succeeded and OpenAI tool
    -- calling produced no final answer at all.
    local messages = ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "go" } }, results, "openai", nil, true)
    local call, output = messages[2], messages[3]
    assert.are.equal("function_call", call.type)
    assert.are.equal("call_1", call.call_id)
    assert.are.equal("function_call_output", output.type)
    assert.are.equal('{"ok":true}', output.output)
  end)

  it("keeps the Chat Completions shape when that API is in use", function()
    local messages = ToolRegistry._prepare_tool_response_messages(
      { { role = "user", content = "go" } }, results, "openai", nil, false)
    assert.are.equal("assistant", messages[2].role)
    assert.is_not_nil(messages[2].tool_calls)
    -- Absent content is rejected by the Responses API and tolerated here; an
    -- empty string satisfies both.
    assert.are.equal("", messages[2].content)
  end)

  it("detects the Responses API from the client's configuration", function()
    local responses_client = { provider = { config = { provider_name = "openai" } } }
    assert.is_true(ToolRegistry._uses_responses_api(responses_client, "openai", {}))
    assert.is_false(ToolRegistry._uses_responses_api(
      responses_client, "openai", { api = "chat_completions" }))
    assert.is_false(ToolRegistry._uses_responses_api(responses_client, "claude", {}))
  end)
end)
