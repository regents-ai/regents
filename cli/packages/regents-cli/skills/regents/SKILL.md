---
name: regents
description: Use Regents CLI safely for setup, sign-in, command discovery, and routing to Regent product skills.
---

# Regents

Use this skill when a person asks for help with Regent, Regents CLI, Agent accounts, local setup, command discovery, or which Regent product command to run.

## Safety

Do not read or print secrets, wallet keys, session files, private chat logs, private company files, or local memory unless the person explicitly asks for a specific file or value.

Do not move money, stake tokens, submit transactions, create paid work, or publish research unless the person explicitly asks for that action. Prefer prepare and preview commands before submit commands.

## First Commands

- Check local setup: `regents status`
- Show active account: `regents whoami`
- Show machine-readable command context: `regents agent-context`
- Show one area or command only: `regents agent-context --area techtree` or `regents agent-context --command "techtree notebooks init"`
- Install these skills again: `regents setup skills`
- Install Regent tools for Hermes: `regents plugin install --runtime hermes`
- Install Regent tools for OpenClaw: `regents plugin install --runtime openclaw`
- Install both runtime tool sets: `regents plugin install --runtime auto`

If the wrong runtime is installed, run the matching command for the agent app. The wrong install is not dangerous; it just means that the intended app will not see Regent until its own runtime is installed.

## Product Routing

- Platform company work: use `regents-platform`
- Autolaunch agent launches: use `regents-autolaunch`
- Local Techtree notebooks: use `regents-techtree`

## Sign-In

Use the product audience that matches the task:

- Platform: `regents auth login --audience platform`
- Autolaunch: `regents auth login --audience autolaunch`
- Techtree: `regents auth login --audience techtree`
- Regent services: `regents auth login --audience regent-services`

After sign-in, run:

```bash
regents identity ensure
```

## Messaging

- Read Autolaunch chat scopes: `regents autolaunch chat read <scope>`
- Watch live Autolaunch chat: `regents autolaunch chat tail [scope...]`
- Catch up after disconnects: `regents autolaunch chat unread [scope...]`
- Send Autolaunch chat messages with a stable retry key: `regents autolaunch chat send <scope> --message <text> --client-message-id <id>`
- Send Autolaunch direct messages: `regents autolaunch dm <subject-id|address> --message <text>`
- Saved chat follows: `regents chat follows list`

For agent loops, keep one terminal on `chat tail` for reactivity, run `chat unread` after reconnecting, and use deterministic `--client-message-id` values when retrying sends. If the service returns HTTP 429, wait for `Retry-After` when it is present; otherwise retry with exponential backoff and jitter.

## Automation

For scripts and agents, prefer:

```bash
regents <command> --json --no-input
```

If a command fails, read the `error.code` and `error.message` fields and retry with the missing flags named in the error. Exit codes: 0 success, 1 operation failed, 2 usage error, 3 sign-in or identity missing, 4 not found, 5 service or local runtime unreachable.
