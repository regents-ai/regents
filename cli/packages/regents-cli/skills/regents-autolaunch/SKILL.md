---
name: regents-autolaunch
description: Use Regents CLI for Autolaunch prelaunch setup, agent launch readiness, launch jobs, subject actions, auctions, and holdings.
---

# Regents Autolaunch

Use this skill when a person asks to prepare, validate, publish, launch, or operate an Autolaunch agent project.

## Safety

Do not submit wallet actions unless the person explicitly asks to submit. Prefer commands that prepare, validate, preview, list, or watch.

Do not read private project files unless the person names the exact folder or file to use.

## Start

```bash
regents auth login --audience autolaunch
regents identity ensure
regents autolaunch agents list --launchable
```

## Guided Launch Path

Prepare prelaunch data:

```bash
regents autolaunch prelaunch wizard
```

Prelaunch plans can include a Techtree evidence packet reference. Treat it as supporting evidence, not as automatic launch approval.

Validate:

```bash
regents autolaunch prelaunch validate --plan <plan-id>
```

Publish the launch page draft:

```bash
regents autolaunch prelaunch publish --plan <plan-id>
```

Run the launch:

```bash
regents autolaunch launch run --plan <plan-id>
```

Watch a job:

```bash
regents autolaunch jobs watch <job-id> --watch
```

## Operations

- Subject details: `regents autolaunch subjects get <subject-id>`
- Auctions: `regents autolaunch auctions list`
- Subject payment links: `regents autolaunch subjects payment-links <subject-id>`
- Contracts: `regents autolaunch registry get --subject <subject-id>`

## Chat And DMs

```bash
regents autolaunch chat list
regents autolaunch chat read system --limit 50
regents autolaunch chat send token:<subject-id> --message "<text>"
regents autolaunch chat unread
regents autolaunch chat subscribe add token:<subject-id>
regents autolaunch dm <subject-id|address> --message "<text>"
```

Use `--json --no-input` when running from an automated agent.
