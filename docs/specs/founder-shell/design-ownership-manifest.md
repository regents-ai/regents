# Design ownership manifest

The machine-readable ownership contract is `priv/handoff/founder-shell-design-ownership.json`. It is exhaustive: Design may change only its listed presentation paths. Every listed Ash exclusion remains owned by Ash, including navigation behavior, route identity and precedence, asynchronous content lifecycle, local shell state, and generated route handoff bytes.

The manifest declares the complete route metadata surface, the seven shell assigns and required `content` slot, the System/Light/Dark theme interface, all eight background slots and their exact future asset paths, and copy-paste acceptance commands. Paths that do not yet exist are intentional Design destinations, not scaffold omissions.

Theme ownership is split at the declared interface without shared file ownership. Ash owns persistence and first-paint behavior in `assets/js/theme.ts` and `lib/ash_platform_web/components/layouts/root.html.heex`. Design owns presentation in `lib/ash_platform_web/components/shell/theme_menu.ex` and `assets/css/components/shell.css`, using the declared choices, storage key, and root attributes without changing their behavior.

`post_commit_source_digest` identifies immutable scaffold commit `ebebb7dbfd8602f6f8d302afeb05ca717bf29029`. Design work must start from that committed source boundary and preserve the Ash-owned exclusions below.

The convergence gate is `test/ash_platform_web/design_ownership_manifest_test.exs`. It mechanically checks the closed metadata and shell interfaces, the theme behavior/presentation seam, the eight one-to-one background mappings, inclusion of every background file in the ownership paths, the required Ash exclusions, the command set, and the pre-commit digest placeholder.
