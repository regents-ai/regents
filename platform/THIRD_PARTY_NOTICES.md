# Third-party notices

Third-party material redistributed inside this repository, and the terms it arrives under.

## vgpu — homepage crown renderer

The homepage hero renderer began as the prism scene from Vercel's `vgpu` project.
The camera, scene structure, post-processing, crown mesh, and WGSL committed under
`assets/js/home_prism/` are adapted from that work.

- Project: `vercel-labs/vgpu` — https://github.com/vercel-labs/vgpu
- Commit: `bd3b05101fdd1193a1593558d3c52a0b2b18f31d` ("feat(docs): move prism shader to homepage")
- Source directory: `apps/docs/app/[lang]/(home)/components/prism-background`
- License: MIT

Pinned npm packages, exact versions, no ranges:

| Package          | Version |
| ---------------- | ------- |
| `vgpu`           | 0.3.1   |
| `@vgpu/wgsl`     | 0.3.1   |
| `@vgpu/wgsl-std` | 0.3.1   |
| `@webgpu/types`  | 0.1.69  |

### What was taken

Camera, scene graph and the production shaders — `glass-common`, `environment`,
`copy-linear`, `bloom`, `bloom-upsample`, `present` — together with the shared
`scene` uniform block and `@vgpu/wgsl-std/color`.

The laser sheet and the field of squares behind the page arrived by way of the
Techtree platform, which adapted them from the same prism background: the CPU beam
tracer in `assets/js/home_prism/crown-light.ts`, its additive sheet shader
`assets/js/home_prism/shaders/crown-light.ts`, and the field composition in
`assets/js/home_field/shader.ts`. The camera in `assets/js/home_prism/camera.ts`
came from Techtree whole, so that the crown can be framed to one side of the page
copy.

The current visible solid is the Regents 3/5/5 crown. Its mesh and crown-specific
front/back/common glass shaders were supplied in the standalone
`regents-vgpu-crown` source bundle, whose sorted source-bundle digest is
`f1235c2f53db30addf70846bb4d4c8675277eeba0794c8c583de7bb63d6678ed`.
That bundle identifies its crown work as a structural adaptation of the same VGPU
prism example at the pinned commit above. Its exact source SHA-256 values were:

| Source | SHA-256 |
| ------ | ------- |
| `crown-types.ts` | `cb5e9c0adb24b68e09336f1c1c4b0fedb73545567ab7671b4699730789e2dbd8` |
| `crown-mesh.ts` | `95c99de93bc9c33a03c6cc6da36210a9e30af70517ec2a56726d22a0481993f2` |
| `crown-glass-common.wgsl` | `aa0df4059483fd58b9fd181cb8465304a5125b2934128eaa9f932b74d93d0de4` |
| `crown-glass-front.wgsl` | `2522c4ecd14b3966c5278f01689f82b08291bb80561557bda5d82198c2191bac` |
| `crown-glass-back.wgsl` | `f1ef00628482d8e7ddfb2e41c4c86ac5fdd31a58f32e2b6246a5fdd241d21df5` |
| `crown-mesh.test.ts` | `b415cec1bf6f90f79d37ab4797556bb0c32d00d733d5d2981e4221a594638be7` |
| `THIRD_PARTY_NOTICES.md` | `da6af60647c0f6601d64782e18cc682c6270b6e63e4e7e02fd41c83977340ec3` |

`crown-types.ts` has since been adapted for the laser pass: it carries the beam and
sheet constants and the retuned glass and bloom settings the three white lasers need.
The digest above is the value the bundle arrived with.

The versioned `environment.wgsl` remains the exact upstream file at the pinned
commit and path above, SHA-256
`382157376c95468a7a9ad1b5c50ba4d630aa3ec15589e7c86041b074d6f54d90`.
The exact `@vgpu/wgsl-std` 0.3.1 color input has SHA-256
`9a65713c22469c7aea102286385e00d5ac8c5986bb415384af779c04fbf88401`.

### What was left behind

The React component and its lazy control panel, the debug control schema and every
value range that fed it, the environment-reflection debug renderer and its axes
shader, the shader validation module, the wireframe and light-wireframe paths and
shaders, the alternate wall/back-face/caustic view modes, the headless thumbnail and
gallery renderer, and the upstream test suites.

The upstream triangle prism mesh, its spectral light sheet, the shared optics
helpers and the `wall`, `light`, `glass` and `glass-back` shaders are gone. The
crown has its own mesh, its own glass shaders and, now, its own beam tracer, so
none of the triangle-era material was reachable.

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

The crown shaders tighten that process further. Their raw source graph is committed
under `assets/js/home_prism/shaders/source/` and resolved from an in-memory module
map with the stable `/regents/home-crown/` and `/vendor/@vgpu/wgsl-std/` identities,
`validate: "off"`, and `minify: false`. No developer path enters the graph and no
path rewrite follows resolution. Focused tests verify every raw digest and regenerate
both TypeScript shader modules byte-for-byte.

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
