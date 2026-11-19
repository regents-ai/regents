# Changelog

## Unreleased

- The tests are gone (19 Nov 2026). `mix check` compiles with warnings as errors and
  checks unused locks, formatting and the usage rules.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `RegentSprites.Output.from_frames/1` pins
  the size it reads from outside a binary match, as Elixir 1.20 asks.

## 0.1.0 (2026-10-04)

- Initial release: `RegentSprites.create/2`, `get/1`, `delete/1`, `checkpoint/2` (found
  by its comment, so repeating it makes one checkpoint), `checkpoints/1`, `restore/2`,
  `exec/3` (output split into standard output and error, with the exit code),
  `read_file/3` and `write_file/4` (through commands, base64 out and raw standard input
  in). Checked against the live Sprites API (version 0.0.1-rc48) on 4 October 2026.
