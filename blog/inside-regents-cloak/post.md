---
title: "Inside Regents Cloak v0.2: Choose What Leaves Your Mac"
description: "A 10-part technical breakdown of Regents Cloak v0.2.3 — Apple Silicon MLX and llama.cpp inference, hardware-attested NEAR TEEs, Tor-routed Boundless and Venice crypto rails, unlinkable zkAPI payments, local prompt rewriting, NIC-less microVM isolation, Pi Agent, CloakDoor, and Darkbloom."
date: "11-25-2026"
author: "Regents Labs"
author_x: "https://x.com/regents_sh"
cover_alt: "The Regents Cloak crown: crisp white squares arranged in three rows on a dark grid background."
draft: false
---

Most AI apps treat privacy as a policy sentence buried in a footer. Even when a model provider promises "zero data retention," your credit card ties every prompt to your legal name, your IP address reveals where you are, your account history links every session together, and your writing style quietly fingerprints you across conversations.

**Regents Cloak does not support normal cloud AI.**

Instead, Cloak is an open-source (MIT), native macOS menu bar app (Swift 6.2, Apple Silicon, macOS 26+) built around a simple premise: **choose where an AI conversation runs, see what leaves your Mac, and understand what can link one request to another.** You can start locally on Apple Silicon with zero accounts and zero crypto—and when you need frontier cloud models, autonomous agents, or coding-tool integrations, you step up explicitly to hardware-attested enclaves, local prompt rephrasing, Tor routing, and accountless crypto payments.

