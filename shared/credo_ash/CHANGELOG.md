# Changelog

## Unreleased

- The package's own tests are gone (19 Nov 2026); its checks are unchanged. `mix
  check` compiles with warnings as errors and checks unused locks, formatting and the
  usage rules and runs Credo.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.

## 0.1.0

Initial release: eight Credo checks covering Ash policy coverage, the
Ash-shaped N+1, actor placement, direct `Repo` access, unjustified
`authorize?: false`, and `accept :*`.
