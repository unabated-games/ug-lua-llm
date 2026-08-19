# Client API

## Construction

```lua
local llm = require "ug-lua-llm"
local client = llm.new(provider, config)
local custom = llm.openai_compatible(config)
```

Common configuration includes `api_key`, `model`, `base_url`, `headers`,
`temperature`, `max_tokens`, `timeout`, `retries`, `retry_delay`, and
`request_options`. Configuration may be overridden per call.

## Methods

| Method | Purpose |
|---|---|
| `chat(messages, options)` | Generate from a message transcript |
| `complete(prompt, options)` | Generate from a text prompt |
| `stream_chat(messages, callback, options)` | Stream normalized chat deltas |
| `stream_complete(prompt, callback, options)` | Stream completion deltas |
| `chat_with_tools(messages, tools, options)` | Request tool calls |
| `stream_chat_with_tools(...)` | Stream text and tool-call deltas |
| `list_models(options)` | List models, following pagination by default |
| `capabilities()` | Inspect locally configured features |
| `response(input, options)` | Use OpenAI Responses where supported |
| `interaction(input, options)` | Use Gemini Interactions where supported |

## The normalized response contract

`response.text` is always a string. When a provider returns JSON `null` for the
content — which happens when a model stops before producing any, such as on an
exhausted output allowance — `text` is `""` rather than the JSON backend's null
sentinel. Check `finish_reason` to tell an empty answer apart from a truncated
one:

```lua
local response = assert(client:chat(messages))
if response.text == "" and response.finish_reason == "length" then
  -- The model ran out of output allowance before emitting content.
end
```

`finish_reason` is a string or `nil`, and `tool_calls` is a table or `nil`;
neither ever holds a null sentinel. The untouched provider payload stays in
`raw`, where JSON `null` is preserved exactly as the backend decoded it. To
inspect it safely, compare against the sentinel rather than testing
truthiness, because a decoded null is truthy in Lua:

```lua
local JSON = require "ug-lua-llm.utils.json"
if JSON.is_null(response.raw.choices[1].message.content) then
  -- The provider explicitly sent null.
end
```

`JSON.value(x)` returns `nil` for a null sentinel and the value otherwise, which
makes ordinary `or` fallbacks safe against `raw`.

## Tool loops

`ToolRegistry.process_response` runs tool calls and continues the conversation
until the model stops asking for tools. Pass the tools through so the model can
request a second one after seeing the first result:

```lua
local Registry = require "ug-lua-llm.tools.registry"

-- The bundled tools are opt-in; register your own with Registry.register.
Registry.register_standard_tools()
local tools = assert(Registry.collection({ "get_weather", "calculator" }))

local first = assert(client:chat_with_tools(messages, tools))
Registry.process_response(client, first, messages, function(final, err)
  if not final then error(err) end
  print(final.text)
end, { tools = tools, max_tool_rounds = 8 })
```

Without `tools`, the follow-up cannot request anything further, so the exchange
ends after one round. `max_tool_rounds` bounds a model that keeps asking for the
same tool; when the cap is reached the response carries
`tool_rounds_exhausted = true` rather than being passed off as complete.

The final response describes the whole exchange, not just the turn that
answered — which asked for no tools, and so would otherwise report none:

| Field | What it holds |
|---|---|
| `tool_calls` | Every call the model requested, across every round |
| `tool_results` | Every call that ran, each with `result`, `ok`, and `error` |
| `tool_rounds` | How many rounds were taken |
| `tool_pending` | Calls the round cap stopped before they ran |
| `messages` | The conversation as it now stands, ready to continue |

Pass `on_tool` to watch each dispatch as it happens:

```lua
Registry.process_response(client, first, messages, function(final, err)
  if not final then error(err) end
  print(final.text)
  print(#final.tool_calls .. " calls over " .. final.tool_rounds .. " rounds")
end, {
  tools = tools,
  max_tool_rounds = 8,
  on_tool = function(record)
    print(record.name .. " -> " .. record.result_str)
  end,
})
```

`max_tool_rounds = 0` is meaningful: the model gets one turn, whatever it asks
for is reported, and nothing runs. The caller's own `messages` table is never
mutated.

Follow-up turns preserve whatever the provider used to link a call to its
result: Claude's original `tool_use` blocks, and Gemini's own parts including
the `thoughtSignature` it signs each `functionCall` with. A turn rebuilt from
the tool's name and arguments loses that linkage and is rejected.

