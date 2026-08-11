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
  "$output_dir/docs/reference" "$output_dir/docs/examples" "$output_dir/skills"

# The landing page is static HTML at the site root; the Docsify shell and every
# Markdown page it renders live together under docs/ so that Docsify's basePath
# is simply "./" and each route finds a sidebar beside its own content.
cp "$project_root/site/index.html" "$output_dir/index.html"
cp "$project_root/site/docs.html" "$output_dir/docs/index.html"
cp "$project_root/site/.nojekyll" "$output_dir/.nojekyll"

cp "$project_root/site/assets/base.css" "$output_dir/assets/base.css"
cp "$project_root/site/assets/site.css" "$output_dir/assets/site.css"
cp "$project_root/site/assets/docs.css" "$output_dir/assets/docs.css"
cp "$project_root/site/assets/site.js" "$output_dir/assets/site.js"
cp "$project_root/site/assets/llm-beaver.svg" "$output_dir/assets/llm-beaver.svg"
cp "$project_root/site/assets/favicon.svg" "$output_dir/assets/favicon.svg"
cp "$project_root/site/assets/favicon.ico" "$output_dir/assets/favicon.ico"
cp "$project_root/site/assets/apple-touch-icon.png" "$output_dir/assets/apple-touch-icon.png"
cp "$project_root/site/assets/og-image.png" "$output_dir/assets/og-image.png"

cp "$project_root/docs/index.md" "$output_dir/docs/index.md"
cp "$project_root/docs/getting-started.md" "$output_dir/docs/getting-started.md"
cp "$project_root/docs/agents.md" "$output_dir/docs/agents.md"
cp "$project_root/CHANGELOG.md" "$output_dir/docs/changelog.md"
cp "$project_root/docs/guides/"*.md "$output_dir/docs/guides/"
cp "$project_root/docs/reference/"*.md "$output_dir/docs/reference/"
cp "$project_root/examples/README.md" "$output_dir/docs/examples/README.md"

# llms.txt stays at the site root where tooling expects to find it, and is
# mirrored into docs/ as Markdown so Docsify can render it as a page too.
cp "$project_root/llms.txt" "$output_dir/llms.txt"
cp "$project_root/llms-full.txt" "$output_dir/llms-full.txt"
cp "$project_root/llms.txt" "$output_dir/docs/llms.md"
cp "$project_root/llms-full.txt" "$output_dir/docs/llms-full.md"

cp "$project_root/LICENSE" "$output_dir/LICENSE"
cp -R "$project_root/skills/use-ug-lua-llm" "$output_dir/skills/use-ug-lua-llm"

# Docsify looks for the nearest sidebar while navigating nested routes. Keep
# identical generated copies beside the canonical pages so those lookups never
# produce avoidable 404s.
for sidebar_dir in \
  "$output_dir/docs" \
  "$output_dir/docs/guides" \
  "$output_dir/docs/reference" \
  "$output_dir/docs/examples"
do
  cp "$project_root/site/_sidebar.md" "$sidebar_dir/_sidebar.md"
done

echo "Built static documentation in $output_dir"
