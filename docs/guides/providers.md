# Providers

Create a client with `require("ug-lua-llm").new(name, config)`. Cloud providers
require an API key; Ollama and custom endpoints may run without one.

| Name | Service | Default model | Key environment variable |
|---|---|---|---|
| `openai` | OpenAI | `gpt-5.6-terra` | `OPENAI_API_KEY` |
| `claude` | Anthropic | `claude-sonnet-4-6` | `ANTHROPIC_API_KEY` |
| `gemini` | Google | `gemini-3.6-flash` | `GEMINI_API_KEY` |
| `grok` | xAI | `grok-4.3` | `GROK_API_KEY` |
| `groq` | Groq | `llama-3.3-70b-versatile` | `GROQ_API_KEY` |
| `openrouter` | OpenRouter | `~openai/gpt-latest` | `OPENROUTER_API_KEY` |
| `ollama` | Local Ollama | `llama3.2` | none |
| `deepseek` | DeepSeek | `deepseek-v4-flash` | `DEEPSEEK_API_KEY` |
| `mistral` | Mistral | `mistral-large-latest` | `MISTRAL_API_KEY` |
| `openai-compatible` | User-supplied server | required | optional |

Defaults are conveniences, not recommendations for every workload. Pass
`model` explicitly when reproducibility matters.

## Provider-specific APIs

- OpenAI uses the Responses API by default. Set `api = "chat_completions"` for
  compatibility, or call `client:response(input, options)` for typed Responses
  input and built-in tools.
- Gemini supports `client:interaction(input, options)` for typed multimodal and
  agentic input. Ordinary message transcripts use `client:chat`.
- Claude accepts `thinking = true`, `thinking_budget`, and a sufficiently large
  `max_tokens` value.
- OpenAI reasoning models accept `reasoning_effort`; supported modes depend on
  the selected model.

## Turning reasoning off

Use the normalized `reasoning` option. It accepts `false` (or `"none"`) to
minimize reasoning, `"low"`, `"medium"`, `"high"`, or `true` for a middling
default, and is translated into whatever the provider understands:

```lua
local response = assert(client:chat(messages, { reasoning = false }))
```

Asking for less reasoning never turns a working request into an error. Where a
model rejects the control — Groq and Mistral refuse `reasoning_effort` on models
that do not reason, and some Gemini models refuse a zero thinking budget — the
request is retried without it, and the response reports what happened:

```lua
if response.reasoning_applied == false then
  -- The reply is valid, but the model would not honour the request.
end
```

`client:capabilities().reasoning_control` says what to expect before you ask:
`"effort"`, `"budget"` (may refuse zero, so cannot always be disabled),
`"opt_in"` (off unless requested), or `false`.

`response.usage.reasoning_tokens` reports what thinking cost, so a change can be
confirmed rather than assumed.

### What each provider does underneath

Three mechanisms exist, in rough order of reliability:

**Pick a model that does not reason.** The only approach that works everywhere.
DeepSeek splits it across two models — `deepseek-chat` does not reason and
`deepseek-reasoner` does — and many Groq and Mistral models do not reason at
all. For latency-sensitive dialogue this is usually the right answer.

**Use the provider's effort control** where one exists:

```lua
-- xAI Grok: "none" genuinely disables it.
local response = assert(client:chat(messages, {
  request_options = { reasoning_effort = "none" },
}))

-- OpenAI reasoning models.
local response = assert(client:chat(messages, { reasoning_effort = "low" }))
```

Accepted values vary by model and an unsupported one is rejected with HTTP 400
rather than ignored, so treat the option as model-specific.

**Keep it opt-in.** Claude does not use extended thinking unless asked, so the
default already behaves as "off":

```lua
local response = assert(client:chat(messages, {
  thinking = true, thinking_budget = 1024, max_tokens = 2000,
}))
```

Gemini exposes a thinking budget through its own container, which reaches the
API unchanged because provider containers are merged rather than replaced:

```lua
local response = assert(client:chat(messages, {
  request_options = {
    generationConfig = { thinkingConfig = { thinkingBudget = 128 } },
  },
}))
```

Treat that budget as an influence rather than a hard cap: some models exceed
it, and some reject a budget of `0` outright because their reasoning cannot be
disabled at all. Measure before relying on it — count the tokens a response
reports as spent but not returned as text, which is the reasoning whether or
not the API names it.

## Reasoning and the output allowance

On models that reason before answering, the reasoning is spent from the same
budget as the reply. A `max_tokens` value that is comfortable for a
non-reasoning model can therefore be consumed entirely by reasoning, and the
response comes back with `finish_reason` set to `"length"` and `text` set to
`""`. Nothing failed; the model never reached the answer.

If that happens, either raise `max_tokens` or lower the reasoning effort:

```lua
local response = assert(client:chat(messages, { reasoning_effort = "low" }))
```

Accepted `reasoning_effort` values differ between models, and an unsupported
one is rejected by the provider with HTTP 400 rather than ignored. Check the
model's own documentation before setting it, and treat the option as
model-specific rather than portable.

Call `client:capabilities()` before conditionally exposing provider-specific UI.
The result is local configuration metadata, not server discovery. Use the
conformance runner for custom-server verification.
