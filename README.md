# ug-lua-llm

[![CI](https://github.com/unabated-games/ug-lua-llm/actions/workflows/ci.yml/badge.svg)](https://github.com/unabated-games/ug-lua-llm/actions/workflows/ci.yml)
[![Lua 5.1–5.4](https://img.shields.io/badge/Lua-5.1–5.4-2c2d72)](https://www.lua.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-16a34a.svg)](LICENSE)

A unified Lua client for cloud LLM APIs, local Ollama models, and arbitrary
OpenAI-compatible endpoints.

An open source project from [Unabated Games](https://github.com/unabated-games).

ug-lua-llm gives Lua applications one interface for chat, streaming, tools,
embeddings, retries, and structured errors—while keeping provider-specific APIs
available when you need them.

```lua
local llm = require "ug-lua-llm"

local client = llm.new("ollama", { model = "llama3.2" })
local response, err = client:chat({
  { role = "user", content = "Why is Lua a good embedding language?" },
})

assert(response, err)
print(response.text)
```

## Why ug-lua-llm?

- One normalized API across OpenAI, Claude, Gemini, Grok, Groq, OpenRouter,
  Ollama, DeepSeek, Mistral, and custom endpoints.
- Local-first development through Ollama, without a cloud key.
- Real SSE streaming, normalized tool calls, embeddings, and provider-native
  escape hatches.
- Structured, redacted errors plus retries, cancellation, lifecycle hooks, and
  endpoint conformance checks.
- Tested on Lua 5.1, 5.2, 5.3, and 5.4.

## Install

```sh
luarocks install ug-lua-llm
```

To work against the source, or to try an unreleased change, install from a
checkout instead:

```sh
git clone https://github.com/unabated-games/ug-lua-llm.git
cd ug-lua-llm
luarocks make ug-lua-llm-0.3.0-1.rockspec
```

> On Homebrew, use the versioned `lua@5.4` formula. The unversioned formula
> targets Lua 5.5, which is not yet supported by ug-lua-llm's transport dependency
> chain. See the [installation guide](docs/getting-started.md) for exact setup
> and diagnostics.

## Choose a provider

```lua
local client = require("ug-lua-llm").new("claude", {
  api_key = os.getenv("ANTHROPIC_API_KEY"),
  model = "claude-sonnet-4-6",
})
```

| Provider name | Service | Authentication |
|---|---|---|
| `openai` | OpenAI | API key |
| `claude` | Anthropic Claude | API key |
| `gemini` | Google Gemini | API key |
| `grok` | xAI | API key |
| `groq` | Groq | API key |
| `openrouter` | OpenRouter | API key |
| `ollama` | Local Ollama | Optional |
| `deepseek` | DeepSeek | API key |
| `mistral` | Mistral | API key |
| `openai-compatible` | Your server or gateway | Optional |

Model defaults evolve; pass `model` explicitly when reproducibility matters.
See [Providers](docs/guides/providers.md) for defaults and special APIs.

## Bring your own endpoint

You do not need to wait for a named adapter when a service implements OpenAI
Chat Completions:

```lua
local client = require("ug-lua-llm").openai_compatible({
  base_url = "http://localhost:8000/v1",
  model = "my-model",
  api_key = os.getenv("LLM_API_KEY"), -- optional
  capabilities = {
    streaming = true,
    tools = false,
    models = true,
  },
})
```

Capabilities vary by server and model. The bundled conformance runner checks
model listing, chat, and real SSE behavior against your configured endpoint.

## Documentation

- [Getting started](docs/getting-started.md)
- [Local AI and custom endpoints](docs/guides/local-ai.md)
- [Provider guide](docs/guides/providers.md)
- [Client API](docs/reference/client.md)
- [Errors, retries, and observability](docs/reference/errors.md)
- [Runnable examples](examples/README.md)
- [AI coding agent setup](docs/agents.md)
- [LLM documentation index](llms.txt)
- [Changelog](CHANGELOG.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Development

```sh
busted --exclude-pattern="integration"
sh scripts/run_e2e.sh
luacheck ug-lua-llm/ spec/ scripts/
```

Unit tests and deterministic localhost transport tests require no API keys.
Integration tests contact real providers and skip those without credentials.

Run everything worth checking before a release in one step:

```sh
sh scripts/run_release_checks.sh          # no credentials needed
sh scripts/run_release_checks.sh --live   # adds real provider calls
```

That covers the unit suite under both JSON backends, lint, the end-to-end
transport tests, version consistency, and the rockspec. `--live` adds
multi-kilobyte requests against every provider with a key in `.env`; providers
without credentials, or with an account that cannot serve the request, are
reported as pending rather than failures.

Preview the documentation website from any repository directory with:

```sh
./scripts/serve_site.sh
```

## License

ug-lua-llm is available under the [MIT License](LICENSE).
