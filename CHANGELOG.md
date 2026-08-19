# Changelog

Notable changes to ug-lua-llm. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-08-19

Defects found by a team porting the library to another runtime, who read every
module closely and re-derived its behaviour. Most were visible in the source
rather than in a failing test, which is why they survived: the behaviour was
wrong but nothing asserted otherwise.

**Two of these broke a documented feature outright.** Groq's default model no
longer exists, so any client that did not set one failed on its first call, and
OpenAI tool calling never produced a final answer.

### Fixed

- **Groq's default model had been retired.** A client created without an
  explicit model failed with `The model llama-3.3-70b-versatile does not exist`.
  The default is now `openai/gpt-oss-20b`. Defaults age out silently and only
  fail for users who did not set one, which is the newest users.
- **OpenAI tool calling never completed.** The follow-up request after a tool
  ran was built in the Chat Completions shape and sent to the Responses API,
  which is the default, and was rejected with `Unknown parameter:
  input[N].tool_calls`. No final answer was ever produced, and the failure was
  silent: the callback received `nil` with no error. Tool exchanges now use the
  typed `function_call` and `function_call_output` items that API takes.
- **Tool calling ran exactly one round.** A model that needed a second tool
  after seeing the first result never got the chance, because the follow-up was
  made without tools and the loop ended after one pass. It now runs to
  completion, bounded by `max_tool_rounds` (default 8), re-offering the tools
  when they are supplied via `options.tools`. A failed follow-up is reported
  rather than returned as `nil`.
- **The Chat Completions escape hatch was unusable on current models.** It sent
  `max_tokens`, which they reject in favour of `max_completion_tokens`, and it
  forced the library's default `temperature` onto every request, which several
  models also reject. A temperature is now sent only when the caller chose one.
- **Gemini token usage was never populated.** The provider emitted
  `prompt_tokens` while the normalizer looked for `total_input_tokens`, so the
  branch never fired. Both namings are now accepted.
- **Gemini discarded all but the last system message.** A plain assignment
  inside the message loop overwrote each previous one without warning. They are
  now joined.
- **A blocked Gemini prompt returned the raw body.** Gemini answers 200 with
  `promptFeedback.blockReason` and no candidates; the caller saw an unfamiliar
  shape rather than a clear refusal. It is normalized like any other reply,
  with `blocked`, `block_reason`, `finish_reason` set to `"content_filter"`,
  `text` as `""`, and `provider` populated. The refusal branch previously
  returned before normalizing, so `text` was `nil` — breaking the contract that
  it is always a string, for precisely the callers least likely to be guarding
  against it.
- **`RateLimiter.check` consumed a token.** A call that reads as a probe
  decremented the bucket, so any caller checking before acting spent its budget
  twice as fast as configured. `check` now only reports. Alongside that: both
  buckets are measured before either is spent, so a wait no longer discards a
  token already taken; and a request larger than the bucket capacity is
  reported as unsatisfiable instead of waiting for a refill that can never
  arrive.
- **Embedding results were paired by arrival order.** The API documents that
  they may arrive out of order, so a caller lining `embeddings[i]` up with
  `inputs[i]` could silently get the wrong vector for the wrong text. They are
  now sorted by the index the provider reports.
- **Claude tool schemas lost fields.** `input_schema` was rebuilt from
  `properties` and `required` alone, dropping `additionalProperties`, `$defs`,
  descriptions and anything else the caller wrote. The schema is now carried
  across intact, and an empty `required` is omitted rather than encoded as
  `{}`, which is the wrong JSON type for a list.
- **OpenRouter attribution used a header the gateway ignores.** It sent
  `X-OpenRouter-Title`; the documented header is `X-Title`, so attribution
  never took effect.
- **Gemini tool calling never reached a second round.** Gemini 3.x signs each
  `functionCall` with a `thoughtSignature` and rejects a follow-up that replays
  the call without it — *"Function call is missing a thought_signature in
  functionCall parts"* — but the follow-up turn was rebuilt from the tool's
  name and arguments, so the signature and the model's own call id were both
  discarded. The model's parts are now echoed back intact. OpenAI and Claude
  were unaffected; both already preserved their original blocks.
- **Gemini's explicit reasoning count was discarded.** The provider rebuilt
  `usage` from three fields, dropping `thoughtsTokenCount` — the very name
  `Response.normalize` looks for — so the cost of thinking was re-derived from
  the gap between the total and its parts, and was absent entirely whenever the
  total did not include it. Every field Gemini reports is now carried through,
  so `usage.raw` also holds `cachedContentTokenCount` and the rest.
- **`reasoning_applied` was never `true`.** It was set only when a request had
  to fall back, so the documented check `if response.reasoning_applied then`
  could not fire even when the provider honoured the request in full. It is now
  a boolean whenever a level was asked for — `false` also covering a provider
  with no reasoning control, which previously looked identical to compliance —
  and stays `nil` when no level was asked for. The test covering it was named
  for the correct behaviour but asserted the defect.
