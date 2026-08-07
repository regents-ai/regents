# Ash Platform

An isolated Phoenix, LiveView, and Ash foundation for Regent. The first phase contains the
public homepage, exact route catalog, persistent product shell, and deterministic fixture
content. It has no database, production connection, or protected wallet capability.

Run the local checks with:

```sh
mix precommit
npm run typecheck
npm test
npm run test:browser
npm run test:budgets
```

The three `:external` Marimo tests are non-required network checks that reach PyPI; run them with `mix test.external`. They are excluded from `mix precommit` by design so the required gates remain hermetic.
