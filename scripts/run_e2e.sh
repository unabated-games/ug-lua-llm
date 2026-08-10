#!/bin/sh
set -eu

task_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ug-lua-llm-e2e.XXXXXX")
server_pid=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$task_tmp_dir"
}
trap cleanup EXIT INT TERM

python3 spec/e2e/fake_llm_server.py --port-file "$task_tmp_dir/port" &
server_pid=$!

attempt=0
while [ ! -s "$task_tmp_dir/port" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 100 ]; then
    echo "Fake LLM server did not start" >&2
    exit 1
  fi
  sleep 0.05
done

fake_port=$(cat "$task_tmp_dir/port")
FAKE_LLM_BASE_URL="http://127.0.0.1:${fake_port}/v1" \
  busted --verbose spec/e2e

LLM_BASE_URL="http://127.0.0.1:${fake_port}/v1" \
LLM_MODEL="fake-stream" \
  lua scripts/conformance.lua
