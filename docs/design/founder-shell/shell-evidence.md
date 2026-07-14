# Founder shell material and background evidence

This slice supplies the standalone presentation seam for AP-061, AP-062, and AP-064. It does not integrate with the held shell components or either asset entrypoint.

## Material

- `material.css` defines one high-opacity neutral structural material for both themes. It carries the exact canonical neutral surface subset needed by this standalone app, so its fills, text basis, hairlines, and elevation do not depend on an unimported stylesheet.
- Structural and focus geometry stays square at 0–4 px. Product colors are not used in panel fills or strokes.
- `shell.css` limits the material class to an explicit structural surface, keeps the background inert, clips overflow safely, and includes a reduced-transparency fallback.

## Background slots

The TypeScript manifest and Phoenix component expose exactly the eight semantic paths declared by the Design ownership handoff. Unknown values render nothing and are never converted into asset paths. Rendered backgrounds are decorative and excluded from assistive technology.

Each SVG is a transparent monochrome geometry mask. The component supplies its trusted URL as a CSS custom property; `shell.css` applies the exact approved guide color and `material.css` applies the neutral ground from Regent's resolved root `data-theme`. Explicit Regent Light or Dark therefore cannot disagree with the operating-system preference.

The eight SVG files are deliberately replaceable geometry placeholders, not final cutting-mat artwork. Each file says so in its metadata. The parent CSS supplies the shared neutral light and dark grounds without product tinting, plus the exact approved guide colors; the masks preserve a restrained fine/medium/primary opacity rhythm:

| Slots | Light guides | Dark guides |
| --- | --- | --- |
| Home, Regents Labs, Regent record | `rgb(0, 95, 146)` | `rgb(75, 168, 224)` |
| Formation | `rgb(176, 63, 0)` | `rgb(230, 115, 57)` |
| Autolaunch | `rgb(0, 122, 58)` | `rgb(65, 214, 134)` |
| Techtree overview, node, tree | `rgb(26, 88, 143)` | `rgb(109, 169, 231)` |

The founder-supplied final light and dark mat assets remain outstanding. Replacing these placeholders should preserve the declared paths and slot names.

## Verification

- The focused component test was observed failing before implementation because canonical slots other than Formation rendered nothing.
- `mix test test/ash_platform_web/components/shell_render_test.exs test/ash_platform_web/design_ownership_manifest_test.exs` passed with 6 tests and 0 failures. It covers every canonical slot, decorative semantics, invalid values, ownership convergence, explicit theme selection, placeholder safety, both approved guide palettes, and the square neutral material contract.
- Warnings-as-errors compilation, Elixir formatting, strict TypeScript compilation of `assets/backgrounds/manifest.ts`, XML validation of all eight SVGs, exact canonical file-count/no-dark-reference assertions, and `git diff --check` passed.
- The repository-wide `npm run typecheck` and asset build are currently blocked by concurrent, out-of-scope Privy bridge integration. TypeScript reports JSX configuration and React DOM declaration gaps in `privy_bridge.tsx`; esbuild reports its unresolved optional Solana packages. The new background manifest passes an independent strict TypeScript check.
