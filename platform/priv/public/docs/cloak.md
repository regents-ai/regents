## Overview

Regents Cloak is a native macOS app (Swift 6.2, Apple silicon, macOS 26 or later) built around a clear premise: **choose where an AI conversation runs, see what leaves your Mac, and understand what can link one request to another.**

Cloak does not support normal account-based cloud AI. You can run models locally on Apple silicon with zero accounts and zero payment, or step up explicitly to hardware-verified enclaves, local prompt rephrasing, per-conversation Tor routing, and crypto payments.

> **Beta & audit status (`{{cloak_version}}`, tag `{{cloak_tag}}`):** Cloak is beta software and its privacy protections have not been independently audited yet. Keep wallet balances small, back up or withdraw funds before wiping your Mac, and read [Wallet Security, Failure Modes & 30-Day zkAPI Limit](/docs/cloak/wallets) before transferring or depositing crypto.

## Architecture & Isolation

Cloak coordinates five purpose-built helpers across process and virtualization boundaries:

- **Sandboxed local LLM workers** (`cloak-worker-vmlx` for Apple MLX and `cloak-rewriter-llama` for Metal `llama.cpp`) over framed binary IPC (`RewriterKit`). Neither worker links an HTTP server.
- **Native Rust TEE verifier** (`cloak-near`, built with `dcap-qvl`, `rustls`, `curve25519-dalek`, and `chacha20poly1305`) that independently verifies Intel TDX quotes and NVIDIA GPU attestation verdicts on your Mac before encrypting prompts end-to-end.
- **Bundled Tor daemon** (`tor 0.4.9.16`) listening strictly on an owner-only Unix SOCKS5 socket (`IsolateSOCKSAuth`, remote DNS).
- **Ephemeral, NIC-less Linux arm64 microVM** via Apple's `Virtualization.framework` (`2 vCPU`, `1 GiB RAM`). It has **zero** virtual network interfaces—its only egress is `vsock:9050` straight into the host's Tor socket.
- **Six separate macOS Data Protection Keychain entries** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), scoped via a Developer ID provisioning profile (`367G3Z7G3J.sh.regents.cloak`) so your chat master key, NEAR key, Venice Base wallet, Boundless/Tempo wallet, Venice API key, and zkAPI ETH wallet key stay strictly separated.

Every bundled binary and downloaded model weight is verified by **SHA-256** against Cloak's embedded manifest before execution.

## The Three Modes

Cloak organizes everything into **three modes**: **1. Local AI**, **2. Private Cloud Inference** (choosing between NEAR AI Cloud, Venice AI, Boundless, or zkAPI per thread), and **3. Inference Serving** with EigenLayer's Darkbloom.

