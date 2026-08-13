# Changelog

Notable changes to ug-lua-llm. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **The documented embeddings example did not run.**
  `Embeddings.new("openai", { api_key = ... })` failed while building the
  request URL, because no provider supplied a default `base_url` even though
  the client for the same provider had one. Every embeddings provider now
  defaults its own endpoint, so Ollama needs no configuration at all.
- **`embeddings:embed(input)` passed the wrong argument.** The documentation
  and the agent reference both use a colon, matching `client:chat`, but the
  object was dot-only, so a colon call sent the embeddings object as the input
  and failed while encoding the request. Both forms now work.

### Changed

- The embeddings object exposes `http` and `config`, so its transport can be
  replaced the same way a provider's can.

### Documentation

- `llms.txt` and `llms-full.txt` described the pre-LuaRocks install and did not
  mention the response contract, JSON-null handling, `request_options` merging,
  or reasoning. Agents reading them were being pointed at a source checkout.

## [0.1.1] - 2026-08-11

A correctness release. Every change is a fix; there are no API removals and no
behaviour anyone should have been relying on has changed.

**If you are on 0.1.0, upgrade.** Any request whose body exceeds 1 KiB — which
is most realistic prompts — could hang until your own timeout fired.

### Fixed

- **Requests larger than 1 KiB could hang.** lua-http adds an
  `Expect: 100-continue` header to bodies over 1024 bytes. Endpoints that never
  send the interim `100` response left the client waiting, and one that replied
  with a final response instead caused the request body to be dropped entirely.
  Small prompts succeeded while realistic ones stalled, which pointed diagnosis
  away from the transport. Both the regular and streaming paths are fixed.
- **Configured timeouts did not cover the response body.** The timeout applied
  to connection and headers only, so a server that sent headers and then stopped
  writing could block indefinitely. A failed body read was also mistaken for an
  empty body, reporting a *successful* response with no content; it is now a
  transport error.
- **JSON `null` could escape as a backend sentinel.** A decoded null is truthy
  in Lua, so it won `value or ""` fallbacks and surfaced as lua-cjson's light
  userdata or dkjson's table. `response.text` is now always a string,
  `finish_reason` a string or `nil`, and `tool_calls` a table or `nil`. This
  also affected streaming: the previous filter compared against the text
  `"userdata: (nil)"`, which never matched on many platforms, so an
  OpenAI-compatible stream — which opens with `{"content": null}` — could emit a
  literal sentinel into accumulated text and content callbacks. A `null` text
  block in a Claude response previously aborted with a `table.concat` error.
- **`Tool.parse_tool_calls(response)` crashed.** The documented single-argument
  form raised `attempt to concatenate a nil value`. The provider is now inferred
  from the normalized response; passing it explicitly still takes precedence.
- **`request_options` could not extend a provider's option containers.** Whole
  keys were overwritten, so anything set inside a generated container was
  silently discarded. Gemini's `generationConfig` meant `thinkingConfig` was
  unreachable, leaving no way to influence reasoning. Nested objects now merge,
  with generated values still winning so required protocol fields cannot be
  replaced. Arrays are still replaced wholesale.
- **`examples/.env.example` named the wrong variable for Anthropic.** It asked
  for `CLAUDE_API_KEY`, but the client, `doctor`, and the documentation all read
  `ANTHROPIC_API_KEY`, so following the example file left Claude unconfigured.
  Keys for the remaining providers were also missing from the file.

### Added

- `JSON.is_null(value)`, `JSON.value(value)`, and `JSON.string_value(value)` for
  callers inspecting the untouched provider payload in `raw`, where JSON `null`
  is preserved as the backend's sentinel and is truthy.
- Documentation for the normalized response contract, and for controlling
  reasoning: there is no portable switch, so the guide covers what each
  mechanism can and cannot do.

## [0.1.0] - 2026-08-11

Initial public release. A unified Lua 5.1–5.4 client for cloud LLM APIs, local
Ollama models, and any OpenAI-compatible endpoint, with chat, streaming, tool
calling, embeddings, retries, and structured errors behind one normalized API.

[Unreleased]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/unabated-games/ug-lua-llm/releases/tag/v0.1.0
