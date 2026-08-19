# Changelog

Notable changes to ug-lua-llm. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-08-19

An audit of how the library talks to each inference API, run against the real
services rather than from memory. Everything below is a case where the code's
model of an API disagreed with the API.

**One of these is a regression introduced in 0.3.0** and is the reason to take
this release: on the default OpenAI API, any tool round where the model spoke
before calling a tool failed on the follow-up.

### Fixed

- **The OpenAI tool loop broke whenever the model spoke before calling a
  tool.** 0.3.0 began echoing the model's own `output` items back, and marked
  empty containers as arrays so they would survive the JSON round trip — but
  only at the top level of each item. A `message` item nests them two deep, so
  `content[0].annotations` re-encoded as an object and the follow-up was
  rejected with *"expected an array of objects, but got an object instead"*. The
  changelog entry for the schema sealer in that same release says a one-level
  pass misses nested nodes; this was written beside it and did exactly that.
- **`tool_choice = { name = ... }` was a 400 on OpenAI and every
  OpenAI-compatible provider.** 0.3.0 documented the portable form and
  translated it for Claude and Gemini, whose spellings are unusual, then passed
  it verbatim to the family it was modelled on — which wants an object, spelled
  differently again on each of OpenAI's two APIs, and answers a bare name with
  `Missing required parameter: 'tool_choice.type'`.
- **Reasoning did nothing on current Claude models.** They reject the thinking
  budget outright — *"Use 'thinking.type.adaptive' and 'output_config.effort'"* —
  so `reasoning` silently degraded and the documented `thinking = true` was a
  hard failure. The ladder now asks for an effort level first and keeps the
  budget as its next rung, so both model generations are covered.
- **Claude's model list was hardcoded on the premise that no endpoint exists.**
  It does. The hardcoded list had rotted the only way such a list can: it named
  models that no longer resolve and omitted the entire current generation.
  `list_models` reads the endpoint now and keeps the per-model capability
  metadata, including which effort levels each model accepts.
- **Streaming on OpenAI's Chat Completions dropped three option families and
  reported compliance.** `stream_chat` and `stream_chat_with_tools` built
  literal payloads carrying neither `reasoning_effort`, `response_format`, nor
  `request_options` — the last documented to reach the provider untouched — and
  then reported `reasoning_applied` and `structured_applied` as true for a
  request that had contained none of them. Both now build the same payload as
  the non-streaming path.
- **Gemini rejected tool schemas written for OpenAI.** Its restricted subset of
  JSON Schema was applied to response schemas and not to tool parameters, so a
  tool schema carrying `additionalProperties` — required by OpenAI strict mode —
  failed with `Unknown name "additionalProperties"`.
- **`stream_fallback = false` was honoured by one provider family.** OpenAI,
  Claude and Gemini fell back to a non-streaming request unconditionally, and
  the fallback's single callback counts as a chunk — so the bundled conformance
  runner, whose purpose is detecting broken SSE, reported streaming healthy on
  three providers where it was not.
- **Two streaming returns still bypassed normalization.** Gemini's `stream_chat`
  returned the raw accumulator on the *successful* path while its fallback
  returned a normalized response, and Claude's `stream_chat` had the reverse.
  One function, one path fixed, one not — in both.
- **`capabilities().embeddings` claimed DeepSeek.** Its adapter was removed in
  0.3.0 when DeepSeek turned out to serve no embeddings endpoint, and the
  capability map was not the sibling that got updated, so the documented check
  said yes and the constructor then raised.
- **A forced `tool_choice` was re-sent on every tool round.** `"required"`, or a
  named tool, compelled another call each round, so the exchange ran to
  `max_tool_rounds` and never reached an answer. It applies to the turn the
  caller made; follow-ups let the model choose, including choosing to stop.
- **Streamed replies never reported usage.** The chunk carrying token counts
  arrives with an empty `choices`, and the accumulator returned early on exactly
  that, so `stream_options.include_usage` — which this library forwards — could
  not produce any.
- **Streamed Claude tool exchanges dropped signed thinking blocks.** The handler
  recognized only `tool_use` blocks, so a streamed thinking-plus-tools reply
  could not legally be continued: Anthropic requires the signed blocks echoed
  ahead of the tool calls. Same rebuild-instead-of-echo the non-streaming path
  was fixed for.
- **Gemini tool results were sent as arrays.** `functionResponse.response` must
  be a Struct, and a tool returning a list encoded as a JSON array. Only a map
  now travels unwrapped.
- **A Gemini reply with neither candidates nor a block reason returned the raw
  body**, leaving `text` nil against a contract that says it is always a string.
  It was the last un-normalized path in that formatter.
