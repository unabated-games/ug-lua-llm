# ug-lua-llm roadmap

ug-lua-llm began its public life at `0.1.0` and is published on LuaRocks. The
immediate priority is a small, dependable provider-neutral API rather than
increasing the provider count for its own sake.

## Near term

- Gather feedback on the public API now that it installs from LuaRocks.
- Keep local Ollama and arbitrary OpenAI-compatible endpoints first-class.
- Expand provider contract, transport, and conformance coverage.
- Continue extracting shared adapter behavior without hiding genuinely
  different provider protocols.
- Improve documentation, examples, and agent-facing reference material as the
  API evolves.

## Later

- Evaluate Lua 5.5 once the transport dependency chain supports it cleanly.
- Move toward `1.0.0` only after the public contracts have settled.

## Non-goals

- Adding named providers solely to increase the supported-provider count.
- Restricting access to provider-native response data; normalized responses
  will continue to retain the untouched provider response in `raw`.
