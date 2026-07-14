# Motion and voxel evidence

The Design handoff provides two stable named exports:

- `ShellMotion` from `./hooks/motion`
- `VoxelDelight` from `./hooks/voxel`

Ash composes them into the existing `designShellHook` after `shellBehavior`. The modules do not replace the entrypoint, navigate, manage focus, or own route and product state. `ShellMotion` responds directly to the composed LiveView lifecycle; Ash does not call the controller manually.

The later Design shell markup provides this stable DOM protocol on the hook root:

- `data-motion-app="formation|autolaunch|techtree|regents-labs"` identifies the currently rendered app.
- `data-motion-source="pointer|keyboard"` identifies the navigation input; keyboard is immediate.
- `data-reduced-motion="true|false"` carries the existing theme-interface preference.
- `data-motion-region` marks each of the five to eight semantic scene regions.
- `data-motion-background` marks the single background slot.
- `data-motion-header-controls` marks the app-local controls inside the fixed header frame.
- `data-voxel-phase` names the current meaningful visual state.
- `data-voxel-meaningful="true|false"` opts a changed phase into the sparse response.
- `data-voxel-source="pointer|keyboard"` keeps keyboard-driven changes static.
- `data-voxel-cell` marks each static 2D cell owned by the current render.

On mount, the hook records the already-correct app and performs no travel. Before a LiveView patch it captures detached visual copies of the outgoing regions. After the patch it compares the old and new app metadata, classifies the change as app-wide or content-only, mounts the pointer-inert copies for the outgoing half of the transition, and removes every copy on completion, interruption, or teardown.

## Motion seam

`createMotionController(root).transition(intent)` accepts element references for the already-authoritative destination. Direct loads, keyboard navigation, and reduced-motion changes settle immediately with no travel. Intra-app changes are a short content-only fade. App changes use a 270 ms total scene budget and one responsive `outQuart` easing throughout: outgoing semantic regions move slightly down while fading, backgrounds and app-local header controls crossfade, and incoming semantic regions enter from the nearest horizontal edge with edge-first timing. The caller groups the shell into five to eight semantic regions; the module does not create per-card cascades.

Each new intent cancels the current handles before reading the next targets. The hook creates disposable, inert outgoing visual copies so the authoritative destination can render immediately; it removes those copies on settlement, interruption, or teardown. Update-driven animations are deliberately kept out of the Anime.js Scope registry, preventing a persistent shell from retaining canceled work. A generation guard prevents stale completion callbacks from settling an older destination. Completion writes exact destination opacity and transform values. Final teardown cancels the active work and reverts the Anime.js 4.5.0 scope, so remount starts clean.

## Voxel seam

`createVoxelController(root, options).respond(response)` keeps its cells static until a meaningful state change. A response lasts 400 ms and uses only cells marked as active accent or neutral. Keyboard and reduced-motion responses remain static. There is no timer, operational pulse, error animation, wallet animation, or component-owned canvas.

`VoxelDelight` makes this behavior available through composition alone. Its root provides `data-voxel-phase`, `data-voxel-meaningful`, and `data-voxel-source`, and contains sparse `[data-voxel-cell]` elements. Mount is static. A changed phase responds only when explicitly marked meaningful. The hook consumes the shared `data-reduced-motion` marker, keeps keyboard-driven changes static, cancels a prior response when another phase arrives, and tears down cleanly.

After every patch, the composed hook replaces its controller so it owns only cells from the current render. An optional `SharedVoxelLayer` interface permits one owner to render a low-frequency shared 3D layer for a meaningful state response. It receives only the active accent-and-neutral palette and is destroyed with the controller. When that owner is absent, the same cells remain a complete static 2D presentation.

## Deterministic proof

Focused Vitest coverage seeks active handles directly, interrupts them with newer intent, invokes completion callbacks deterministically, verifies stale completion cannot win, repeats rapid intents to expose retained-registry growth, checks teardown/remount boundaries, and confirms the no-travel and static fallbacks. TypeScript checks the installed Anime.js 4.5.0 imports and public integration names.

Verified on 2026-07-10 against installed `animejs@4.5.0`: 21 focused tests passed, the four owned TypeScript files passed strict focused type checking, and the owned diff passed whitespace validation. Repository-wide integration gates remain with Ash and the concurrent Privy lane.
