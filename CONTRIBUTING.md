# Contributing

Bug reports, documentation improvements, provider compatibility fixes, and
focused API improvements are welcome.

Before opening a pull request:

1. Keep provider-neutral behavior in shared modules and provider wire formats
   in their adapters.
2. Preserve the `result, err, details` return convention, normalized response
   fields, and untouched provider response in `raw`.
3. Add mock regression coverage for behavior changes and localhost end-to-end
   coverage for transport changes.
4. Update the canonical documentation under `docs/`; update `llms-full.txt`
   when the agent-facing contract changes.
5. Run the available checks:

   ```sh
   busted --exclude-pattern="integration"
   sh scripts/run_e2e.sh
   luacheck ug-lua-llm/ spec/ scripts/
   ```

Never include API keys, credentials, `.env` contents, or private request data
in code, examples, fixtures, logs, issues, or pull requests. Integration tests
must skip providers whose credentials are absent.

By contributing, you agree that your contribution is licensed under the MIT
License included in this repository.
