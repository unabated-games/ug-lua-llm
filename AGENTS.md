# Agent guidance for ug-lua-llm

Read `docs/index.md` for the documentation map and `llms-full.txt` for the
public API summary. Keep provider-neutral behavior in shared modules and retain
provider-specific wire formats in their adapters.

When changing public behavior:

1. Preserve the `result, err, details` return convention.
2. Preserve normalized fields and the untouched `raw` provider response.
3. Add mock regression coverage; add local end-to-end coverage for transport.
4. Update the canonical page under `docs/`, then update `llms-full.txt` when the
   agent-facing contract changes.
5. Run `busted --exclude-pattern="integration"`, `sh scripts/run_e2e.sh`, and
   `luacheck ug-lua-llm/ spec/ scripts/` when those tools are installed.

Never place API keys in examples, fixtures, logs, lifecycle hooks, or error
details. Integration tests must skip providers whose credentials are absent.
