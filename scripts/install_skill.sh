#!/bin/sh
set -eu

agent=generic
scope=project
force=false

usage() {
  echo "Usage: $0 [--agent codex|claude|opencode|generic] [--scope project|user] [--force]" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      agent=$2
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      scope=$2
      shift 2
      ;;
    --force)
      force=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$scope:$agent" in
  project:codex|project:generic) skill_root=".agents/skills" ;;
  project:claude) skill_root=".claude/skills" ;;
  project:opencode) skill_root=".opencode/skills" ;;
  user:codex) skill_root="${CODEX_HOME:-$HOME/.codex}/skills" ;;
  user:claude) skill_root="$HOME/.claude/skills" ;;
  user:opencode) skill_root="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills" ;;
  user:generic) skill_root="$HOME/.agents/skills" ;;
  *)
    usage
    exit 2
    ;;
esac

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$project_root/skills/use-ug-lua-llm"
target_dir="$skill_root/use-ug-lua-llm"

if [ -e "$target_dir" ]; then
  if [ "$force" != true ]; then
    echo "Skill already exists at $target_dir; use --force to replace it." >&2
    exit 1
  fi
  rm -rf -- "$target_dir"
fi

mkdir -p "$skill_root"
cp -R "$source_dir" "$target_dir"
echo "Installed use-ug-lua-llm at $target_dir"
