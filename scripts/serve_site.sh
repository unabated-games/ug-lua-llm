#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
port="${1:-8765}"

case "$port" in
  *[!0-9]*|'')
    echo "Usage: $0 [port]" >&2
    exit 2
    ;;
esac

sh "$project_root/scripts/build_site.sh"

echo "Previewing ug-lua-llm documentation at http://localhost:$port"
echo "Press Ctrl-C to stop."
exec python3 -m http.server "$port" --directory "$project_root/_site"
