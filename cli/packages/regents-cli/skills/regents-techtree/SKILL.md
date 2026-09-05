---
name: regents-techtree
description: Use Regents CLI to create and pair local paper or freeform notebook workspaces.
---

# Regents Techtree Notebooks

Use this skill when a person asks to create or reopen a local research notebook through Regents CLI.

The shipped Techtree command surface is local-only:

```bash
regents techtree notebooks init \
  --kind <paper|freeform> \
  --title "<title>" \
  --workspace-path <workspace> \
  --json

regents techtree notebooks pair \
  --workspace-path <workspace> \
  --json
```

`init` creates `notebook.json`, `analysis.py`, and a README in the workspace. `pair` validates that workspace and returns the marimo edit command.

No Techtree sign-in is required for these local commands. Do not claim that the CLI publishes, searches, reviews, watches, chats, or runs benchmark workflows; those commands are not shipped.

Do not open or modify other files unless the person names the workspace. Use `--json --no-input` for automated agent calls.
