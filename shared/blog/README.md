# Regent Blog

`regent_blog` is the file-to-HTML boundary for the four Regent Phoenix products.
It owns metadata validation, safe Markdown and a compile-time catalog. Product
controllers own `/blog` and `/blog/:slug`; `Regent.Blog` in `regent_ui` owns the
shared gallery, article and contents presentation. Ash/database/auth state stays
out of the shared catalog.

## Use

Add the path dependency in a consumer's `platform/mix.exs` and define a module with
`use RegentBlog.Catalog, root: Path.expand("../../../blog", __DIR__)` from
`platform/lib/<web>/blog.ex`. `all/0` returns public posts newest first; `get/1`
returns a post or nil. `RegentBlog.load!/1` validates an entire trusted directory.
Each post keeps its Markdown body in `markdown` beside the safe `html`, so a product
can answer `/blog/:slug` as Markdown for agents from the same source.
The catalog bakes content into the BEAM; it never joins a request slug to a file.

See each product's root `blog/README.md` and `example-post.md` for the authoring
format. There is deliberately no CMS, category filter, React context, browser
content fetch, HTML/HEEx execution, or automatic author attribution.

## Assets and releases

`mix regent_blog.assets` runs from the consuming platform and stages the packaged
KaTeX module into `priv/static/assets/regent-blog`, plus repository `blog/images`
into `priv/static/images/blog`. Both destinations are generated. Import shared
`blog.mjs` from the consumer's staged `regent_ui`; `structure.css` imports blog CSS.
Keep images self-hosted to honor all four existing CSPs.

`mix regent_blog.stage` stages the package and product source content into an
application-only Docker context. It requires a pinned elixir-utils workspace
snapshot and `REGENT_BLOG_REVISION`, checks package bytes against that snapshot,
refuses symlinks/environment-shaped inputs and unrecognized destinations, and
preserves prior generated copies under `vendor/.regent-blog-history`.
Regents/Autolaunch use their existing parent-context assemblers instead.
Shared package/UI revisions must be committed and consumer pins advanced before
CI or release preparation can select this addition. No deployment is implied.

## Math and trust

Markdown uses MDEx with raw HTML disabled. Local KaTeX 0.18.7 renders dollar-delimited
math as MathML with `trust: false`, bounded expansion and size. It needs no CDN,
inline styles or CSP changes. TeX remains visible if JavaScript or rendering fails.
KaTeX's MIT license is retained in `priv/static/KATEX-LICENSE.txt`.

Npm source: `https://registry.npmjs.org/katex/-/katex-0.18.7.tgz`.
Verified npm integrity:
`sha512-h+UCwkZ+4Jz8WQ7MLGfj7UVFrRCizGb912fwF4luGdYsC5paYG1vx+jy+KRcC/XkpjGva/P7nAWuxNnPzRvzHw==`.

Posts are trusted repository authoring inputs, capped at 1 MB each. Drafts and
future UTC dates are filtered on every public catalog read. Raw Markdown is never
staged as a public asset; images are public, including images referenced by drafts.
Use modern browsers with native MathML; desktop WebKit is not physical-iPhone or
VoiceOver acceptance.

## Checks

From this package: `mix check` and `mix hex.audit`. Product acceptance also requires
the actual controller routes, header/theme controls, rendered Markdown/math, native
contents navigation and narrow layouts—not compilation alone.
