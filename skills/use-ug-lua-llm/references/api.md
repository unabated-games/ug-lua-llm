# ug-lua-llm compact API reference

Import with `local llm = require "ug-lua-llm"`.

Create built-in clients with `llm.new(provider, config)`. Provider names are
`openai`, `claude`, `gemini`, `grok`, `groq`, `openrouter`, `ollama`,
`deepseek`, and `mistral`. Cloud providers require `api_key`; Ollama does not.

Create custom clients with:

```lua
local client = llm.openai_compatible({
  base_url = "http://localhost:8000/v1",
  model = "my-model",
  api_key = os.getenv("LLM_API_KEY"), -- optional
  headers = {},
  capabilities = { streaming = true, tools = false, models = true },
})
```

Common methods are `chat`, `complete`, `chat_with_tools`, `stream_chat`,
`stream_complete`, `stream_chat_with_tools`, `list_models`, and
`capabilities`. OpenAI additionally supports `response`; Gemini supports
`interaction`.

Messages contain `role` and `content`. Every operation returns
`result, err, details`. Normalized responses expose `text`, `tool_calls`,
`usage`, `model`, `finish_reason`, `provider`, and `raw` where available.

`text` is always a string, never nil and never a JSON-null sentinel. A model
that stops before producing content returns `""` with `finish_reason` `"length"`,
so check `finish_reason` to tell an empty answer from a truncated one. `raw`
keeps the provider payload untouched, where JSON null survives as a truthy
sentinel: test it with `require("ug-lua-llm.utils.json").is_null(value)`.

Streaming callbacks receive `(delta, full)`; consume `delta.content` or
`delta.text`. Tools use `{ name, description, parameters = <JSON Schema> }`.
Parse calls with `llm.Tool.parse_tool_calls(response)` or use
`llm.ToolRegistry` for registered handlers.

`ToolRegistry.process_response(client, response, messages, callback, options)`
runs the handlers and continues until the model stops asking for tools. Pass
the tools back in as `options.tools`, or the follow-up cannot request anything
and the exchange ends after one round; `options.max_tool_rounds` (default 8)
bounds a model that keeps asking, and the response then carries
`tool_rounds_exhausted = true`. The bundled `get_weather` and `calculator` are
opt-in as of 0.3.0 — call `ToolRegistry.register_standard_tools()` first or
`Registry.collection` reports them as not found.

Structured error details may contain `kind`, `provider`, `status`, `code`,
`retryable`, safe headers, and a sanitized body. Set lifecycle hooks with
`on_request`, `on_retry`, `on_response`, and `on_error`. Set custom retry logic
with `retry_predicate` and `backoff`; cancellation uses a function or shared
`{ cancelled = boolean }` token.

Embeddings use `llm.Embeddings.new(provider, config):embed(input, options)` and
support OpenAI, Gemini, Mistral, Ollama, and DeepSeek. Each provider supplies
its own default `base_url`, so only a key (and, for Ollama, not even that) is
required.

Control reasoning with the `reasoning` option: `false` or `"none"` to minimize,
`"low"`, `"medium"`, `"high"`, or `true`. It is translated per provider — an
effort string, a token budget, or an opt-in block — so do not write
`reasoning_effort` or `thinking` by hand. Asking for less never turns a working
request into an error: a provider that refuses the control is retried without
it. `response.reasoning_applied` is a boolean whenever a level was asked for
and `nil` when it was not, so check it rather than assuming compliance;
`response.usage.reasoning_tokens` reports the cost, and
`client:capabilities().reasoning_control` returns `"effort"`, `"budget"` (may
refuse a zero budget), `"opt_in"`, or `false` before a request is made.
Reasoning is spent from the output allowance, so a small `max_tokens` can be
consumed before content appears.

Get structured output with `json_schema` and read `response.parsed`; the raw
JSON document stays in `response.text`. One schema covers every provider —
carried as `text.format`, `response_format.json_schema`,
`generationConfig.responseSchema`, or a forced tool call on Claude, which has
no response-format field. Gemini accepts only a restricted subset of JSON
Schema, so unsupported keywords are stripped rather than rejected. A refused
schema falls back to plain JSON mode and then to an ordinary reply, so check
`response.structured_applied` before trusting the shape.
`client:capabilities().structured_output` names the carrier.

Provider-specific request fields go in `request_options`, whose nested
containers are merged into the generated payload rather than replacing it.
