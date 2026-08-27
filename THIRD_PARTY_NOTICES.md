# Third-party notices

Third-party material redistributed inside this repository, and the terms it arrives under.

## vgpu — homepage prism

The homepage hero renders the prism scene from Vercel's `vgpu` project. Both the
TypeScript under `assets/js/home_prism/` and the WGSL compiled into
`assets/js/home_prism/shaders/` are adapted from it.

- Project: `vercel-labs/vgpu` — https://github.com/vercel-labs/vgpu
- Commit: `bd3b05101fdd1193a1593558d3c52a0b2b18f31d` ("feat(docs): move prism shader to homepage")
- Source directory: `apps/docs/app/[lang]/(home)/components/prism-background`
- License: MIT

Pinned npm packages, exact versions, no ranges:

| Package          | Version |
| ---------------- | ------- |
| `vgpu`           | 0.3.1   |
| `@webgpu/types`  | 0.1.69  |

### What was taken

Camera, optics, prism mesh, spectral light mesh, scene graph and the production
shaders — `wall`, `light`, `glass`, `glass-back`, `glass-common`, `environment`,
`copy-linear`, `bloom`, `bloom-upsample`, `present` — together with the shared
`scene` uniform block and `@vgpu/wgsl-std/color`.

### What was left behind

The React component and its lazy control panel, the debug control schema and every
value range that fed it, the environment-reflection debug renderer and its axes
shader, the shader validation module, the wireframe and light-wireframe paths and
shaders, the alternate wall/back-face/caustic view modes, the headless thumbnail and
gallery renderer, and the upstream test suites.

### How the shaders got here

Upstream resolves WGSL imports through a bundler plugin. This repository has no such
plugin and downloads no shader source at runtime. Instead each production shader was
resolved once, offline, from the WGSL graph at the commit above and committed as a
plain TypeScript module. Two steps, in this order, and nothing else:

1. `@vgpu/wgsl` 0.3.1 `resolveShader()`, with the same identifier-preserving settings
   the upstream bundler loader uses. Names are kept because vgpu matches geometry to a
   shader's vertex attributes by name, so renaming them would silently break the draw;
   keeping them also means the committed shader reads line for line against its source.
2. Rewriting the module paths that resolution records in the output, from the local
   checkout directories they were read from to stable identities — the upstream
   repository path for the prism shaders, the package path for `@vgpu/wgsl-std/color`.
   Comments only; no WGSL, and no identifier, is changed by this step.

Every generated file records its entry point and the full SHA-256 digest of each
module resolved into it, under those stable identities.

### License

```
MIT License

Copyright (c) 2025 Vercel, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
