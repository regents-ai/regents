---
name: regents-autolaunch
description: Inspect retained legacy Autolaunch commands in Regents.
---

# Regents Autolaunch

Public market operations belong to the standalone `autolaunch` command. Run
`autolaunch commands list --json` for current public capabilities. No sign-in is
needed for those reads or quotes.

The older private and chain commands below remain in Regents pending individual
migration or retirement. Their old HTTP routes are absent from the current
Autolaunch server; inspect the intended backend before attempting them. These
instructions do not establish availability or grant signing authority.

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
- Public auctions (separate package): `autolaunch auctions list`
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