- **`stream_complete` deltas carried neither `content` nor `text`** on Claude,
  Gemini, and the OpenAI-compatible family. The 0.3.0 fix for this landed only
  in the OpenAI provider, so the documented
  `delta.content or delta.text` printed nothing on the other three.

### Documentation

- `finish_reason` is the provider's own value, not a normalized vocabulary. The
  documented `== "length"` example only matched OpenAI-style services; Claude
  reports `max_tokens` and Gemini `MAX_TOKENS`.
- Reasoning on Claude, including why a temperature you set is dropped when a
  thinking budget is in use — an API requirement, and the one place the library
  discards a value you chose.

## [0.3.0] - 2026-08-19

The largest correctness release so far. It began with defects found by a team
porting the library to another runtime, who read every module closely and
re-derived its behaviour; it grew because the techniques that exchange produced
— testing provider parsing and normalization together rather than separately,
transcribing real provider responses instead of writing plausible ones, and
auditing for options no documentation had ever had to state the behaviour of —
kept finding more.

Almost none were visible as a failing test. The behaviour was wrong and nothing
asserted otherwise, and in several cases a passing test sat directly beside the
defect, asserting what the code did rather than what the API required.

**Six documented features did not work at all.** If you use any of these, this
release is the one to take:

- Groq's default model had been retired, so a client that set no model failed
  on its first call.
- OpenAI tool calling never produced a final answer.
- Gemini tool calling never reached a second round.
- Embeddings failed on Gemini and Mistral, and were documented for DeepSeek,
  which serves no embeddings endpoint.
- Streaming never streamed on current OpenAI models — the request was rejected
  and a silent fallback returned a whole reply, reporting success.
- `tool_choice` was ignored on Claude and Gemini, so a caller forbidding tool
  use with `"none"` had tools called anyway.

**Behaviour changes worth reading before upgrading:** there is no longer a
default `temperature`; the bundled example tools are opt-in; a JSON schema
combined with tools is refused on Claude; a library option nested inside
`request_options` is refused rather than forwarded; and `Embeddings.new` raises
for a provider that has no embeddings rather than returning a client that 404s.

### Added

- **`RateLimiter.acquire(provider, tokens)`** returns `{ ok, wait, limit,
  waited }`, where `limit` names the bucket that bound the call. `configure`
  gained `request_burst` and `token_burst`, defaulting to their rates, and `now`
  and `sleep` hooks so pacing can be tested without waiting.
- **Tool exchanges report what happened across all of them:** `tool_calls`
  across every round, `tool_results` with `ok` and `error` per dispatch,
  `tool_rounds`, `tool_pending` for calls a round cap stopped, and `messages`,
  the conversation ready to continue. `on_tool` observes each dispatch.
- **`ToolRegistry.register_standard_tools()`**, now that `get_weather` and
  `calculator` are opt-in rather than registered at load time.
- **`JSON.empty_array()`**, for building a payload that must carry an empty
  array where an empty Lua table would otherwise encode as an object.
- **Error codes `schema_tool_conflict` and `library_option_in_request_options`**
  on `details.code`, for the two option combinations that are refused up front.

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
  models also reject. **There is now no temperature default at all**, so a
  temperature present in a config is by definition one the caller chose. The
  old rule additionally stripped a caller's temperature for models matching
  `^o%d`; that is gone too, because `gpt-5.x` refuses a temperature and cannot
  be recognised by name, so stripping for one family and not the other was
  inconsistent in the direction that hides the problem. A value the caller set
  now travels and the provider answers for it — a 400 naming the parameter
  beats a silent drop that looks like it applied.
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

- **`reasoning` meant something different on the Responses escape hatch.**
  `client:response` passed the option straight through to a field the API
  requires to be an object, so a caller moving a working `reasoning = "high"`
  from `chat` to the escape hatch got *"Invalid type for 'reasoning': expected
  an object, but got a string instead"*. A normalized level is now translated
  there as it is everywhere else, and a caller who supplies the provider's own
  object still has it passed through untouched.
- **`complete` and `stream_complete` sent current models to a dead endpoint.**
  The routing kept an allow-list of chat-only models, written when
  `/v1/completions` still served most of them, and sent anything absent from it
  to the legacy endpoint — so every model released since failed with *"This is
  a chat model and not supported in the v1/completions endpoint"*. The list was
  correct when written and could rot in only one direction. It is inverted now:
  an unknown model goes to the endpoint that serves everything, and only the
  handful the legacy endpoint still serves take the other branch. Alongside
  that, `stream_complete` deltas now carry `content` and `text`, which every
  streaming callback in the library is documented to expose and this one did
  not.
