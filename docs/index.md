# Documentation

<div class="docs-lead">
  <p>ug-lua-llm gives Lua applications one interface for chat, streaming,
  tools, embeddings, retries, and structured errors — while keeping
  provider-specific APIs available when you need them.</p>
</div>

<div class="docs-cards">
  <a href="#/getting-started">
    <strong>Getting started</strong>
    <span>Install the package, configure a provider, and make a first request.</span>
  </a>
  <a href="#/guides/local-ai">
    <strong>Local AI</strong>
    <span>Run entirely on Ollama, or point the client at a custom endpoint.</span>
  </a>
  <a href="#/guides/providers">
    <strong>Providers</strong>
    <span>Names, default models, key variables, and provider-native APIs.</span>
  </a>
  <a href="#/reference/client">
    <strong>Client API</strong>
    <span>Chat, streaming, tools, embeddings, and capability inspection.</span>
  </a>
  <a href="#/reference/errors">
    <strong>Errors and retries</strong>
    <span>Structured failures, lifecycle hooks, cancellation, and rate limits.</span>
  </a>
  <a href="#/examples">
    <strong>Examples</strong>
    <span>Runnable programs for chat, streaming, and tool calling.</span>
  </a>
</div>

## Start with familiar Lua

```lua
local llm = require "ug-lua-llm"

local client = llm.new("ollama", { model = "llama3.2" })
local response, err = client:chat({
  { role = "user", content = "Explain this module." },
})

assert(response, err)
print(response.text)
```

Change `ollama` to `openai`, `claude`, `gemini`, `grok`, `groq`, `openrouter`,
`deepseek`, or `mistral`. The ordinary chat contract stays the same, while
provider-native APIs remain available when your use case needs them.

## Conventions

Every operation returns `result, err, details`. Normalized responses expose
`text`, `tool_calls`, `usage`, `model`, `finish_reason`, and `provider`, and
keep the untouched provider payload in `raw`.

Never assume an OpenAI-compatible endpoint implements every capability. Declare
what a custom server supports, then verify it with the bundled conformance
runner.

## What you get

- **Normalized by default.** Read the same fields across every provider without
  losing access to the original response.
- **One schema, every provider.** Ask for structured output with `json_schema`
  and read `response.parsed`; the schema is carried in whatever shape the
  provider takes, including a forced tool call on Claude.
- **Reasoning is an option, not a dialect.** `reasoning = false` for latency,
  `"high"` for hard problems, translated per provider and reported honestly
  when a model cannot comply.
- **Modern provider APIs.** OpenAI Responses, Gemini Interactions, Claude
  extended thinking, multimodal content, structured outputs, reasoning options,
  and safe request-option passthrough.
- **Local AI is first-class.** Ollama works without a cloud account or API key,
  with focused examples for chat, streaming, model selection, and tools.
- **Compatibility is testable.** Run the conformance suite against a custom
  server's real models, chat, and SSE endpoints.
- **Lua stays broad.** The package and CI support Lua 5.1 through 5.4.

## Also here

- [AI coding agent setup](#/agents) installs the portable Agent Skill.
- [`llms.txt`](#/llms.md) and [`llms-full.txt`](#/llms-full.md) provide the
  machine-readable documentation map.
- The [source repository](https://github.com/unabated-games/ug-lua-llm) holds
  the security policy, contributing guide, and roadmap.

Contributors can preview this site locally with `./scripts/serve_site.sh` from
the repository root.
