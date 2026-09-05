# Slice 04 — clean-room proof (`regent-2mf0.4`)

Add deterministic test-only fixtures and focused unit, LiveView, Vitest, and Playwright proof. Browser tests run the test endpoint with a dedicated environment switch and fresh built assets. Add zero-query and forbidden-dependency firewalls plus JS/CSS/HTML budgets from the README.

Acceptance: direct/deep navigation, persistence, cancellation, failure/crash, keyboard, reduced motion, responsive 320px, landmarks, route allowlist, asset budgets, zero DB, and absence of old-platform dependency all pass.