- **A JSON schema written the obvious way was rejected, and the reason was
  hidden.** OpenAI's strict mode requires `additionalProperties: false` on every
  object node, and the caller's schema was passed through unchanged — so a
  schema with none, which is what anyone writes, failed the strict attempt with
  `'additionalProperties' is required to be supplied and to be false`. The
  ladder then degraded to plain JSON mode as designed, and *that* rung failed
  for an unrelated reason, so the error the caller finally saw named a rung they
  never asked for. Every object node is sealed now, including objects inside
  `items`, which a one-level pass misses and which is exactly the shape of a
  list of records. An explicit `additionalProperties = true` is left alone.
- **`structured_applied` was derived from the attempt index alone.** That reads
  correctly while every provider has a carrier, and stops the moment one does
  not: a provider absent from the format map has a single attempt — the
  unchanged one — so the first rung is a request carrying no schema, and the
  caller was told their schema had been honoured by a request that never
  contained it. It is now derived from whether a carrier resolved at all, the
  same rule `reasoning_applied` already used. Both flags are answered by their
  own module — `Reasoning.applied` and `Structured.applied` — rather than
  computed at the call site, because two expressions of one fact are how the
  first came to be fixed without the second. Tests cover both maps for every
  provider the library can construct.
- **Structured output did nothing on the Chat Completions escape hatch, and
  said it had worked.** The schema was carried as `text.format`, which only the
  Responses API reads, and the Chat Completions payload builder did not carry
  `response_format` at all — so the schema never reached the wire, the request
  succeeded without it, and `structured_applied` reported `true`. The carrier
  now follows the API in use, and the payload carries what it is given.
- **Streaming replies did not satisfy the normalized contract on Claude.** The
  accumulator built Anthropic's own shape and returned it directly, so a
  streamed reply carried `stop_reason` rather than `finish_reason`, no
  `provider` — which made the documented one-argument
  `Tool.parse_tool_calls(response)` raise — and `text` as `nil` against a
  contract saying it is always a string, losing the model's prose entirely when
  it spoke before calling a tool. Both streaming paths normalize now, and the
  accumulator rebuilds Anthropic's content blocks, which is both the shape the
  normalizer reads tool calls from and the shape a tool follow-up echoes back;
  a string would have been the wrong type there.
- **Streaming sent the retired token field on Chat Completions.** 0.3.0 fixed
  `max_tokens` to `max_completion_tokens` in the non-streaming builder and
  missed the two streaming ones that post to the same endpoint, so current
  models rejected the request — and the silent fallback to a non-streaming call
  reported success, so a caller who asked to stream got a whole reply and no
  signal that streaming had failed.
- **OpenAI tool exchanges discarded the model's reasoning between rounds.** The
  follow-up rebuilt a `function_call` item from the tool's name and arguments,
  so a reasoning model's `reasoning` item — which carries its `encrypted_content`
  alongside the call — was dropped and the chain of thought re-derived from
  scratch on every round. The model's own `output` items are echoed back now,
  which is the same rule Claude's content blocks and Gemini's parts already
  follow: echo what the provider sent, do not rebuild it. Three providers, three
  different fields, one rule.
- **`JSON.empty_array()`**, because echoing a provider's structure back requires
  the round trip to be faithful and it was not: an empty JSON array and an empty
  JSON object decode to the same Lua table, so a decoded `"summary": []`
  re-encoded as `{}` and was rejected as the wrong type. Empty tables still
  default to objects, which JSON Schema `properties` and empty tool arguments
  depend on; the marking is explicit and now survives encoding on both backends.
- **Embeddings were broken on two of the four providers that have them, and
  claimed on one that has none.** The OpenAI-compatible adapter fell back to a
  single hardcoded OpenAI model name for every service it serves, so Mistral was
  asked for a model it has never had — 400 — and Gemini's own default,
  `text-embedding-004`, had been retired outright: 404. Both failed only for
  callers who did not pass a model, which is the ones following the
  documentation. Each provider now defaults to its own (`text-embedding-3-small`,
  `gemini-embedding-001`, `mistral-embed`, `nomic-embed-text`), and the
  integration suite checks all three cloud defaults still resolve. DeepSeek
  serves no embeddings endpoint at all; it was aliased to the OpenAI adapter and
  documented as supported, so a caller got a bare 404 that read like a
  misconfiguration. It now raises at construction naming the providers that do
  have them. Two existing tests asserted the alias.
