# Local Techtree notebooks

Techtree notebook pages use Marimo's static WebAssembly export so Python runs on the reader's device, not in the Regent web process. The browser page is deliberately read-only: agents prepare and publish notebook evidence through a separate authenticated contract, while humans explore the admitted result.

## Artifact boundary

The canonical state owner is `AshPlatform.Techtree.NotebookArtifact`. An admitted artifact binds one stable node and its current payload to:

- the source hash;
- the exact Marimo version and Pyodide runtime;
- a manifest that hashes every exported file; and
- a content-addressed run URL.

Only the named Techtree domain interface may admit an artifact. Browser requests only read that state. A later CLI/SIWA publisher must begin in its owning API and CLI contracts and produce this same artifact shape; it must not add an alternate upload format or execute arbitrary Python in a web request.

## Reproducible export

Use the exact approved Marimo release and its static run mode:

```sh
uvx --from marimo==0.23.14 marimo check notebook.py
uvx --from marimo==0.23.14 marimo export html-wasm notebook.py -o exported-notebook --mode run --no-show-code
```

The publisher hashes the source and every file under `exported-notebook`, writes the canonical manifest, and places the directory at the payload-hash path before calling the domain interface. Marimo 0.23.14 loads Pyodide from `https://cdn.jsdelivr.net`, its versioned lock file from `https://wasm.marimo.app`, and the exact Python wheels named by that lock from `https://files.pythonhosted.org`. Those three origins must be declared in the artifact and are the only external origins admitted by the notebook policy. The test fixture in `test/support/fixtures/` is the executable example; `AshPlatform.TestMarimoArtifact` owns its deterministic local export and manifest generation.

## Browser isolation

The node page loads only the admitted content-addressed URL from a dedicated notebook origin. The iframe may use workers on that origin, but it remains cross-origin and credentialless relative to Regent, sends no referrer, and denies device/payment capabilities. Notebook files are served outside the application session pipeline with a restrictive content policy. If validation fails or the node payload changes, the page does not run the artifact.

Marimo's upstream model and export behavior are documented in the [WebAssembly guide](https://docs.marimo.io/guides/wasm/) and [static HTML export guide](https://docs.marimo.io/guides/exporting/webassembly_html/).
