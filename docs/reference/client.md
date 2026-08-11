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