- **`dimensions` did nothing on most providers.** Each service spells the
  requested vector width its own way — `dimensions`, `outputDimensionality`,
  `output_dimension` — and only OpenAI's was ever sent, so the option was
  silently ignored elsewhere. Translated now; a model that does not support a
  narrower vector says so rather than the request quietly returning the full
  width.
- **`tool_choice` was ignored on both Claude and Gemini.** Each spells it
  differently — `{ type = ... }` on Claude, a nested
  `toolConfig.functionCallingConfig` on Gemini — and neither was translated, so
  the option never reached either payload. A caller asking to force a tool got
  a free choice, and — worse — one asking for `"none"` to *forbid* tool use got
  tools called anyway, with no error to say otherwise. `auto`,
  `required`/`any`, `none`, and naming a single tool now all translate for
  both; a named tool becomes `allowedFunctionNames` on Gemini and
  `{ type = "tool", name = ... }` on Claude. A value no provider recognizes is
  left out rather than guessed at.
- **A library option nested in `request_options` was forwarded raw.**
  `request_options` reaches the provider untouched by design, which is what
  makes a name this library also owns dangerous inside it: the attempt ladder
  consumes the top-level `reasoning`, so a copy nested there went straight to
  the provider and was rejected as a parameter the caller had been told to use.
  It is refused up front with `code = "library_option_in_request_options"` and a
  message naming the fix. Only this library's value shape is caught — a
  provider's own object of the same name still passes through, because a caller
  writing that shape means the provider's API rather than ours.
- **A failed tool was reported to Claude as an ordinary result.** Anthropic's
  `tool_result` block has an `is_error` flag; without it a handler failure reads
  to the model as a call that succeeded and happened to return an error-shaped
  object. It is now set, and omitted rather than sent as `false` on success.
- **A JSON schema and tools could not be combined on Claude, confusingly.**
  Claude has no response-format field, so the schema is delivered as a forced
  tool call, which the caller's own tools then contradict. The provider rejected
  it as `Tool 'answer' not found in provided tools`, sending the caller after a
  registration bug that did not exist. The conflict is now reported up front
  with `code = "schema_tool_conflict"`. Where a provider has a real response
  format the two still travel together, but a model that answers with a tool
  call produces no JSON, so `parsed` is `nil` even when `structured_applied` is
  true; the guidance is to read `parsed`.
- **The rate limiter takes its clock as a parameter.** `now` and `sleep` are
  configurable, defaulting to the wall clock and a real sleep, which makes the
  waiting behaviour testable without waiting — the suite covers refill, burst,
  and both failure modes in 13ms and cannot flake on a slow machine. `now` is
  called once at configuration, so a clock reporting the wrong unit fails there
  with a clear message rather than producing a limiter that waits a thousand
  times too long. Alongside that: `acquire` reports which bucket bound the call,
  a `sleep` hook that cannot pause is reported as `stalled` instead of spun on,
  one that raises cannot corrupt the limiter, `waited` is measured from the
  clock rather than assumed from the delays requested, a clock that goes
  backwards no longer manufactures tokens, and `request_burst`/`token_burst`
  default to their rates so existing behaviour is unchanged. The unused
  `Bucket:wait_and_acquire` is gone; it decremented without re-checking and
  could take a bucket negative.
- **A tool exchange reports what happened across all of it.** The turn that
  finally answers asks for no tools, so a caller reading `tool_calls` on it saw
  nothing in exactly the case where tools had been used successfully. The final
  response now carries `tool_calls` (every call requested, across every round),
  `tool_results` (every one that ran, each with `ok` and `error`), `tool_rounds`,
  and `messages` — the conversation as it now stands, ready to continue. When
  `max_tool_rounds` stops the loop, the calls it prevented are handed back as
  `tool_pending` rather than dropped, because the cap is now consulted after
  recording what the model asked for rather than before. An `on_tool` callback
  reports each dispatch, so a host can render progress instead of the library
  writing to a stream it does not own.

- **The bundled example tools are opt-in.** `get_weather` and `calculator` were
  registered when the module loaded, so every consumer inherited tools they
  never defined, in a registry shared across the process. Call
  `ToolRegistry.register_standard_tools()` if you were relying on them.
- **Diagnostics go through the logger.** The tool registry called `print`,
  which writes to a stream the host may be using for its own output and cannot
  be suppressed. It now uses `Logger.warn`, which a host can route or silence.

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

[Unreleased]: https://github.com/unabated-games/ug-lua-llm/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/unabated-games/ug-lua-llm/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/unabated-games/ug-lua-llm/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/unabated-games/ug-lua-llm/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/unabated-games/ug-lua-llm/releases/tag/v0.1.0
