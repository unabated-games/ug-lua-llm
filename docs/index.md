# One Lua client for every model

<div class="overview-lead">
  <p>Build LLM features in Lua without coupling your application to one vendor.
  Use the same client for OpenAI, Claude, Gemini, five other cloud adapters,
  local Ollama models, and any OpenAI-compatible server.</p>
</div>

ug-lua-llm is an open source project from
[Unabated Games](https://github.com/unabated-games).

<p class="overview-actions">
  <a class="primary-action" href="getting-started.md">Install and make a request</a>
  <a class="secondary-action" href="guides/local-ai.md">Run locally with Ollama</a>
</p>

## What you can build

<div class="feature-grid">
  <article>
    <span class="feature-kicker">One interface</span>
    <h3>Cloud and local chat</h3>
    <p>Switch between eight cloud providers, local Ollama, and custom endpoints without
    rewriting your application around each provider's response format.</p>
  </article>
  <article>
    <span class="feature-kicker">Real-time</span>
    <h3>Streaming responses</h3>
    <p>Consume normalized SSE deltas as text and tool calls arrive, with correct
    handling for fragmented events, multiline data, retries, and timeouts.</p>
  </article>
  <article>
    <span class="feature-kicker">Agentic</span>
    <h3>Tools and function calling</h3>
    <p>Define tools once with JSON Schema, normalize calls across providers, and
    use the registry to execute handlers and continue the conversation.</p>
  </article>
  <article>
    <span class="feature-kicker">Search and RAG</span>
    <h3>Embeddings</h3>
    <p>Create embeddings from strings or batches through OpenAI, Gemini,
    Mistral, Ollama, or DeepSeek using one result shape.</p>
  </article>
  <article>
    <span class="feature-kicker">No waiting</span>
    <h3>Bring any compatible model</h3>
    <p>Connect to a local server, inference gateway, or new vendor immediately.
    Supply its URL, model, optional credentials, headers, and capabilities.</p>
  </article>
  <article>
    <span class="feature-kicker">Production control</span>
    <h3>Failures you can act on</h3>
    <p>Use structured, redacted errors plus retries, rate-limit headers,
    cancellation, lifecycle hooks, request IDs, and endpoint conformance tests.</p>
  </article>
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
`deepseek`, or `mistral`. The ordinary chat contract remains the same, while
provider-native APIs stay available when your use case needs them.

## More than a lowest-common denominator

- **Normalized by default.** Read `text`, `tool_calls`, `usage`, `model`,
  `finish_reason`, and `provider` consistently while retaining the untouched
  provider response in `raw`.
- **Modern provider APIs.** Use OpenAI Responses, Gemini Interactions, Claude
  extended thinking, multimodal content, structured outputs, reasoning options,
  and safe request-option passthrough.
- **Local AI is first-class.** Ollama works without a cloud account or API key,
  with focused examples for chat, streaming, model selection, and tools.
- **Compatibility is testable.** Declare custom-server capabilities locally,
  then run the bundled conformance suite against its real models, chat, and SSE
  endpoints.
- **Lua stays broad.** The package and CI support Lua 5.1 through 5.4.

## Choose your next step

- [Install ug-lua-llm and make your first request](getting-started.md).
- [Run entirely locally with Ollama](guides/local-ai.md).
- [Compare providers and their native features](guides/providers.md).
- [Explore streaming, tools, and embeddings](reference/client.md).
- [Handle errors, retries, cancellation, and hooks](reference/errors.md).
- [Install the portable AI coding-agent skill](agents.md).

For runnable programs, see the [examples guide](../examples/README.md). For the
complete machine-readable documentation map, see
[`llms.txt`](https://github.com/unabated-games/ug-lua-llm/blob/main/llms.txt).

Contributors can preview this documentation locally with
`./scripts/serve_site.sh` from the repository root.