*(Status: `v0.2.3 Beta`. Signed, notarized `.dmg` builds are published on [GitHub Releases](https://github.com/regents-ai/cloak/releases). Cloak's privacy protections have not yet been independently audited—keep wallet balances small, back up or withdraw funds before wiping or switching Macs, and read the [Wallet Security & Recovery](https://regents.sh/docs/cloak/wallets) guide.)*

Here is the complete 10-part technical breakdown of how **Cloak v0.2.3** actually works under the hood—every engine, sandbox boundary, protocol, and open-source project it stands on.

---

## 0. The Architecture: Zero-Trust Boundaries & Open Infrastructure

Cloak is not an Electron wrapper around a REST API. It is a native SwiftUI/AppKit macOS host coordinating five purpose-built helpers across strict process and VM boundaries:

- **Two sandboxed local LLM workers** (`cloak-worker-vmlx` for MLX and `cloak-rewriter-llama` for Metal `llama.cpp`) communicating over a zero-HTTP framed binary IPC (`RewriterKit`)—neither worker even links an HTTP server.
- **A native Rust TEE verifier** (`cloak-near`) that independently checks Intel and NVIDIA enclave proofs before encrypting prompts end-to-end.
- **A bundled Tor daemon** (`tor 0.4.9.16`) listening strictly on an owner-only Unix SOCKS5 socket.
- **An ephemeral, NIC-less Linux arm64 microVM** booted via Apple's `Virtualization.framework` (`2 vCPU`, `1 GiB RAM`). It has **no virtual network card**—its only way off the machine is `vsock` port `9050` straight into the host's Tor socket.
- **Six separate macOS Data Protection Keychain items** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), scoped via a Developer ID provisioning profile (`367G3Z7G3J.sh.regents.cloak`) so your chat encryption key, NEAR API key, Boundless/Tempo wallet, Venice Base USDC wallet, and zkAPI ETH payment disk key live in separate entries without legacy login-keychain prompts across updates.

Every bundled binary and downloaded model weight is verified by **SHA-256** against Cloak's embedded manifest before execution. Every conversation thread locks its mode on turn 1 so a Local thread can never silently route to a cloud provider, and each cloud thread receives its own isolated 32-byte Tor SOCKS5 circuit identity.

![Cloak Powered by Open Infrastructure — Venice + Base, Boundless + Tempo, Ethereum + zkAPI, EigenLayer Darkbloom, NEAR AI, Tor Network, Apple MLX + llama.cpp, and Pi Agent + CloakDoor](/images/cloak/cloak-ecosystem-banner.png)

*Cloak's open-infrastructure stack at a glance. The top row maps the four crypto-backed inference and serving rails—Venice on Base (`USDC` via `x402`), Boundless on Tempo (`USDC.e` via `MPP`), Ethereum + zkAPI (one-time zero-knowledge spend keys), and EigenLayer's Darkbloom (idle Apple Silicon serving). The bottom row maps the four core privacy and execution layers underneath—NEAR AI's hardware-attested Intel TDX and NVIDIA enclaves (`E2EE v2`), the bundled Tor network (`SOCKS5` circuit isolation and cover traffic), Apple MLX + `llama.cpp` (offline chat and local prompt rewriting), and the sealed Pi coding agent + CloakDoor local API.*

---

## 1. Mode 1: Local — On-Device Apple Silicon Inference

**Privacy model:** Once weights are downloaded, local inference does not send your conversation to an inference provider—no account, no payment, and no remote model calls during chat. (Model weight downloads from HuggingFace and optional Sparkle update checks are separate app-level network activity.)

Cloak ships two native local inference runtimes so Apple Silicon Macs get both peak speed and GGUF/LoRA flexibility:

- **Fast path (`vmlx-swift` + Apple MLX):** Powered by [vmlx-swift](https://github.com/osaurus-ai/vmlx-swift) ([Osaurus](https://osaurus.ai)) on top of [mlx-swift](https://github.com/ml-explore/mlx-swift), running Thinking Machines' [Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) in OsaurusAI's [JANGH2](https://huggingface.co/OsaurusAI/Inkling-2-Mini-JANGH2) format (10.21 GB, fits 16 GB+ Macs; measured ~56–64 tok/s on an M4 Max 48 GB).
- **GGUF + LoRA path (`llama.cpp`):** Built directly from [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) (`b12633`, inspired by Georgi Gerganov's local-first push — [X post](https://x.com/ggerganov/status/2121246103312212124)) with Metal acceleration. Supports 24 GB+ GGUF tiers and an optional 44 MB [AtomicChat Unfiltered LoRA](https://huggingface.co/AtomicChat/Inkling-2-Mini-Uncensored-GGUF).

Both workers preserve multi-turn `reasoning_content` inside your encrypted local chat store without cluttering the visible bubble, surface real cold-start (`Starting local model…`) vs. answering progress while loading into Apple Silicon memory, and coordinate unified memory automatically—resting the local prompt rewriter before loading a large chat model on 16–24 GB Macs.

Local Mode also includes an opt-in, strictly offline **Local Access** layer (`Settings → Local Access`, all off by default and completely isolated from cloud modes): a non-identifying Mac hardware/clock snapshot, Hermes-compatible local memory (`USER.md` / `MEMORY.md`, owner-only and excluded from Spotlight and Time Machine), read-only keyword search over approved local folders (strictly skipping dotfiles, `.env*`, and private keys), per-message PDF/document/image (on-device Apple Vision OCR)/code file attachments via picker or drag & drop (showing a `Reattach to use` badge after quit when in-memory extracted text is cleared), and opt-in read-only macOS Calendar, Reminders, and Contacts connectors.

![Regents Cloak macOS app running Local Mode with Inkling 2 Mini (Fast), native LaTeX math rendering, mode-tagged sidebar history, Active Guarantees rail, and Local Access composer controls](/images/cloak/cloak-hero.jpg)

*Cloak's native macOS chat window in **Local · Inkling 2 Mini (Fast)** mode. Answers render Markdown and LaTeX equations natively in pure Swift with one-click copy buttons. On the left, the single `New Chat ⌘N` button sits above mode-tagged conversation history (showing Local, NEAR, and zkAPI threads side by side), while the **Active Guarantees** rail in the bottom-left reports only the protections live on the current thread (`100% on this Mac`, `Local context active`, `Encrypted on disk`, `Zero telemetry`). Along the bottom composer, **Attach** and **Local Access (1)** stay strictly scoped to offline Local Mode.*

---

## 2. Mode 2: NEAR AI Gateway — Hardware-Attested Enclaves & Traces

**Privacy model:** Frontier cloud inference (`Qwen3.8-27B`) inside hardware-verified Intel TDX + NVIDIA GPU enclaves, with end-to-end encryption and optional Tor routing—paid with a standard [NEAR AI Cloud](https://cloud.near.ai) API key (works on 8 GB+ Macs with 0 GB model download; your NEAR API key still identifies your NEAR account, and normal NEAR chats send your prompt as written rather than through the local rewriter).

Most apps trust a cloud provider's TLS certificate and call it a day. Cloak doesn't. Before a single prompt leaves your Mac in NEAR AI Gateway mode, Cloak's Rust verifier (`cloak-near`, built with `dcap-qvl`, `rustls`, `curve25519-dalek`, and `chacha20poly1305`):

1. Fetches live hardware attestation from `cloud-api.near.ai` ([NEAR AI](https://github.com/nearai) / [Dstack TEE](https://github.com/Dstack-TEE/dstack) — [NEAR Protocol X post](https://x.com/NEARProtocol/status/2121041723992216043)).
2. Verifies the **Intel TDX quote** locally via DCAP QVL and checks the `app_compose` measurement against pinned hashes compiled into Cloak.
3. Independently verifies the **NVIDIA GPU attestation verdict** from [Intel Trust Authority](https://portal.trustauthority.intel.com) (`PS384` JWT + nonce binding).
4. Pins the TLS session to the enclave's attested key and seals every prompt with **E2EE v2** (`X25519` + `HKDF-SHA256` + `ChaCha20-Poly1305`) directly to the enclave's public key. If any measurement or pin mismatches, Cloak fails closed.

When you enable the **Tor** toggle, Cloak uses two separate Tor circuits per app launch—one for NEAR and one for Intel Trust Authority.

Inside the mode's top tab bar (**Chat | Traces | Insights**), Cloak also tracks local token counts on-device and supports opt-in **Letta Trajectory v1** local export to an owner-only, Time-Machine- and Spotlight-excluded `Traces` folder—compatible with [NEAR AI Gateway](https://gateway.near.ai) / [Trace Commons](https://github.com/TraceCommons/trace-commons) (`v1.0.19`). Cloak itself never uploads traces; reviewing, redacting, submitting, and earning any NEAR AI credits all happen in the standalone NEAR AI Gateway app while your Cloak chats remain E2EE v2.

---

## 3. Mode 3 (Default): Token Inference — Boundless & Tempo (`MPP`)

**Privacy model:** Accountless per-request payment channels over per-conversation Tor circuits with local prompt rephrasing (`Qwen 3.5 9B`) and **no account or credit card**, using HTTP 402 Machine Payments Protocol (`MPP`) on Tempo Mainnet (`USDC.e`).

Why crypto? Because credit cards tie every prompt to your real identity. In Token Inference mode, [Boundless](https://boundless.network) on [Tempo](https://tempo.xyz) via [MPP](https://mpp.dev) ([tempoxyz/mpp-rs](https://github.com/tempoxyz/mpp-rs) `0.20.0` + `tempo-alloy`) is the default provider for new users:

- Uses its own dedicated Keychain wallet (`sh.regents.cloak.wallet`) kept separate from your Venice Base wallet to avoid cross-chain address reuse (a reused Tempo wallet or channel still links chats funded by it).
- All payment channel signing and HTTPS inference calls run inside the NIC-less Linux microVM (`cloak-sender` over `vsock:8020`) and exit exclusively through Tor with per-conversation SOCKS5 isolation.
- Opens session-based payment channels with cooperative instant **Close** and a unilateral on-chain **Withdraw** escape hatch (15-minute grace period), with deposit state sealed on disk under ChaCha20-Poly1305.
- Also powers Token Inference **Agent** sessions routed through `CloakDoor`.

---

## 4. Mode 3 (Toggle): Token Inference — Venice AI over Tor with Base USDC (`x402`)

**Privacy model:** Remote cloud inference over per-conversation Tor circuits with local prompt rephrasing and **no Venice account or credit card required**.

Right beside Boundless on the Token Inference toggle sits [Venice AI](https://venice.ai) ([Docs](https://docs.venice.ai) · [GitHub](https://github.com/veniceai)):

- Cloak generates a dedicated **Base USDC** wallet stored in its own Keychain entry (`sh.regents.cloak.venice-wallet`), separate from the Boundless/Tempo wallet to prevent cross-chain address reuse.
- All signing (`EIP-4361` Sign-In with Ethereum + `EIP-3009` `TransferWithAuthorization` for Base USDC) and streaming SSE calls execute inside the NIC-less Linux microVM (`cloak-sender` over `vsock:8020`) over per-conversation Tor circuits.
- Funding uses HTTP **`x402`** credit top-ups (`$5`, `$10`, `$20`, or custom) straight from Base USDC—or you can plug in your own Venice API key. A persistent top-up guard (`VeniceTopUpGuard`) survives app restarts and requires a full top-up balance delta before unlocking another payment while a pending `EIP-3009` authorization could still settle.
- Cloak defaults to Venice's **Private** and **TEE** model tiers and refuses silent tier downgrades mid-conversation. Switching between Boundless and Venice mid-thread prompts explicitly before sending an existing conversation's history to the newly selected provider. **Honest distinction:** Venice's zero-retention policy and `Private` / `TEE` tier labels are provider-reported by Venice—unlike NEAR AI Gateway, Cloak does not independently verify a Venice TEE quote, and a reused wallet address or API key can still link requests made with it.

---

## 5. Mode 4: zkAPI Anon Inference — Unlinkable Zero-Knowledge Payments

**Privacy model:** Maximum payment anonymity ("Paranoid Mode"). Every prompt uses a fresh one-time payment credential drawn from a reusable ETH deposit so no provider account, reusable wallet address, or linked API key ties one request to the next—though identifying text inside a prompt, multi-turn conversation history, and request timing can still correlate requests.

Inspired directly by Vitalik Buterin's blueprint for private AI payments ([X post](https://x.com/VitalikButerin/status/2111046730959433793) · [vbuterin/zkapi](https://github.com/vbuterin/zkapi)), zkAPI Anon Inference runs [Open Anonymity's zkAPI](https://zkapi.openanonymity.ai) ([ethereum/zkapi](https://github.com/ethereum/zkapi), Ethereum Mainnet vault `0x4386FDbdA35D995beB3BF8625118Ec5982ec81fe`):

- **Hardened guest-only secrets:** Your Ethereum Mainnet deposit and zkAPI notes live inside a 1 GiB sparse **LUKS2-encrypted disk image** (`payment-disk.img`) mounted only inside the Linux microVM under a dedicated `cloak-pay` user—isolated even from the coding agent sandbox. The 32-byte unlock key lives in macOS Keychain (`sh.regents.cloak.paydisk`).
- **One-time zero-knowledge spend tickets:** Cloak bundles `zkapi-walletd` and its four SHA-256-verified Groth16 proving/verifying keys (13.7 MB). For every single prompt, the guest proves deposit ownership in zero knowledge (`zkapi-v2-note-bound-v1`) and pays with a fresh credential over a per-chat Tor circuit.
- **30-day vault expiry & gas guardrails:** `ExpiryGuard` tracks your 30-day protocol deposit window, schedules native macOS alerts at Days 20, 25, and 28, and can optionally auto-withdraw 3 days before expiry so funds never get stranded. Active-deposit and withdrawal-gas guardrails—plus a non-locking withdrawal fee preview—help prevent accidental stranded deposits or gas shortfalls.

---

## 6. Local Prompt Rewriter (`Qwen 3.5 9B`) & Detail Suggestions

**Privacy model:** Even over Tor with one-time payments, your *prose* gives you away—slang, typos, politeness habits, and irrelevant personal framing act as a stylometric fingerprint.

Before any prompt leaves in Token Inference, zkAPI Anon Inference, Agent, or Connected Apps modes, Cloak runs a sandboxed, zero-HTTP local rewriter ([Qwen 3.5 9B](https://huggingface.co/Qwen/Qwen3.5-9B) · [Unsloth Q4_K_M GGUF](https://huggingface.co/unsloth/Qwen3.5-9B-GGUF), 5.69 GB) on Metal `llama.cpp` with GBNF grammar constraints:

- Rephrases user prose locally into neutral language while **explicitly preserving necessary identifiers, names, paths, URLs, numbers, code, and exact quotations verbatim** (`Rewrite.swift`)—for example, turning *"Ugh, totally fried after my train into Zurich—can you draft a short note pushing my 3pm review on PR #418 to Thursday?"* into *"Draft a brief message requesting to reschedule the 3:00 PM review of PR #418 to Thursday."* That keeps technical requests accurate, and it means you should still avoid pasting secrets you don't want sent.
- Shows a live **Original vs. Sent** word-diff side-by-side when Review mode is enabled, and **fails closed**—if the rewriter stops or errors, the original prompt is never transmitted.
- Automatically unloads from unified memory after 15 minutes of idle time (`AppSettings.freeMemory`) and wakes seamlessly on the next prompt.

---

## 7. Tor Network, NIC-Less Linux MicroVM, & Live Cover Traffic

**Privacy model:** Eliminate IP leaks and DNS leaks at the OS virtualization layer, and blur traffic timing without restarting the stack.

- **Bundled Tor:** Cloak runs [The Tor Project's](https://www.torproject.org) official arm64 `tor 0.4.9.16` ([source](https://gitlab.torproject.org/tpo/core/tor)) bound strictly to a Unix socket with `IsolateSOCKSAuth` and remote DNS resolution. Token Inference and zkAPI Anon Inference use **per-conversation** Tor circuits, Cover Traffic uses a **fresh circuit per fetch**, and NEAR AI Gateway (when Tor is enabled) uses **two per-launch circuits** (NEAR vs. Intel).
- **No NIC, no escape:** The Apple `Virtualization.framework` Linux guest has **zero** `VZVirtioNetworkDevice`. Every outbound connection from `cloak-sender`, `cloak-pay`, or the coding agent goes over `vsock:9050` through the host's `TorRelay` into Tor.
- **Instant Live Cover Traffic + Local Log:** Toggling Cover Traffic ON or OFF takes effect immediately with **zero Tor or VM restart**. Running natively on the host over Tor's Unix SOCKS5 socket (`CoverTraffic.swift`), it fetches ~3 random public HTTPS pages per minute from a curated 58-URL pool, each on its own Tor circuit, and records every fetch to an owner-only append-only log (`cover-log.jsonl`) you can inspect or clear (last hour or all) in `Settings → Advanced`.

![Cloak 5-step verified startup checklist: checking Mac hardware and verified binaries, connecting to Tor, loading local prompt rewriter model, booting isolated Linux VM, and verifying Tor routing, prompt rewriting, and isolation](/images/cloak/cloak-startup.png)

*Cloak's live 5-step verified startup checklist inside the menu bar panel. **Local** (`⌘1`) and direct **NEAR AI Gateway** (`⌘2`) work immediately while paused; when you start Tor-routed modes, Cloak checks hardware and SHA-256 binary hashes, connects to bundled Tor, loads the local `Qwen 3.5 9B` prompt rewriter, boots the NIC-less Linux arm64 microVM, and runs an end-to-end verification pass before letting a single remote prompt leave the Mac.*

---

## 8. Local Agent Box (`Pi`) & Connected Apps Gateway (`CloakDoor`)

**Privacy model:** Bring local user-prompt rephrasing, Tor routing, and crypto payments to autonomous coding agents and existing AI tools on your Mac—with clear boundaries on what is sandboxed and what is rewritten.

- **Local Agent Box:** Toggle the hammer icon in Token Inference or zkAPI Anon Inference (with an inline keyboard-focusable info button explaining the sandbox) to run [Pi Coding Agent](https://github.com/earendil-works/pi) (`v1.3.0` on [Node.js](https://nodejs.org) `v24.22.2`) inside the sealed Linux microVM over `vsock:8030`. Shell and file tools (`bash`, `read`, `edit`, `write`) execute inside the throwaway VM—never touching your macOS filesystem—while model calls loop back over `vsock:8742` (`zkAPI` in zkAPI Anon Inference; Boundless/Tempo `USDC.e` in Token Inference).
- **Connected Apps (`CloakDoor`):** Exposes a localhost-only (`127.0.0.1:8742/v1`, `acceptLocalOnly = true`) OpenAI-compatible API with per-app bearer keys (`cloak-<64 hex>`, only SHA-256 hashes stored on disk) and cross-site browser header rejection. Point **Cursor, Cline, Continue, or Aider** at `http://127.0.0.1:8742/v1` to route their inference over Tor through zkAPI Anon Inference's queue, with buffered SSE support, documented request/message size limits, and a live in-memory Original-vs-Sent inspection log.
- **Clear boundaries:** Connecting an external Mac app changes its **inference endpoint**, not its macOS filesystem or network permissions—only Cloak's built-in `Pi` agent runs inside the Linux VM. And in both Connected Apps and Agent runs (`CloakDoor/Asked.swift`), Cloak rephrases **only user-message text**; system/developer instructions, tool definitions, tool results (including source code), assistant messages, and accepted image/audio/file parts pass through unchanged.

---

## 9. Mode 5: Inference Serving — Darkbloom

Cloak also integrates **Inference Serving** as Mode 5 via [Darkbloom](https://darkbloom.dev) ([Eigen Labs / Layr-Labs/d-inference](https://github.com/Layr-Labs/d-inference)) on macOS 27+, turning idle Apple Silicon unified memory into a local or peer-to-peer inference node:

- Verifies `~/.darkbloom/bin/darkbloom` against a pinned macOS Developer ID Team ID (`SLDQ2GJ6TL`) and leaf certificate hash before talking to its loopback-only control API.
- Provides a unified 3-way **Serving Mode** control (**Off** / **Local Only** / **Network + Local**), computes available unified memory headroom beside Cloak, fetches live per-million-token payout rates from `api.darkbloom.dev/v1/pricing` (`0%` platform cut), ranks all fitting models highest-earner first, stays in sync with local `darkbloom` CLI changes, and monitors live telemetry (daemon uptime, served requests, output tokens, and memory) while pausing network serving automatically whenever you actively use your Mac.

---

## 10. The Native macOS Platform Shell

Everything wraps into a single notarized macOS app built with zero third-party UI frameworks:

- **Encrypted local storage & native math:** Saved chats, Connected App hashes, and Tempo deposit metadata are authenticated with ChaCha20-Poly1305 under `sh.regents.cloak.conversations` inside owner-only (`0700`) Application Support folders, rendered with pure-Swift Markdown and LaTeX math (`$$...$$`, `\[...\]`, `\(...\)`, `$...$`). Ephemeral mode (`Save chat history: Off`) keeps new chats strictly in RAM.
- **Menu Bar, Quick Prompt, Copyable Text & Widgets:** Native Liquid Glass `NSPanel` menu bar control center on macOS 27+ (classic menu on macOS 26) with live 5-step startup progress, native right-click quick actions, inline Quick Prompt via Carbon hotkeys (zero Accessibility permission needed), unified **Settings → Wallets** inspection across all three local wallets, native selectable/copyable text across Settings, Funds, Connected Apps, Inference Serving, Credits, and the menu bar panel, plus Control Center toggles and Desktop widgets communicating via non-sensitive App Group snapshots and control-only deep links (`cloak://action/...`). Local dev builds (`app/build.sh dev`) isolate strictly under `cloak-dev://` and port `8743`.
- **Progressive Offline Data:** `Settings → Offline Data` offers resumable **Minimum → Maximum** downloads for **Kiwix Library** (`174 MB → 61 GB`), **DevDocs** (`15 MB → 240 MB`, 1-click linkable into Local Mode), **CourtListener Bulk Data** (`540 KB → 58.3 GB`), **PubMed Central Open Access** (AWS S3 CLI), and [Tinfoil Kit](https://github.com/tudor-city-ventures/tinfoil-kit).
- **CLI, Signed Updates & Independent Release Verification:** Ships a bundled `cloak` CLI ([Swift Argument Parser](https://github.com/apple/swift-argument-parser)) speaking over an owner-only Unix control socket and EdDSA-verified auto-updates via [Sparkle 2.8.1](https://sparkle-project.org) ([GitHub](https://github.com/sparkle-project/Sparkle)) with system profiling disabled. Every release publishes SHA-256 checksums and Apple Developer ID signing metadata (`SHA256SUMS.txt` and `checksums.json`, Team `367G3Z7G3J`) across GitHub Releases, [regents.sh/cloak/install#verify](https://regents.sh/cloak/install#verify), and live inside Cloak's **Settings → Status** pane with copy-paste macOS `shasum`, `codesign`, and `spctl` commands.

---

## Try Cloak v0.2.3 & Give Feedback

**Choose what leaves your Mac.**

- Download & docs: [regents.sh/cloak](https://regents.sh/cloak) · [regents.sh/cloak/download/mac](https://regents.sh/cloak/download/mac) · [regents.sh/docs/cloak/reference](https://regents.sh/docs/cloak/reference)
- Source code (MIT): [github.com/regents-ai/cloak](https://github.com/regents-ai/cloak) · [tech-stack.md](https://github.com/regents-ai/cloak/blob/main/docs/tech-stack.md)
- Wallet security & recovery: [regents.sh/docs/cloak/wallets](https://regents.sh/docs/cloak/wallets)
- Follow & share feedback on X: [@regents_sh](https://x.com/regents_sh)
- Bug reports & agent-friendly Q&A: [regents.sh/patchbay/cloak](https://regents.sh/patchbay/cloak) · [github.com/regents-ai/cloak/issues](https://github.com/regents-ai/cloak/issues)

---

## Sources, Repositories & Citations

### Key X Posts & Discussions

- **Regents:** [@regents_sh](https://x.com/regents_sh)
- **Vitalik Buterin on private AI & unlinkable payments (zkAPI):** [x.com/VitalikButerin/status/2111046730959433793](https://x.com/VitalikButerin/status/2111046730959433793)
- **NEAR Protocol on hardware-attested private AI:** [x.com/NEARProtocol/status/2121041723992216043](https://x.com/NEARProtocol/status/2121041723992216043)
- **Georgi Gerganov on local inference & llama.cpp:** [x.com/ggerganov/status/2121246103312212124](https://x.com/ggerganov/status/2121246103312212124)

### Core Protocols & Inference Providers

- **Open Anonymity (zkAPI):** [zkapi.openanonymity.ai](https://zkapi.openanonymity.ai) · [github.com/ethereum/zkapi](https://github.com/ethereum/zkapi) · [github.com/vbuterin/zkapi](https://github.com/vbuterin/zkapi)
- **NEAR AI Cloud, Gateway, Trace Commons & Dstack TEE:** [cloud.near.ai](https://cloud.near.ai) · [gateway.near.ai](https://gateway.near.ai) · [github.com/nearai](https://github.com/nearai) · [github.com/TraceCommons/trace-commons](https://github.com/TraceCommons/trace-commons) · [github.com/Dstack-TEE/dstack](https://github.com/Dstack-TEE/dstack) · [portal.trustauthority.intel.com](https://portal.trustauthority.intel.com)
- **Boundless, Tempo & Machine Payments Protocol (MPP):** [boundless.network](https://boundless.network) · [tempo.xyz](https://tempo.xyz) · [mpp.dev](https://mpp.dev) · [github.com/tempoxyz/mpp-rs](https://github.com/tempoxyz/mpp-rs)
- **Venice AI (Base USDC x402):** [venice.ai](https://venice.ai) · [docs.venice.ai](https://docs.venice.ai) · [github.com/veniceai](https://github.com/veniceai)
- **Darkbloom (Eigen Labs):** [darkbloom.dev](https://darkbloom.dev) · [github.com/Layr-Labs/d-inference](https://github.com/Layr-Labs/d-inference)

### Local Engines, Models & Sandbox Infrastructure

- **vmlx-swift & Apple MLX:** [osaurus.ai](https://osaurus.ai) · [github.com/osaurus-ai/vmlx-swift](https://github.com/osaurus-ai/vmlx-swift) · [github.com/ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift)
- **llama.cpp:** [github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- **Inkling 2 Mini & Unfiltered LoRA:** [huggingface.co/thinkingmachines/Inkling-2-Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) · [huggingface.co/OsaurusAI/Inkling-2-Mini-JANGH2](https://huggingface.co/OsaurusAI/Inkling-2-Mini-JANGH2) · [huggingface.co/AtomicChat/Inkling-2-Mini-Uncensored-GGUF](https://huggingface.co/AtomicChat/Inkling-2-Mini-Uncensored-GGUF)
- **Qwen 3.5 9B (Local Prompt Rewriter):** [huggingface.co/Qwen/Qwen3.5-9B](https://huggingface.co/Qwen/Qwen3.5-9B) · [huggingface.co/unsloth/Qwen3.5-9B-GGUF](https://huggingface.co/unsloth/Qwen3.5-9B-GGUF)
- **The Tor Project:** [torproject.org](https://www.torproject.org) · [gitlab.torproject.org/tpo/core/tor](https://gitlab.torproject.org/tpo/core/tor)
- **Pi Coding Agent & Node.js:** [github.com/earendil-works/pi](https://github.com/earendil-works/pi) · [nodejs.org](https://nodejs.org)
- **Sparkle, Swift Argument Parser & Tinfoil Kit:** [sparkle-project.org](https://sparkle-project.org) · [github.com/sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) · [github.com/apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) · [github.com/tudor-city-ventures/tinfoil-kit](https://github.com/tudor-city-ventures/tinfoil-kit)
