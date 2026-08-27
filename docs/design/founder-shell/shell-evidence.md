# Founder shell material and background evidence

This slice supplies the standalone presentation seam for AP-061, AP-062, and AP-064. It does not integrate with the held shell components or either asset entrypoint.

## Material

- `material.css` defines one high-opacity structural material for both theme choices, resolved entirely from the shared design system. Its ground, fills, text basis, hairlines, and elevation name no color of their own.
- Structural and focus geometry stays square at 0–4 px. One material recipe serves every app; product identity arrives through the ground, guide, and accent rather than through panel fills or strokes.
- `shell.css` limits the material class to an explicit structural surface, keeps the background inert, clips overflow safely, and includes a reduced-transparency fallback.
- Base buttons, inputs, and focus outlines read the shared elevated surface, foreground, and accent, so they stay legible on Charcoal, Tangerine Tango, and Powder Blue alike. The operating-system colors stand only on the unbranded public page, which defines none of these tokens and keeps its independent palette.

## Background slots

The TypeScript manifest and Phoenix component expose exactly the eight semantic paths declared by the Design ownership handoff. Unknown values render nothing and are never converted into asset paths. Rendered backgrounds are decorative and excluded from assistive technology.

Each SVG is a transparent monochrome geometry mask. The component supplies its trusted URL as a CSS custom property; `shell.css` names the shared guide token and `material.css` names the shared ground, both selected by the brand the server renders for the route.

The eight SVG files are deliberately replaceable geometry placeholders, not final cutting-mat artwork. Each file says so in its metadata. The founder's 2026-08-26 product framing supersedes the earlier eight-value light/dark guide table. A guide is now the active app's shared accent and follows the app rather than the Light or Dark choice, so both choices show the same ground and guide; the masks preserve a restrained fine/medium/primary opacity rhythm:

| Slots | Ground | Text | Guide |
| --- | --- | --- | --- |
| Home, Regents Labs, Regent record | Charcoal | Platinum | Powder Blue |
| Formation | Charcoal | Platinum | Tangerine Tango |
| Autolaunch | Tangerine Tango | Black | Powder Blue |
| Techtree overview, node, tree | Powder Blue | Charcoal | Charcoal |

The founder-supplied final light and dark mat assets remain outstanding. Replacing these placeholders should preserve the declared paths and slot names.

## Verification

- The focused component test was observed failing before implementation because canonical slots other than Formation rendered nothing.
- `mix test test/ash_platform_web/components/shell_render_test.exs test/ash_platform_web/design_ownership_manifest_test.exs` passed with 6 tests and 0 failures. It covers every canonical slot, decorative semantics, invalid values, ownership convergence, explicit theme selection, placeholder safety, and the square material contract.
- The product-palette adoption reran that focused test and added Chromium coverage that reads the painted ground, text, and mat guide on `/stake`, `/formation`, `/autolaunch`, and `/techtree` in both the Light and the Dark choice, and again after switching apps inside the persistent shell. Ash names no color of its own in any of these stylesheets, and the unbranded public page is unchanged.
- Warnings-as-errors compilation, Elixir formatting, strict TypeScript compilation of `assets/backgrounds/manifest.ts`, XML validation of all eight SVGs, exact canonical file-count/no-dark-reference assertions, and `git diff --check` passed.
- The repository-wide `npm run typecheck` and asset build are currently blocked by concurrent, out-of-scope Privy bridge integration. TypeScript reports JSX configuration and React DOM declaration gaps in `privy_bridge.tsx`; esbuild reports its unresolved optional Solana packages. The new background manifest passes an independent strict TypeScript check.
