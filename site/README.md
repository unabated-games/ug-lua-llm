# Website source

This directory contains the Docsify shell and theme, not a standalone built
website. The documentation itself remains canonical under `../docs/` and is
copied into the generated site.

From the project root, preview the complete website with:

```sh
./scripts/serve_site.sh
```

The default URL is `http://localhost:8765`. Pass another port as the first
argument. Do not run `python3 -m http.server` directly inside `site/`; that
server cannot access the canonical Markdown outside its document root.
