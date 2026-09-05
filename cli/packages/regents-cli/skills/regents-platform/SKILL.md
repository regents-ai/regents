---
name: regents-platform
description: Use Regents CLI for Platform companies, workers, runtimes, work items, and local agent connections.
---

# Regents Platform

Use this skill when a person asks about Regent Platform, company setup, company work, local workers, agent links, runtimes, billing, or hosted company status.

## Safety

Do not read private company files, logs, messages, or local memory unless the person names the exact source to use.

Do not create work, start work, connect workers, change billing, or change runtime state unless the person asks for that action.

## Start

```bash
regents auth login --audience platform
regents identity ensure
regents platform formation status
```

## Company Work

Create work:

```bash
regents work create --regent-id <regent-id> --title "<title>" --description "<details>"
```

Run work:

```bash
regents work run <work-item-id> --regent-id <regent-id> --runner <runner>
```

Watch work:

```bash
regents work watch <run-id> --regent-id <regent-id>
```

## Local Workers

Platform stores work, and the local worker checks for assigned work. The local OpenClaw or Regents CLI process does the work, then reports updates, artifacts, and completion back to Platform.

This does not open remote shell access to the person's machine. Work runs only through the local command the person starts.

Connect OpenClaw:

```bash
regents agent connect openclaw --regent-id <regent-id> --role executor
```

Check a local worker once:

```bash
regents work local-loop --regent-id <regent-id> --worker-id <worker-id> --once
```

Use `--json --no-input` when running from an automated agent.
