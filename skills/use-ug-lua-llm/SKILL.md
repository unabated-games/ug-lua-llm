---
name: use-ug-lua-llm
description: Build, update, debug, or review Lua applications that use the ug-lua-llm library with OpenAI, Claude, Gemini, Ollama, other built-in providers, or custom OpenAI-compatible endpoints. Use for client setup, chat, streaming, tool calling, embeddings, capability checks, error handling, local AI, provider selection, and ug-lua-llm installation problems.
---

# Use ug-lua-llm

## Workflow

1. Inspect the target project's Lua version, dependency declaration, existing
   ug-lua-llm usage, and provider configuration.
2. Read [references/api.md](references/api.md) before writing or changing calls.
3. Choose a named provider for supported services. Choose
   `openai_compatible` for a user-supplied server or gateway and `ollama` for a
   local Ollama instance.
4. Preserve `result, err, details` handling and normalized response fields.
5. Keep credentials in environment variables. Never print keys, authorization
   headers, `.env` contents, or unredacted secret-bearing payloads.
6. Check `client:capabilities()` before conditionally using optional features.
7. Add a focused test or runnable example appropriate to the change. Avoid live
   provider calls unless the user explicitly wants integration verification.

## Implementation defaults

- Prefer `response.text` over parsing provider-specific response bodies.
- Preserve `response.raw` when exposing provider-native data.
- Use the normalized `reasoning` and `json_schema` options rather than a
  provider's own dialect. Both degrade rather than fail, so check
  `response.reasoning_applied` and `response.structured_applied` before
  treating the request as honoured.
- Pass tools back into `ToolRegistry.process_response` as `options.tools` so a
  model can request a second tool after seeing the first result.
- Pass `model` explicitly when reproducibility matters.
- Keep `/v1` on common Ollama and OpenAI-compatible base URLs.
- Do not assume an OpenAI-compatible endpoint supports streaming, tools,
  models, vision, or structured output.
- Use `lua scripts/doctor.lua` from a checkout when Lua cannot find installed
  rocks. Align Lua and LuaRocks versions before changing application code.

For full project documentation, consult `docs/index.md` or `llms-full.txt` when
working in the ug-lua-llm repository.