| Mode | Where inference runs | What leaves your Mac | Payment / auth | What can link requests |
| --- | --- | --- | --- | --- |
| **1. Local AI** | On your Mac (`vmlx-swift` MLX or `llama.cpp` GGUF) | Nothing during chat once weights are downloaded | Free · no account | Nothing leaves your Mac during inference |
| **2. Private Cloud — NEAR AI Gateway** | [NEAR AI Cloud](https://cloud.near.ai) (`Qwen3.8-27B`, Intel TDX + NVIDIA GPU) | Prompt as written, E2EE v2 encrypted to the hardware-verified enclave (optional Tor) | Your NEAR AI Cloud API key | Your NEAR API key identifies your NEAR account |
| **2. Private Cloud — Venice & Boundless** | [Venice AI](https://venice.ai) or [Boundless](https://boundless.network) on Tempo | Locally rephrased user text over per-conversation Tor circuits | Tempo `USDC.e` (`MPP`), local Base USDC wallet (`x402`), or Venice API key | A reused wallet address, payment channel, or API key can link chats |
| **2. Private Cloud — zkAPI** | Open Anonymity (`zkAPI`) over Tor | Locally rephrased user text over per-conversation Tor circuits | Fresh one-time zero-knowledge key per turn drawn from a reusable ETH deposit — no provider account or linked API key | No reusable provider credential; prompt text, conversation history, and timing can still correlate requests |
| **3. Inference Serving** | On your Mac via [EigenLayer](https://eigenlayer.xyz)'s [Darkbloom](https://darkbloom.dev) | Local Only stays on your Mac; Network + Local serves idle compute to Darkbloom | Earn payouts on idle Apple silicon (`0%` platform cut, macOS 27+) | Linked `console.darkbloom.dev` provider account (Network + Local only) |

### Mode 1: Local AI (`vmlx-swift` MLX + `llama.cpp`)

Once model weights are downloaded, local inference does not send your conversation to an inference provider—no account, no payment, and no remote model calls during chat. (Model downloads from Hugging Face and optional Sparkle update checks are separate app-level network activity.)

- **Fast MLX path:** Powered by [vmlx-swift](https://github.com/osaurus-ai/vmlx-swift) on Apple MLX, running [Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) in [JANGH2](https://huggingface.co/OsaurusAI/Inkling-2-Mini-JANGH2) format (10.21 GB, fits 16 GB+ Macs; measured ~56–64 tok/s on M4 Max 48 GB).
- **GGUF + LoRA path:** Built from [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (`b12633`) with Metal acceleration, supporting 24 GB+ GGUF tiers (13.63 GB / 17.63 GB) and an optional 44 MB uncensored LoRA.
- Both workers preserve multi-turn reasoning history inside your encrypted local chat store and coordinate unified memory with the prompt rewriter automatically.

### Mode 2: Private Cloud Inference (NEAR, Venice, Boundless & zkAPI)

Choose the cloud privacy rail you want per thread—from zero-download hardware TEE enclaves to local prompt rewriting over Tor with crypto payments:

#### NEAR AI Gateway (Hardware TEE)

Runs `Qwen3.8-27B` inside Intel TDX + NVIDIA GPU enclaves on [NEAR AI Cloud](https://cloud.near.ai) ([Dstack TEE](https://github.com/Dstack-TEE/dstack)). Works on 8 GB+ Macs with **0 GB** of model downloads.

Before sending a prompt, `cloak-near`:

1. Fetches live hardware attestation from `cloud-api.near.ai`.
2. Verifies the **Intel TDX quote** locally via DCAP QVL and checks `app_compose` against pinned measurements compiled into Cloak.
3. Verifies the **NVIDIA GPU attestation verdict** from [Intel Trust Authority](https://portal.trustauthority.intel.com) (`PS384` JWT + nonce binding).
4. Pins TLS to the enclave's attested key and seals prompts with **E2EE v2** (`X25519` + `HKDF-SHA256` + `XChaCha20-Poly1305`). Any mismatch fails closed.

Normal NEAR chats send your prompt as written (no local rewriter). Enabling **Tor** allocates two separate Tor circuits per app launch (one for NEAR, one for Intel Trust Authority).

Inside the mode's top tab bar (**Chat | Traces | Insights**), the **Traces** tab exports opt-in **Letta Trajectory v1** `.json` files locally into an owner-only, Time-Machine- and Spotlight-excluded `Traces` folder compatible with [NEAR AI Gateway](https://gateway.near.ai) / [Trace Commons](https://github.com/TraceCommons/trace-commons). Cloak itself never uploads traces; reviewing, redacting, submitting, and earning any NEAR AI credits happen in the standalone NEAR AI Gateway app.

#### Venice AI & Boundless + Tempo (Token Inference)

Sends locally rephrased prompts over per-conversation Tor circuits with no centralized account or credit card required. Switch between [Venice AI](https://venice.ai) and [Boundless](https://boundless.network) + Tempo via the segmented slider in Settings / Funds or the logo toggle right below the chat composer—when an existing thread already has history with the other provider, Cloak prompts you to either **Start New Thread** or **Send All Thread Context**.

- **[Boundless](https://boundless.network) + Tempo (`USDC.e` via HTTP 402 `MPP`):** Uses a dedicated Tempo wallet (`sh.regents.cloak.wallet`) with session payment channels, cooperative instant **Close**, and a unilateral on-chain **Withdraw** escape hatch (15-minute grace period).
- **[Venice AI](https://venice.ai) (Base USDC `x402` or API Key):** Generates a dedicated Base USDC wallet (`sh.regents.cloak.venice-wallet`, kept separate from the Boundless/Tempo wallet to avoid cross-chain address reuse), authenticates with Sign-In with Ethereum (`EIP-4361`), and tops up credit via HTTP `x402` (`EIP-3009`). Cloak defaults to Venice's `Private` and `TEE` model tiers and refuses silent mid-conversation downgrades. **Important distinction:** Venice's zero-retention policy and `Private`/`TEE` tier labels are provider-reported by Venice—Cloak does not independently verify a Venice TEE quote, and a reused wallet or API key can still link requests made with it.

#### zkAPI Anon Inference (One-Time Zero-Knowledge Keys)

Inspired by [Vitalik Buterin's private AI architecture](https://x.com/VitalikButerin/status/2111046730959433793), zkAPI Anon Inference runs [Open Anonymity's zkAPI](https://zkapi.openanonymity.ai) ([ethereum/zkapi](https://github.com/ethereum/zkapi)) on Ethereum Mainnet.

- **Guest-only LUKS2 payment disk:** Your Ethereum Mainnet deposit and `zkAPI` note secrets live inside a 1 GiB sparse LUKS2-encrypted disk image (`~/Library/Application Support/Regents Cloak/pay/disk.img`) mounted only inside the Linux microVM under a dedicated `cloak-pay` user, isolated even from the built-in coding agent.
- **Reusable ETH deposit, fresh one-time key per turn:** One ETH deposit stays active for up to 30 days and funds many sequential turns (only one deposit can be active at a time; to add more ETH, withdraw first and make a new deposit). For every turn, `zkapi-walletd` proves deposit ownership in zero knowledge (`zkapi-v2-note-bound-v1`), leases a fresh one-time provider API key over a per-conversation Tor circuit, and settles actual token cost automatically after the turn (~35–78 s between back-to-back turns) — so the provider never sees a reusable account, wallet, or API key.
- **Deposit & model tiers:** Open Anonymity uses coarse temporary per-turn escrow holds (`$1.00` Tier 1, `$2.00` Tier 3, `$3.00` Tier 5, `$4.50` Tier 25, `$6.00` Tier 100); only actual token cost is spent and unused funds remain in your deposit. A `$5` deposit unlocks models up through Tier 25 (`Claude Fable 5.2`, `Claude Opus 5.5`, `Claude Sonnet 5.5` default), and `$10+` gives headroom for multiple flagship turns. Keep a small ETH buffer in your local wallet outside the deposit to cover Ethereum Mainnet withdrawal gas.
- **30-day vault expiry safety:** `ExpiryGuard` alerts you at Days 20, 25, and 28 and can optionally auto-withdraw 3 days before expiry.
- **Honest limit:** Payment unlinkability does not prevent correlation from identifying text inside prompts, multi-turn conversation history, or request timing.

### Mode 3: Inference Serving (EigenLayer's Darkbloom)

Serve local models on Apple silicon for your own Mac apps or earn payouts on idle compute with [EigenLayer](https://eigenlayer.xyz)'s [Darkbloom](https://darkbloom.dev) (`Off` / `Local Only` / `Network + Local`, macOS 27+). See [Inference Serving (Darkbloom)](#inference-serving-darkbloom) below for verification and telemetry details.

## Privacy Boundaries: What Each Layer Actually Does

Cloak separates its local protections into three explicit layers so you know what each layer does—and what it does not claim to do:

| Layer | Where it runs | What it actually does | Honest limit |
| --- | --- | --- | --- |
| **Local Rewriter (`Qwen 3.5 9B`)** | On-device (`llama.cpp`), before Private Cloud (Venice, Boundless, zkAPI), Pi Agent, and Connected Apps | Paraphrases user writing style, filler, politeness, and irrelevant personal framing; **fails closed** on error | Does **not** redact secrets or PII by itself — preserves names, identifiers, file paths, URLs, numbers, code, and exact quotes verbatim |
| **CloakDoor Privacy Shield** | On-device pre-send (`< 1 ms`) on `http://127.0.0.1:8742/v1` | Deterministic **Secret Tripwire** hard-blocks PEM private keys, API keys/tokens, JWTs, wallet private keys, and `.env` secrets before any remote call or payment; reversible deterministic and user-configured **Private-Terms** alias masking for local paths, emails, Ethereum addresses, ENS names, non-loopback IPs, and custom terms | Deterministic pattern rules and explicit user-configured Private Terms only — **not yet neural NER**. Aliases restore only in human-facing reply text, never in tool-call arguments, and unconfigured free-form sensitive prose can still pass through |
| **Local Access** | Strictly **Local Mode only** (100% offline) | Supplies opt-in approved local folders, PDFs, image OCR, Hermes `USER.md`/`MEMORY.md` memory, and macOS Calendar/Reminders/Contacts to local models | Never available in Private Cloud Inference, the Pi Agent microVM, or Connected Apps — zero code path exists from Local Access to any remote provider |

## Local Prompt Rephrasing

Before any prompt leaves in Token Inference, zkAPI Anon Inference, Local Agent Box, or Connected Apps, Cloak runs a sandboxed local rewriter ([Qwen 3.5 9B](https://huggingface.co/unsloth/Qwen3.5-9B-GGUF), 5.69 GB) on Metal `llama.cpp` with GBNF grammar constraints.

- **What it changes:** Paraphrases writing style, filler, politeness, and irrelevant personal framing, and **fails closed** if rewriting errors (the original text is never sent automatically on failure).
- **What it preserves verbatim:** By design (`Rewrite.swift`), it keeps **names, identifiers, file paths, URLs, numbers, code, and exact quotations verbatim** so technical requests remain accurate—rely on CloakDoor Privacy Shield's deterministic Secret Tripwire and Private Terms (or stay in Local Mode) rather than expecting the rewriter to redact sensitive facts.
- **Memory management:** Automatically unloads from unified memory after 15 minutes of idle time and wakes transparently on the next request.

## Tor Network, MicroVM & Live Cover Traffic

- **Per-conversation Tor circuits:** Token Inference and zkAPI Anon Inference allocate a dedicated `IsolateSOCKSAuth` Tor circuit per conversation with remote DNS resolution.
- **No virtual NIC:** The Linux arm64 microVM has zero `VZVirtioNetworkDevice`. Every outbound packet from `cloak-sender`, `cloak-pay`, or the `Pi` agent exits exclusively over `vsock:9050` into the host's Tor relay.
- **Instant Live Cover Traffic + Local Log:** Toggling Cover Traffic ON or OFF takes effect instantaneously with **zero Tor or VM restart**. Running natively on the host over Tor's Unix SOCKS5 socket, it fetches ~3 random public HTTPS pages per minute from a curated 58-URL pool, each on its own fresh Tor circuit, and appends every fetch to an owner-only (`0600`), Time-Machine-excluded log (`cover-log.jsonl`) that you can inspect, copy, or clear (last hour or all) in **Settings → Advanced**.

## Thread & Mode Isolation

Every chat thread in Cloak is **strictly self-contained**—across different modes and across separate threads within the same mode:

- **No cross-thread access:** Every mode constructs its request solely from the single active thread's history. A cloud model can never read a Local thread or any other thread.
- **Mode locked on turn 1:** Once a thread sends its first turn, its mode (`Local`, `NEAR AI Gateway`, `Token Inference`, or `zkAPI Anon Inference`) is fixed permanently—a Local thread can never be routed to a remote provider.
- **Offline-only Local Access:** Opt-in **Settings → Local Access** sources (basic Mac info, Hermes-compatible `USER.md`/`MEMORY.md` memory, read-only approved local folders, per-turn PDF/document/image-OCR/text file attachments via picker or drag & drop, and macOS Calendar/Reminders/Contacts) are available **exclusively in Local Mode**. Cloud modes, the Pi Agent VM, and Connected Apps have zero code path to Local Access data, and pending local attachments automatically clear when switching threads or leaving Local Mode.
- **What to keep in mind:**
  - Sources enabled under **Settings → Local Access** apply across your **Local Mode** threads only (never cloud threads).
  - Toggling the **Venice ↔ Boundless** pill on an existing **Token Inference** thread with prior history prompts you before sending: you can **Start New Thread** (sharing only the new message) or **Send All Thread Context** (rotating the Tor circuit and sending that one thread's locally rewritten history to the newly selected provider—still isolated from all other threads and modes).
  - Separate threads in **NEAR** (same API key) or **Token Inference** (same Venice or Boundless wallet) never share conversation content, though the provider can see both requests were paid by the same key or wallet. **zkAPI Anon Inference** breaks payment-level linkability per prompt, and **Local Mode** never leaves your Mac.

## Local Agent Box & Connected Apps

### Local Agent Box (`Pi`)

Toggle the hammer icon below the composer in **Token Inference** or **zkAPI Anon Inference** to turn a chat into an autonomous multi-step agent session:

- Runs [Pi Coding Agent](https://github.com/earendil-works/pi) (`v1.3.0` on Node.js `v24.22.2`) inside the ephemeral, NIC-less Linux microVM over `vsock:8030`.
- Shell and file tools (`bash`, `read`, `edit`, `write`) execute strictly inside the throwaway Linux VM—never touching your macOS filesystem.
- Any web access from agent tools is forced through `torsocks` over Tor.
- Model calls loop back over `vsock:8742` into Cloak's host gateway (`CloakDoor`), where user prompts are rephrased locally and paid over Tor.
- Agent workspace state lives in guest memory and resets cleanly when Cloak restarts.

### Connected Apps (`CloakDoor`)

Open **Settings → Connected Apps** to expose a localhost-only OpenAI-compatible API (`http://127.0.0.1:8742/v1`, `acceptLocalOnly = true`, cross-site browser `Origin` requests rejected) with per-app bearer keys (`cloak-<64 hex>`, SHA-256 hashed on disk):

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:8742/v1", api_key="<cloak-app-key>")
model = client.models.list().data[0].id
client.chat.completions.create(
    model=model,
    messages=[{"role": "user", "content": "Review PR #418 for edge cases."}],
)
```

### Routing & Rewrite Boundaries

| Caller | Endpoint / Mode | Payment Rail | Sandbox |
| --- | --- | --- | --- |
| **External Mac app** (Cursor, Cline, Aider, Python) | `http://127.0.0.1:8742/v1` | **zkAPI Anon Inference** | External app keeps its own macOS filesystem & network permissions |
| **Built-in Pi Agent** in zkAPI Anon Inference | `vsock:8030` → `vsock:8742` | **zkAPI Anon Inference** | Sealed NIC-less Linux microVM |
| **Built-in Pi Agent** in Token Inference | `vsock:8030` → `vsock:8742` | **Boundless / Tempo (`USDC.e`)** | Sealed NIC-less Linux microVM |
| **Interactive Chat** (Token Inference) | `vsock:8020` | **[Venice AI](https://venice.ai)** or **[Boundless](https://boundless.network) / Tempo** | NIC-less Linux microVM (`cloak-sender`) |
| **Interactive Chat** (NEAR AI Gateway / Local) | `cloak-near` / local worker | NEAR API key / Free | Native Rust verifier / sandboxed local worker |

**API scope & caveats (`v0.2`):** `CloakDoor` serves `GET /v1/models` and `POST /v1/chat/completions` (OpenAI Chat Completions clients such as Cursor, Cline, Continue, Aider, OpenCode, and T3) with support for `tools`, `tool_choice`, `tool_calls`, `max_completion_tokens`, `reasoning_effort`, inline `data:` images, and buffered `stream: true` SSE (full completion arrives once the turn finishes). Keep two current limits in mind:
- **zkAPI-only for external Mac apps:** External apps calling `http://127.0.0.1:8742/v1` bill exclusively via **zkAPI Anon Inference** (a funded Boundless or Venice balance does not pay Connected Apps yet).
- **No `/v1/messages` or `/v1/responses` yet:** Clients speaking Anthropic `POST /v1/messages` (such as Claude Code) or defaulting to OpenAI `POST /v1/responses` will receive `404` unless configured for Chat Completions. Anthropic `/v1/messages` and Token Inference billing for Connected Apps are planned for `v0.3`.

**What `CloakDoor` checks & rewrites:** Before any remote call or payment, **CloakDoor Privacy Shield** runs a deterministic `< 1 ms` Secret Tripwire (hard-blocking PEM keys, API tokens, JWTs, wallet private keys, and `.env` secrets) and applies reversible deterministic + user-configured **Private-Terms** alias masking (paths, emails, ETH addresses, ENS names, non-loopback IPs, custom terms — explicitly deterministic/Private-Terms matching, **not yet neural NER**; aliases restore only in human-facing reply text, never in tool-call arguments). After Privacy Shield, the **Local Rewriter** paraphrases only `role == "user"` text parts for writing style while system/developer instructions, tool definitions, tool results (including source code), assistant turns, and accepted image/audio/file parts pass through unchanged. An in-memory Activity log lets you inspect Original vs. Sent user text for the latest 20 requests without writing request contents to disk.

## Inference Serving (Darkbloom)

Cloak integrates **Inference Serving** via [Darkbloom](https://darkbloom.dev) ([console.darkbloom.dev](https://console.darkbloom.dev/) · [Eigen Labs / Layr-Labs/d-inference](https://github.com/Layr-Labs/d-inference)) on macOS 27+ to serve local models to your own apps or optionally earn payouts from idle Apple silicon memory:

- Verifies `~/.darkbloom/bin/darkbloom` against Darkbloom's pinned macOS Developer ID Team ID (`SLDQ2GJ6TL`) and leaf certificate hash before talking to its loopback-only control API.
- Provides a unified 3-way **Serving Mode** control (**Off** / **Local Only** / **Network + Local**), computes available memory headroom alongside Cloak, ranks fitting models by live payout rate, monitors live telemetry (daemon uptime, served requests, output tokens, and memory) over SSE, stays in sync with local `darkbloom` CLI changes, and automatically pauses network serving whenever you actively use your Mac.

## Native macOS Shell & Requirements

| Mode | Mac RAM | Model download | Needs `Qwen 3.5 9B` rewriter (5.69 GB)? |
| --- | --- | --- | --- |
| **NEAR AI Gateway** | 8 GB+ | **0 GB** | No |
| **Local (Fast MLX — `Inkling 2 Mini`)** | 16 GB+ | **10.21 GB** | No |
| **Local (GGUF + optional 44 MB LoRA)** | 24 GB+ / 32 GB+ | **13.63 GB** / **17.63 GB** | No |
| **Token Inference, zkAPI Anon Inference, Connected Apps, Agent** | 16 GB+ | **5.69 GB** (`Qwen 3.5 9B`) | Yes |

- **Encrypted local storage & native math:** Saved chats, Connected App hashes, and Tempo deposit state are authenticated with ChaCha20-Poly1305 inside owner-only (`0700`) Application Support folders, rendered with pure-Swift Markdown and LaTeX math. Ephemeral mode (`Save chat history: Off`) keeps new threads strictly in RAM.
- **Menu bar, Quick Prompt, Widgets & CLI:** Native Liquid Glass menu bar panel, Carbon-hotkey Quick Prompt (zero Accessibility permission required), Control Center toggles, Desktop widgets, `cloak` CLI over an owner-only Unix socket, and EdDSA-signed updates via [Sparkle 2.8.1](https://sparkle-project.org).
- **Offline Data:** **Settings → Offline Data** provides progressive **Minimum → Maximum** downloads for **Kiwix Library** (`174 MB → 61 GB`), **DevDocs** (`15 MB → 240 MB`, 1-click linkable into Local Mode), **CourtListener Bulk Data** (`540 KB → 58.3 GB`), **PubMed Central Open Access** (AWS S3 CLI), and [Tinfoil Kit](https://github.com/tudor-city-ventures/tinfoil-kit).

- **Release verification (pinned to `{{cloak_tag}}`):** Every release publishes immutable per-tag SHA-256 checksums for the `.dmg` (`{{cloak_dmg_filename}}`, SHA-256 `{{cloak_dmg_sha256}}`) and installed `Cloak.app/Contents/MacOS/RegentsCloak` binary plus its Apple Developer ID `CDHash` (Team `367G3Z7G3J`) at [Release {{cloak_tag}}]({{cloak_release_url}}) ([SHA256SUMS.txt]({{cloak_sums_url}})) and at [regents.sh/cloak/install]({{origin}}/cloak/install#verify-your-download). Cloak's **Settings → Status** pane displays the running bundle's live SHA-256 and `CDHash` alongside copy-paste `shasum`, `codesign`, and `spctl` commands so you can verify independently using built-in macOS tools.

## Links & Source Code

- Product page: [regents.sh/cloak]({{origin}}/cloak) · Install guide: [regents.sh/cloak/install]({{origin}}/cloak/install)
- Releases (signed & notarized DMGs): [github.com/regents-ai/cloak/releases](https://github.com/regents-ai/cloak/releases)
- Open-source repository: [github.com/regents-ai/cloak](https://github.com/regents-ai/cloak)
- Feedback & questions: [regents.sh/patchbay/cloak](https://regents.sh/patchbay/cloak) · [github.com/regents-ai/cloak](https://github.com/regents-ai/cloak) · [@regents_sh](https://x.com/regents_sh) · [build@regents.sh](mailto:build@regents.sh)