- **A transport failure could be mistaken for a provider refusal.** The
  `reasoning` and `json_schema` fallbacks matched on the error message even
  when no HTTP status was present, so an unrelated failure could be retried
  silently. A refusal now requires a 4xx.

### Changed

- **The bundled example tools are opt-in.** `get_weather` and `calculator` were
  registered when the module loaded, so every consumer inherited tools they
  never defined, in a registry shared across the process. Call
  `ToolRegistry.register_standard_tools()` if you were relying on them.
- **Diagnostics go through the logger.** The tool registry called `print`,
  which writes to a stream the host may be using for its own output and cannot
  be suppressed. It now uses `Logger.warn`, which a host can route or silence.
- `Config.is_explicit(config, key)` reports whether a value was chosen by the
  caller or filled in as a default.

### Documentation

- **The Agent Skill told agents reasoning could not be controlled portably.**
  Its API reference still described the 0.1.1 world — "there is no portable way
  to disable it" — so an agent reading it would reach for `reasoning_effort` or
  Claude's `thinking` by hand rather than the `reasoning` option added in
  0.2.0. It now covers `reasoning`, `json_schema`, and the tool loop, and
  `llms-full.txt` gained the same tool-loop and opt-in details.
- **The documented tool-loop example could not run.** It called
  `Registry.collection({ "find_city", "get_weather" })`, but `find_city` is not
  a bundled tool and the bundled ones stopped being registered at load time in
  this release, so the snippet failed with `Tool 'find_city' not found in
  registry`.
- Blocked Gemini prompts are documented in the provider guide.

## [0.2.0] - 2026-08-13

Adds normalized control over two things that previously required knowing each
provider's own dialect: how much a model reasons, and whether it answers with a
schema. Both degrade rather than fail, because several providers reject the
option outright on models that do not support it.

### Added

- **`reasoning` option.** Accepts `false`/`"none"`, `"low"`, `"medium"`,
  `"high"`, or `true`, and is translated per provider: an effort string for
  OpenAI-style services, a thinking budget for Gemini, and an opt-in block for
  Claude. Asking for less reasoning never turns a working request into an
  error: where a model refuses the control, the request is retried without it
  and `response.reasoning_applied` is `false`.
- **`json_schema` option** with the decoded result on `response.parsed`. One
  schema covers every provider, carried as a flattened `text.format` on the
  OpenAI Responses API, `response_format.json_schema` on Chat Completions
  services, `generationConfig.responseSchema` on Gemini, and a forced tool call
  on Claude, which has no response-format field. A model that refuses a schema
  falls back to plain JSON mode and then to an ordinary reply, with
  `response.structured_applied` reporting which happened.
- **`usage.reasoning_tokens`**, so the cost of thinking is visible rather than
  inferred from the gap between a total and its parts.
- **`capabilities().reasoning_control` and `capabilities().structured_output`**,
  describing what a provider can honour before a request is made.

### Fixed

- **Structured output was broken on OpenAI.** `response_format` was nested
  under `text.format`, but the Responses API requires the format flattened, so
  a JSON Schema request failed with `Missing required parameter:
  'text.format.name'`.
- **Gemini rejected ordinary JSON Schemas.** Its `responseSchema` accepts a
  restricted subset and errors on an unknown keyword rather than ignoring it,
  so a schema containing `additionalProperties` — which every other provider
  accepts — failed the request. Unsupported keywords are now removed.
- **Normalized `usage` was missing for most providers.** It was only rebuilt
  when a payload used `input_tokens`, so the many services reporting
  `prompt_tokens` had their provider-shaped usage passed straight through and
  the normalized fields were simply absent.
- **The documented embeddings example did not run.**
  `Embeddings.new("openai", { api_key = ... })` failed while building the
  request URL, because no provider supplied a default `base_url` even though
  the client for the same provider had one. Every embeddings provider now
  defaults its own endpoint, so Ollama needs no configuration at all.
- **`embeddings:embed(input)` passed the wrong argument.** The documentation
  and the agent reference both use a colon, matching `client:chat`, but the
  object was dot-only, so a colon call sent the embeddings object as the input.
  Both forms now work.

### Changed

- The embeddings object exposes `http` and `config`, so its transport can be
  replaced the same way a provider's can.

### Documentation

- `llms.txt` and `llms-full.txt` described the pre-LuaRocks install and none of
  the contracts that changed in 0.1.1. Agents reading them were being pointed
  at a source checkout.

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

[Unreleased]: https://github.com/unabated-games/ug-lua-llm/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/unabated-games/ug-lua-llm/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/unabated-games/ug-lua-llm/releases/tag/v0.1.0
