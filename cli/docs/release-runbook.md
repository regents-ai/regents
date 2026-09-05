# Regents CLI Release Runbook

This is the package release runbook for `@regentslabs/cli`.

It is not a service deployment guide. The CLI is a published npm package, so the operator job here is to prove the package is shippable, publish it cleanly, and make sure the shipped tarball works on a clean machine.

## What this runbook covers

This runbook covers four things:

1. What must pass before a release is allowed
2. How to do a local release run safely
3. What CI should do on every push
4. What CI/CD should do when it is time to publish

If you remember only one thing, remember this:

- `regents-cli` is released like a package
- `techtree` and `autolaunch` are operated like systems

## Current release gate

Today, the checked-in local release gate is:

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
pnpm check:pack-cli-contents
pnpm test:pack-smoke
```

Those commands are the current definition of "safe to release" for this repo.

They prove:

- the generated OpenAPI-backed types are in sync
- the required release repos, contracts, generated bindings, shared contract mirror, money rows, and incident rows are visible
- the shipped command list still matches the CLI contracts
- the package builds
- the TypeScript surface still checks
- the unit and integration tests pass
- the packed tarball only contains the intended package surface
- the packed npm tarball can be installed and run through the clean-machine smoke path

The packed-install smoke is especially important. A CLI release is not ready unless the tarball that would actually be published can install and complete the expected smoke flow.

## What exists already

The repo already has a local release helper:

- [`scripts/release-cli.sh`](../scripts/release-cli.sh)

That script:

1. runs the release gate
2. requires a clean git worktree before it changes anything
3. bumps the package version
4. stages only the release-owned files
5. creates a release commit message
6. commits
7. optionally pushes

This is useful for a controlled local release.

What it does not do by itself is replace hosted CI and npm trusted-publisher setup. Those are now handled by GitHub Actions plus npm configuration.

## Before any release

Before treating a release candidate as publishable, confirm these conditions:

1. The Techtree backend contract changes, if any, are already merged and stable.
2. The Autolaunch backend contract changes, if any, are already merged and stable.
3. `pnpm check:workspace` passes with every required release repo present.
4. `pnpm check:openapi` passes with no generated-file drift.
5. `pnpm check:pack-cli-contents` proves the tarball only contains the intended package files.
6. `pnpm test:pack-smoke` passes from the package tarball, not just the workspace build.
7. The release notes are clear about operator-facing changes.

If the CLI contract changed, do not publish until the owning backend contract and generated CLI types agree.

## Local release path

This is the current human-operated path.

### 1. Update and validate the branch

```bash
git switch main
git pull --ff-only origin main
pnpm install
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
pnpm check:pack-cli-contents
pnpm pack:cli
pnpm test:pack-smoke
```

Stop immediately if any of those fail.

### 2. Dry-run the release helper first

```bash
bash scripts/release-cli.sh --dry-run
```

Use this to confirm:

- the version bump is what you expect
- the worktree was clean before the helper ran
- the staged files are only the release-owned files
- the generated release commit message is sane

### 3. Run the local release helper

If the dry run looks correct:

```bash
bash scripts/release-cli.sh --no-push
```

This creates the release commit locally without pushing.

Only push after you have reviewed the resulting version bump and staged files.

## What CI does on every push

This repo now has a checked-in CI workflow at:

- [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)

It runs on:

- pull requests
- pushes to `main`

It does the full required gate:

1. install dependencies
2. run `pnpm check:openapi`
3. run `pnpm check:cli-contract`
4. run `pnpm build`
5. run `pnpm typecheck`
6. run `pnpm test`
7. run `pnpm check:pack-cli-contents`
8. run `pnpm test:pack-smoke`

If any of those fail, the branch should not be considered releasable.

## What publish CI/CD does

This repo now has a checked-in publish workflow at:

- [`.github/workflows/publish.yml`](../.github/workflows/publish.yml)

The release model is tag based.

The practical flow is:

1. push to `main`
2. CI runs the full release gate
3. bump the package version in git
4. create and push a matching tag like `v0.2.0`
5. the publish workflow reruns the release gate
6. the publish workflow reruns `pnpm check:cli-contract`
7. the publish workflow rechecks the tarball contents
8. the publish workflow publishes `@regentslabs/cli`
9. the publish workflow creates a GitHub release with generated notes

The publish job should also prove that it is publishing the same package shape that passed `test:pack-smoke`.

In plain English:

- test the exact thing you plan to ship
- only publish if that exact thing passed

## Required external setup

The workflows alone are not enough. Two things still need to be configured outside git:

1. Branch protection on `main`
   Require the CI workflow to pass before merge.
2. npm trusted publishing
   Configure `@regentslabs/cli` on npm to trust this repository and the publish workflow file.

The publish workflow is written for npm trusted publishing, not a long-lived npm token.

## Tagging a release

After the release commit is merged to `main`, create a tag that matches the package version exactly:

```bash
git switch main
git pull --ff-only origin main
git tag v0.2.0
git push origin v0.2.0
```

The publish workflow rejects mismatches. If the package version is `0.2.0`, the tag must be `v0.2.0`.

## Release artifacts that matter

For this repo, the important artifacts are:

- the npm package version in `packages/regents-cli/package.json`
- the packed tarball
- the generated OpenAPI-backed code
- the release notes or changelog entry

Those are the things an operator or downstream user actually feels.

## What this runbook does not cover

This runbook does not replace:

- [`docs/manual-acceptance.md`](./manual-acceptance.md) for operator usage checks
- [`docs/autolaunch-cli.md`](./autolaunch-cli.md) for the Autolaunch command lifecycle
- [`docs/regent-doctor-spec.md`](./regent-doctor-spec.md) for doctor behavior

Those docs explain how the CLI behaves.

This runbook explains how the package itself should be released.

## Bottom line

`regents-cli` is already set up for a disciplined local release flow.

What is still missing is the external repo configuration around the checked-in workflows:

- branch protection
- npm trusted-publisher configuration

That is the right remaining work for this repo because it is a package, not a long-running deployed service.
