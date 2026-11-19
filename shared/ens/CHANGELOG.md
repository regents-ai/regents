# Changelog

All notable changes to `ens_elixir` should be recorded here.

## Unreleased

- The tests are gone (19 Nov 2026). `mix check` compiles with warnings as errors and
  checks unused locks, formatting and the usage rules.

- idna 8.0.0 (`{:idna, "~> 8.0"}`), which fixes EEF-CVE-2026-117678: an overlong
  `xn--` label is refused at once instead of being decoded first.
  `AgentEns.Normalize.normalize/1` asks for UTS #46 with its STD3 rule, so ASCII
  stays letters, digits and hyphens as before. What changes with idna 8: emoji
  names and symbols such as `≠` are kept instead of refused; an empty label
  (`a..b.eth`, `.eth`), an invalid `xn--` label and a digit-led label beside a
  right-to-left label are refused instead of passed.

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `AgentEns.ERC7930.decode/1` pins the
  lengths it reads from outside a binary match, as Elixir 1.20 asks.

### Added

- `AgentEns.PrimaryName.verified_primary_identity/2`: a wallet's verified primary name and
  its avatar, read only through the ENS avatar service (`metadata.ens.domains`) and given
  only when the service answers with a picture. The address an avatar record names is never
  fetched.

### Fixed

- A picture that was slow to arrive is no longer recorded as no picture. The ENS avatar
  service takes one to five seconds to answer for a name it has not been asked about in
  the last hour, and the check gave up at two. `verified_primary_identity/2` now waits ten
  seconds by default, and a service that does not answer in time is `{:error, reason}`, so
  the caller keeps the picture it holds and asks again. Only the service's own answers
  about the name mean no picture: the 404 it gives a name without one, the 400 it gives a
  name it refuses, and a redirect. Any other answer (busy, broken, or refusing this
  caller, such as a 403) is `{:error, {:avatar_service_status, status}}` for the same
  reason.
- The avatar check no longer follows redirects: a redirect from the ENS avatar service is
  not a picture, so no avatar is given and the server never fetches the address it points to.

### Removed

- `AgentEns.Display` and `AgentEns.Identicon`: no Regent product calls them, and every site
  draws its own labels and pictures.

## 0.1.1 - 2026-05-06

### Added

- Wallet-ready unsigned transaction request envelopes for ENS and ERC-8004 identity actions.
- ERC-8004 registration helpers and richer transaction request metadata.

### Changed

- ENS action preparation now preserves caller and network metadata in stable string-keyed shapes.
- Prepared action keys now produce consistent app-safe request data.

## 0.1.0 - 2026-04-22

### Added

- Standalone Hex package layout for `ens_elixir`, shaped for publishing and documentation.
- Elixir-first ENSIP-25 surface for record-key building, verification, link planning, and unsigned link preparation.
- Rich ENS read helpers for wrapped-name detection, resolver capabilities, addresses, content hashes, TTL, and requested text records.
- General ENS transaction helpers for records, addresses, resolver changes, TTL changes, and registry or wrapped subname actions.

### Changed

- Low-level Ethereum call helpers now live under an internal namespace instead of the public package surface.
- Package errors now use one structured error shape with explicit kind, message, and details.
