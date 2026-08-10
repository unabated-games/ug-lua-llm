# AI coding agents

The repository ships one portable Agent Skill at
[`skills/use-ug-lua-llm`](../skills/use-ug-lua-llm). It teaches coding agents to
select providers, write correct ug-lua-llm calls, handle errors, and verify work.
The same package works with Codex, Claude Code, OpenCode, and tools that support
the Agent Skills `SKILL.md` convention.

## Install from a checkout

Choose the directory for your agent and copy or symlink the complete skill
folder so its bundled reference remains available:

| Agent | Project location | User location |
|---|---|---|
| Codex | `.agents/skills/use-ug-lua-llm` | `~/.codex/skills/use-ug-lua-llm` |
| Claude Code | `.claude/skills/use-ug-lua-llm` | `~/.claude/skills/use-ug-lua-llm` |
| OpenCode | `.opencode/skills/use-ug-lua-llm` | `~/.config/opencode/skills/use-ug-lua-llm` |
| Generic Agent Skills | `.agents/skills/use-ug-lua-llm` | `~/.agents/skills/use-ug-lua-llm` |

Example project-local installation:

```sh
mkdir -p .agents/skills
cp -R /path/to/ug-lua-llm/skills/use-ug-lua-llm .agents/skills/
```

Or run the installer from a ug-lua-llm checkout:

```sh
sh scripts/install_skill.sh --agent generic --scope project
```

Supported agent values are `codex`, `claude`, `opencode`, and `generic`;
supported scopes are `project` and `user`. Existing installations are never
overwritten unless `--force` is supplied.

OpenCode also discovers `.agents/skills` and `.claude/skills`, so the generic
location is the simplest choice for repositories used by multiple agents.

## LLM-readable documentation

- [`llms.txt`](../llms.txt) is the short discovery index.
- [`llms-full.txt`](../llms-full.txt) is a compact, standalone usage reference.
- The skill bundles a focused reference for on-demand agent context.

Agents working inside this repository should also read `AGENTS.md`, which
contains contributor-specific validation and architecture guidance.
