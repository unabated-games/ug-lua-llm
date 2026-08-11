# Website source

This directory holds the website shell and theme, not a standalone built site.
The documentation itself remains canonical under `../docs/` and is copied into
the generated site by `../scripts/build_site.sh`.

## Layout

| File | Becomes | Purpose |
|---|---|---|
| `index.html` | `/index.html` | Static landing page. No framework, no build step. |
| `docs.html` | `/docs/index.html` | Docsify shell for the documentation. |
| `_sidebar.md` | `/docs/**/_sidebar.md` | Sidebar, copied beside every route directory. |
| `assets/base.css` | `/assets/base.css` | Design tokens and the shared site header. |
| `assets/site.css` | `/assets/site.css` | Landing page styles. |
| `assets/docs.css` | `/assets/docs.css` | Dark theme layered over Docsify's `vue.css`. |
| `assets/site.js` | `/assets/site.js` | Landing page tabs, copy buttons, Lua highlighting. |

The landing page lives at the site root and the Docsify application lives at
`/docs/`, alongside the Markdown it renders. Because the shell and its content
share a directory, Docsify's `basePath` is simply `./` and every route resolves
a sidebar from its own directory.

Old documentation URLs used the site root (`/#/docs/getting-started.md`). The
landing page forwards those to `/docs/#/getting-started.md` before first paint.

## Brand assets

`assets/llm-beaver.svg` and `assets/favicon.svg` are generated from
`../branding/llm-beaver.svg` with editor metadata stripped. The favicon variant
scales the mascot up inside the same roundel so it still reads at 16px, and
uses a square canvas so icon rasterisation never letterboxes. `favicon.ico`,
`apple-touch-icon.png`, and `og-image.png` are rasterised from that SVG.

Regenerate them only when the source artwork changes; they are committed so the
site build stays a plain file copy with no image toolchain in CI.

## Preview

From the project root:

```sh
./scripts/serve_site.sh
```

The default URL is `http://localhost:8765`. Pass another port as the first
argument. Do not run `python3 -m http.server` directly inside `site/`; that
server cannot access the canonical Markdown outside its document root.
