# ug-lua-llm roadmap

ug-lua-llm is published on LuaRocks. The priority remains a small, dependable
provider-neutral API rather than a larger provider count.

## Where the releases have gone

`0.1.1` and `0.3.0` were both correctness releases, and between them they say
most of what this project has learned: the defects that matter have been
seams — a field written under one name and read under another, an option
translated for one provider and dropped for the next, a rule about model
capabilities that was true when it was written.

`0.2.0` added the two normalized controls that were missing, `reasoning` and
`json_schema`, both degrading rather than failing where a provider refuses them.

## Near term

- **Make `response.raw` the untouched provider payload on Gemini.** It is
  currently an intermediate table, with the real body one level further down at
  `raw.raw`, because the normalizer is handed something already normalized.
  Every other provider satisfies the documented contract. Fixing it changes the
  shape of `raw` for existing Gemini callers, so it wants its own release and a
  note saying which field is the untouched body *now* — not which one moved.
- **Incremental tool calls on the OpenAI Responses API.** Function calls arrive
  there as typed output items, and the registry has no incremental tool-call
  API to feed them into, so `stream_chat_with_tools` there fires the callback
  once with a complete normalized response. The Chat Completions and Anthropic
  paths build their calls from incremental events instead; this one does not
  surface the call until it is finished.
- Keep local Ollama and arbitrary OpenAI-compatible endpoints first-class.
- Continue extracting shared adapter behaviour without hiding genuinely
  different provider protocols.

## Testing practices worth keeping

These came out of a port of this library to another runtime, and each one found
defects that module-level tests could not:

- Test provider parsing and normalization **together**, asserting only what a
  caller receives. A field written under one name and read under another is
  correct on both sides of a seam and broken across it.
- Build fixtures from **transcribed** provider responses rather than plausible
  ones. A body written from belief tests the belief.
- Pin default models in the integration suite. Defaults age out silently and
  fail only the callers who did not set one, which is the newest ones.
- Prefer an invariant to a list — "whatever can stream can report its tool
  calls" rather than naming the providers that currently can.

## Later

- Evaluate Lua 5.5 once the transport dependency chain supports it cleanly.
- Move toward `1.0.0` only after the public contracts have settled. The
  normalized response, the `result, err, details` convention and the two
  degrading controls are the contracts that need to hold still first.

## Non-goals

- Adding named providers solely to increase the supported-provider count.
- Restricting access to provider-native response data; normalized responses
  will continue to retain the untouched provider response in `raw`.
- Guessing model capabilities from model names. Three separate rules of that
  kind have now had to be removed, each correct when written and each able to
  rot in only one direction.
