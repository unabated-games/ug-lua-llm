# ug-lua-llm roadmap

ug-lua-llm is starting its public life at `0.1.0`. The immediate priority is a
small, dependable provider-neutral API rather than increasing the provider
count for its own sake.

## Near term

- Gather feedback on the renamed public API and source installation flow.
- Keep local Ollama and arbitrary OpenAI-compatible endpoints first-class.
- Expand provider contract, transport, and conformance coverage.
- Continue extracting shared adapter behavior without hiding genuinely
  different provider protocols.
- Improve documentation, examples, and agent-facing reference material as the
  API evolves.

## Later

- Evaluate Lua 5.5 once the transport dependency chain supports it cleanly.
- Decide deliberately when the package is ready for its first LuaRocks upload.
- Move toward `1.0.0` only after the public contracts have settled.

## Non-goals

- Adding named providers solely to increase the supported-provider count.
- Publishing to LuaRocks before an explicit release decision.
- Restricting access to provider-native response data; normalized responses
  will continue to retain the untouched provider response in `raw`.
