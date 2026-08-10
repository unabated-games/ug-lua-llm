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

Call `client:capabilities()` before conditionally exposing provider-specific UI.
The result is local configuration metadata, not server discovery. Use the
conformance runner for custom-server verification.
