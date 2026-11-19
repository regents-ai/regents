# RegentSprites

Fly Sprites machines for Regent Elixir apps.

- `create/2`, `get/1`, `delete/1` — a machine by name.
- `checkpoint/2`, `checkpoints/1`, `restore/2` — save a machine's disk and put it back.
- `exec/3` — run a command and get what it printed and its exit code.
- `read_file/3`, `write_file/4` — move any bytes in and out.

Every call is tried once; the app decides when to try again, for example from an Oban
job. Nothing here keeps state or runs on its own.

## Install

```elixir
# mix.exs
{:regent_sprites, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "sprites"}
```

```elixir
# config/runtime.exs
config :regent_sprites, token: System.get_env("SPRITES_TOKEN")
```

## Use

```elixir
{:ok, sprite} = RegentSprites.create("wb-h05-baseline")
:ok = RegentSprites.write_file(sprite.name, "/var/wb/settings.json", settings)
{:ok, checkpoint} = RegentSprites.checkpoint(sprite.name, "baseline H05 2026-10-04")

# later
:ok = RegentSprites.restore(sprite.name, checkpoint.id)
{:ok, %RegentSprites.Output{exit_code: 0, stdout: boot_id}} =
  RegentSprites.exec(sprite.name, ["cat", "/proc/sys/kernel/random/boot_id"])
```

Failures come back as `{:error, %RegentSprites.Error{reason: reason}}`; the reasons are
listed in `RegentSprites.Error`.

## What to know about Sprites

- **The comment is a checkpoint's key.** Sprites only names a new checkpoint's id in its
  progress text, and every restore makes a `"pre-restore …"` checkpoint of its own, so
  `checkpoint/2` finds the checkpoint by its comment. Calling it again with the same
  comment returns the same checkpoint and makes nothing, so a job that runs twice is safe.
- **Files move through commands.** Sprites' file endpoints keep showing the disk as it was
  before a restore, and do not see files written by commands. Commands see the true disk,
  so `read_file/3` and `write_file/4` use them.
- **Binary output needs base64.** Sprites marks each piece of command output with one byte
  and does not say how long it is, so output holding bytes 1, 2 or 3 is ambiguous.
  `read_file/3` sends files as base64; do the same for any command that may print binary.
- **Raw bytes must be labelled.** Standard input that is not text is refused unless the
  request says it is raw bytes; `exec/3` always does.
- **Never put a secret in a command.** A command and its arguments travel in the request's
  address. Send a secret as standard input (`:stdin`, or `write_file/4`).
- **A restore can be refused.** Sprites has refused a restore made moments after a
  checkpoint (`{:stream, message}`); the app decides whether to try again.
- **A name in use answers 409.** `create/2` returns `{:sprites, 409, message}`; look the
  machine up with `get/1` if reusing it is what you want.

## Checks

```bash
mix deps.get
mix check
```