`ToolRegistry.register_standard_tools()` is required before `get_weather` and
`calculator` resolve. They were registered when the module loaded before 0.3.0,
which gave every consumer tools they never defined; `Registry.collection` now
reports `Tool 'name' not found in registry` if you ask for one without opting
in first.

## Structured output

Pass a JSON Schema as `json_schema` and read the decoded result from `parsed`:

```lua
local response = assert(client:chat(messages, {
  json_schema = {
    name = "answer",
    schema = {
      type = "object",
      properties = { answer = { type = "integer" } },
      required = { "answer" },
    },
  },
}))

print(response.parsed.answer)  -- decoded
print(response.text)           -- the raw JSON document
```

One schema works everywhere. It is carried as a flattened `text.format` on the
OpenAI Responses API, as `response_format.json_schema` on Chat Completions
services, as `generationConfig.responseSchema` on Gemini, and as a forced tool
call on Claude, which has no response-format field. Gemini accepts only a
restricted subset of JSON Schema, so unsupported keywords such as
`additionalProperties` are removed rather than passed through and rejected.

A model that refuses a schema falls back to plain JSON mode, and then to an
ordinary reply, so the request still succeeds. Check before trusting the shape:

```lua
if response.structured_applied then
  -- The schema was enforced by the provider.
end
```

### Choosing which tool runs

`tool_choice` takes `"auto"`, `"required"` (or `"any"`), `"none"`, or a table
naming one tool. Every provider spells this differently and the option is
translated for each: a bare string on OpenAI-compatible services,
`{ type = ... }` on Claude, and `toolConfig.functionCallingConfig` on Gemini,
where naming a tool becomes `allowedFunctionNames`.

```lua
client:chat_with_tools(messages, tools, { tool_choice = "required" })
client:chat_with_tools(messages, tools, { tool_choice = { name = "get_weather" } })
client:chat_with_tools(messages, tools, { tool_choice = "none" })
```

`"none"` forbids tool use for that turn, which is worth stating because it is
the case where a silently dropped option does the opposite of what was asked.
A value no provider recognizes is left out rather than guessed at.

### Schemas and tools together

The two do not always compose, and how they fail depends on where the provider
puts the schema.

On Claude there is no response-format field, so the schema *is* a forced tool
call. Asking for both is a contradiction — the model cannot be compelled to
call the schema tool and left free to choose among yours — and it is reported
as a validation error with `code = "schema_tool_conflict"` rather than sent.
Ask for the schema in a follow-up call once the tool exchange has finished.

Elsewhere the schema travels beside the tools and the model chooses. A model
that answers with a tool call has not produced a JSON document, so `parsed` is
`nil` even where `structured_applied` is true — the schema was carried, and the
model simply did something else with its turn. **Read `parsed` rather than
`structured_applied` when tools are also in play.**

`client:capabilities().structured_output` reports the carrier: `"responses"`,
`"chat"`, `"schema"`, `"tool"`, or `false`.

## Reasoning

`reasoning` accepts `false`/`"none"`, `"low"`, `"medium"`, `"high"`, or `true`.
See the [provider guide](../guides/providers.md) for what each provider can
actually honour, `response.reasoning_applied` for whether it did — a boolean
when you asked for a level, `nil` when you did not — and
`response.usage.reasoning_tokens` for what it cost.

## Streaming

```lua
local ok, err = client:stream_chat(messages, function(delta, full)
  io.write(delta.content or delta.text or "")
  io.flush()
end)
```

Deltas normalize `content`, `text`, `tool_calls`, `finish_reason`, `provider`,
and `raw` where available. Streaming falls back to a regular request when SSE
is unavailable unless disabled for conformance testing.

## Tools

Tool definitions use JSON Schema:

```lua
local tools = {{
  name = "get_weather",
  description = "Get weather for a location",
  parameters = {
    type = "object",
    properties = { location = { type = "string" } },
    required = { "location" },
  },
}}

local response = assert(client:chat_with_tools(messages, tools))
for _, call in ipairs(require("ug-lua-llm").Tool.parse_tool_calls(response)) do
  print(call.name, call.arguments.location)
end
```

Use `UGLuaLLM.ToolRegistry` to register handlers and execute tool loops. Parsed
calls have `{ id, name, arguments, type, raw }`; malformed JSON arguments are
preserved rather than silently discarded.

## Embeddings

```lua
local embeddings = require("ug-lua-llm").Embeddings.new("openai", {
  api_key = os.getenv("OPENAI_API_KEY"),
})
local result = assert(embeddings:embed({ "first", "second" }))
```

Embeddings are available for OpenAI, Gemini, Mistral, Ollama, and DeepSeek.
