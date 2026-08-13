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

Structured error details may contain `kind`, `provider`, `status`, `code`,
`retryable`, safe headers, and a sanitized body. Set lifecycle hooks with
`on_request`, `on_retry`, `on_response`, and `on_error`. Set custom retry logic
with `retry_predicate` and `backoff`; cancellation uses a function or shared
`{ cancelled = boolean }` token.

Embeddings use `llm.Embeddings.new(provider, config):embed(input, options)` and
support OpenAI, Gemini, Mistral, Ollama, and DeepSeek. Each provider supplies
its own default `base_url`, so only a key (and, for Ollama, not even that) is
required.

Reasoning is spent from the output allowance, so a small `max_tokens` can be
consumed before content appears. There is no portable way to disable it:
choose a non-reasoning model, or use a provider's own control, such as
`reasoning_effort` (model-specific values, rejected with HTTP 400 when
unsupported) or Claude's opt-in `thinking = true`. Provider-specific request
fields go in `request_options`, whose nested containers are merged into the
generated payload rather than replacing it.
