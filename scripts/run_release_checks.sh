#!/bin/sh
# Everything worth running before cutting a release, in one place.
#
# By default this runs only checks that need no credentials, so it is safe to
# run at any time. Pass --live (or set UG_LUA_LLM_LIVE=1) to add the live
# provider tests, which read keys from .env and cost real tokens.
#
#   sh scripts/run_release_checks.sh
#   sh scripts/run_release_checks.sh --live
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

live="${UG_LUA_LLM_LIVE:-0}"
for arg in "$@"; do
  case "$arg" in
    --live) live=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

failures=0
step() {
  name=$1
  shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    printf '%s\n' "  -> $name: OK"
  else
    printf '%s\n' "  -> $name: FAILED" >&2
    failures=$((failures + 1))
  fi
}

# Unit tests run once per JSON backend. The backends disagree on how JSON null
# is represented, so a single run cannot prove a sentinel never escapes.
for backend in cjson dkjson; do
  if lua -e "local ok = pcall(require, '$backend') os.exit(ok and 0 or 1)" 2>/dev/null; then
    step "unit tests ($backend)" env UG_LUA_LLM_JSON_BACKEND="$backend" \
      busted --exclude-pattern=integration
  else
    printf '\n=== unit tests (%s) ===\n' "$backend"
    printf '%s\n' "  -> skipped: $backend is not installed"
  fi
done

step "lint" luacheck ug-lua-llm/ spec/ scripts/
step "end-to-end transport" sh scripts/run_e2e.sh
# Discovered rather than pinned, so a version bump needs no edit here.
rockspec=$(ls ./*.rockspec | head -n 1)
step "version consistency" lua scripts/check_version.lua "$rockspec"
step "rockspec lint" luarocks lint "$rockspec"

if [ "$live" = "1" ]; then
  # Live provider coverage: real TLS, real endpoints, real multi-kilobyte
  # bodies. Providers without credentials report as pending, and an account
  # with no credit is reported as pending rather than a regression.
  step "live provider tests" busted --run=integration
else
  printf '\n=== live provider tests ===\n'
  printf '%s\n' "  -> skipped: pass --live to run them (uses credentials and tokens)"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  echo "All release checks passed."
else
  echo "$failures release check(s) failed." >&2
  exit 1
fi
