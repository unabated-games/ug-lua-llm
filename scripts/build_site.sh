#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir="${1:-$project_root/_site}"

case "$output_dir" in
  "$project_root"|"/"|"")
    echo "Refusing unsafe site output directory: $output_dir" >&2
    exit 1
    ;;
esac

rm -rf -- "$output_dir"
mkdir -p "$output_dir/assets" "$output_dir/docs/guides" \
  "$output_dir/docs/reference" "$output_dir/examples" "$output_dir/skills"

cp "$project_root/site/index.html" "$output_dir/index.html"
cp "$project_root/site/_sidebar.md" "$output_dir/_sidebar.md"
cp "$project_root/site/.nojekyll" "$output_dir/.nojekyll"
cp "$project_root/site/assets/theme.css" "$output_dir/assets/theme.css"
cp "$project_root/docs/index.md" "$output_dir/docs/index.md"
cp "$project_root/docs/getting-started.md" "$output_dir/docs/getting-started.md"
cp "$project_root/docs/agents.md" "$output_dir/docs/agents.md"
cp "$project_root/docs/guides/"*.md "$output_dir/docs/guides/"
cp "$project_root/docs/reference/"*.md "$output_dir/docs/reference/"
cp "$project_root/examples/README.md" "$output_dir/examples/README.md"
cp "$project_root/llms.txt" "$output_dir/llms.txt"
cp "$project_root/llms-full.txt" "$output_dir/llms-full.txt"
cp "$project_root/llms.txt" "$output_dir/llms.md"
cp "$project_root/llms-full.txt" "$output_dir/llms-full.md"
cp "$project_root/LICENSE" "$output_dir/LICENSE"
cp -R "$project_root/skills/use-ug-lua-llm" "$output_dir/skills/use-ug-lua-llm"

# Docsify looks for the nearest sidebar while navigating nested routes. Keep
# identical generated copies beside the canonical pages so those lookups never
# produce avoidable 404s.
for sidebar_dir in \
  "$output_dir/docs" \
  "$output_dir/docs/guides" \
  "$output_dir/docs/reference" \
  "$output_dir/examples"
do
  cp "$project_root/site/_sidebar.md" "$sidebar_dir/_sidebar.md"
done

echo "Built static documentation in $output_dir"
