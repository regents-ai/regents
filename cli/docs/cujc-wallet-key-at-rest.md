# Wallet key at rest (regent-cujc) — decision handoff

Short brief for Sean to dig into. Nothing implemented. bd: `regent-cujc` (held pending this decision).

## Purpose — what we're protecting and why

The agent's wallet private key is the credential that signs SIWA logins and, ultimately, moves
money. "Protect at rest" means: if someone reads the files on the machine (backup, stolen laptop,
leaked container volume, a misconfigured share), they should not walk away with a usable private
key in cleartext. Today the key can live in `keys/agent-wallet.json` as **plaintext** (only
protected by 0600 file permissions), which is the gap the ticket names.

## What's actually true today (this reframes the ticket)

- **The CLI never writes that key file.** There is no writer anywhere in the code. A developer
  places `keys/agent-wallet.json` by hand. The setup wizard steers people to the **env var**
  (`REGENT_WALLET_PRIVATE_KEY`), not the file.
- **Read path is one clean seam.** Everything goes through `WalletSecretSource.getPrivateKeyHex()`,
  selected in two spots. Env var wins if set; otherwise the plaintext file is read. That seam is a
  clean place to slot in an encrypted source.
- So "encrypt the existing store" is slightly a misnomer: there's barely a store. Doing keychain
  encryption properly means **building a new managed store** (encrypted file format + a key to
  encrypt it + a new `regents wallet import` command to create it), not hardening something that
  already exists.

## The hermes / sprite situation (the part that decides this)

The OS-keychain idea only works where there *is* an OS keychain — a developer's Mac/Linux desktop
running the CLI interactively. Our two most important run contexts are **not** that:

- **Sprites** (Platform-hosted agent runtimes) are containers. They receive secrets by **env-var
  injection** (same as `CDP_API_KEY_SECRET`, `STRIPE_SECRET_KEY` in `runtime_config.ex`). No
  keychain exists in a container.
- **Hermes agents** run the CLI as a plugin on an unattended host and inherit the host env. Also
  headless.

Implication: for the contexts that matter most, the key (or the key that decrypts the key) comes
from an **environment variable** regardless. The keychain is a nicety for laptops only. This is the
tension worth your judgment: how much to invest in keychain machinery when sprites/hermes will
always be env-var-driven.

## The options

**A. Full managed encrypted store (the design as drafted).**
New `regents wallet import` writer + AES-256-GCM encrypted file + a 32-byte data-encryption key held
in the OS keychain (`@napi-rs/keyring`, optional dep) with an env-var fallback (`REGENTS_WALLET_KEY`)
for headless. Fail closed if neither key source is present — never a silent plaintext write.
*Pros:* real at-rest protection everywhere, clean laptop UX. *Cons:* biggest surface; introduces a
native optional dep and a whole new command; the keychain path only benefits laptops (sprites/hermes
still use the env var).

**B. Minimal — encrypt if present, no keychain, no new command.**
Encrypt/decrypt the file with a key derived from an env var only. Drop the keychain and the import
command. *Pros:* small; protects the file at rest; works identically on laptop, sprite, and hermes
(env-var everywhere). *Cons:* no laptop convenience layer; still relies on env-var key management.

**C. Rescope — env var + socket auth is the posture; document, don't encrypt the file.**
Treat the plaintext file as unsupported. Standardize on `REGENT_WALLET_PRIVATE_KEY` (already the
wizard's path) and lean on daemon socket auth (`regent-u5gs`) for the live process. *Pros:* smallest;
matches how sprites/hermes already work; nothing new to maintain. *Cons:* if a dev *does* keep a key
file, it stays plaintext; "at rest" for the key itself is only as strong as the env/secret store.

## Held decision: key precedence (only relevant to option A)

If we build the keychain path, which wins when decrypting — env var or keychain?
- **Env-first:** deterministic for unattended agents; a stale env key fails closed rather than
  silently using the keychain. Matches the headless reality.
- **Keychain-first:** a laptop's keychain key can't be overridden by a leaked/injected env var.
Held at your request.

## Recommendation to react to

Given sprites and hermes are env-var-driven no matter what, the keychain in option A buys relatively
little for the highest-value contexts. If the goal is "no plaintext key on disk, everywhere,"
**option B** gets ~90% of the security for a fraction of the surface, and behaves the same across
laptop/sprite/hermes. Reserve **option A** if a first-class developer-laptop keychain experience is
an explicit product goal. **Option C** is right if we're willing to declare the key file unsupported
and make the env var + socket auth the whole story.

Open threads to pin down when you dig in: (1) do we actually want a key *file* at all, or is env-var
the only sanctioned source? (2) is a `wallet import` command desired UX? (3) does u5gs (socket auth)
change how much at-rest file encryption we need?
