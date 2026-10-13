# Third-party notices

Third-party material redistributed inside this repository, and the terms it arrives under.

## vgpu — account holographic card

The foil on the account page's identity card is the shared `Regent.HolographicCard`
from the Regent design system, whose `holographic_card.mjs` adapts the "Holographic
Card" example published with Vercel's `vgpu` project. This repository ships no copy of
that material: `mix regent_ui.assets` stages the module from the pinned design-system
revision at build time, and the attribution and licence text live in the design system's
`THIRD_PARTY_NOTICES.md`. The renderer runs on the `vgpu` 0.6.0 this repository
pins, with `@vgpu/wgsl` 0.6.0 preparing its shader.

## vgpu — homepage world cube

The turning cube on the homepage, under `assets/js/world_cube/` with its `WorldCube`
hook and component, is copied unchanged from ash-template, which records no
third-party source for its scene or shader. It draws through Vercel's `vgpu`, which
is bundled into the script the site serves, with `@vgpu/wgsl` preparing its one shader
in the browser when the cube first draws. Nothing is downloaded at runtime.

- Project: `vercel-labs/vgpu` — https://github.com/vercel-labs/vgpu
- License: MIT

Pinned npm packages, exact versions, no ranges:

| Package         | Version |
| --------------- | ------- |
| `vgpu`          | 0.6.0   |
| `@vgpu/wgsl`    | 0.6.0   |
| `@webgpu/types` | 0.1.69  |

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
