# Cloak Wallet Security, Failure Modes & 30-Day zkAPI Limit

> **Beta software (`v0.2.3 Beta`):** Cloak is public beta software and has not yet undergone an independent security audit. Treat Cloak's built-in wallets as **small working balances only** (for example, $5–$20), not long-term storage.

Cloak creates no Regents account and never has custody of your keys or funds. Every crypto payment rail in Cloak generates a local key on your Mac, isolated per rail, and **never synced to iCloud**.

## How each local wallet is stored

| Mode & Rail | Asset & Network | Where the key lives on your Mac | Backup & Recovery |
| --- | --- | --- | --- |
| **Token Inference · Venice** | `USDC` on **Base** | Device-only macOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never synced to iCloud) | **Export Private Key…** in Funds or **Settings → Wallets** (gated by Touch ID / Mac password) |
| **Token Inference · Boundless** | `USDC.e` on **Tempo** | Separate device-only macOS Keychain item (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, isolated from Venice, never synced to iCloud) | **Export Private Key…** in Funds or **Settings → Wallets** (gated by Touch ID / Mac password — recovers wallet `USDC.e`; close active channels first) |
| **zkAPI Anon Inference** | `ETH` on **Ethereum Mainnet** | Local LUKS2-encrypted payment disk (`~/Library/Application Support/Regents Cloak/pay/disk.img`) sealed by a device-only Keychain key (never synced to iCloud) | No standalone seed export — withdraw active deposits and click **Transfer…** to move ETH out to an external wallet |
| **NEAR AI Gateway** | NEAR AI Cloud API key | Device-only macOS Keychain | Managed in your [NEAR AI Cloud](https://cloud.near.ai) dashboard |

## Failure modes if you do not have a backup

Because Regents never sees, stores, or backs up your keys, **losing local key material without a backup permanently loses unbacked-up funds**:

1. **Wiping macOS, erasing the disk, or losing/breaking your Mac**
   - **No backup:** Any ETH left in your zkAPI wallet, any active zkAPI deposit, any Base `USDC` in your Venice wallet, and any Tempo `USDC.e` in your Boundless wallet or open payment channel are **permanently lost**.
   - **With a backup:** For Venice (Base) and Boundless (Tempo), importing your exported hex private key into any standard EVM wallet recovers on-chain balances at that address. For zkAPI, you must withdraw active deposits and transfer ETH out *before* wiping or switching Macs.
2. **Deleting Keychain items or `~/Library/Application Support/Regents Cloak/`**
   - **Safe:** Deleting or replacing `Cloak.app` in `/Applications` (or updating via Sparkle) **keeps** your wallets and encrypted chats intact.
   - **Destructive:** Manually deleting Cloak's macOS Keychain entries or `~/Library/Application Support/Regents Cloak/` destroys your local keys and encrypted zkAPI payment disk. Unless you already exported your Venice/Boundless private keys (for wallet balances) or withdrew active deposits/channels first, remaining funds cannot be recovered.
3. **Sending the wrong asset or wrong network**
   - Every Cloak deposit address accepts **one exact asset on one exact chain**:
     - Venice: **Base `USDC` only**
     - Boundless: **Tempo `USDC.e` only**
     - zkAPI: **Ethereum Mainnet `ETH` only**
   - Sending any other token or network (such as Arbitrum ETH to the zkAPI address, or Base ETH instead of Base USDC to the Venice address) puts those funds outside Cloak's reach. For Venice and Boundless, exporting the private key into an external EVM wallet may allow recovery; for zkAPI, there is no seed export, so mis-sent assets cannot be recovered.
4. **Unclosed Boundless MPP payment channels**
   - Boundless + Tempo locks `USDC.e` into a per-request MPP payment channel while you chat. Always click **Close** (cooperative instant refund) or **Withdraw** (unilateral 15-minute close) before switching Macs.
5. **Irreversible on-chain transfers & top-ups**
   - Ethereum Mainnet transfers and zkAPI deposits, Base `USDC` x402 top-ups to Venice AI Credit, and Tempo `USDC.e` channel deposits are irreversible on-chain transactions. Verify recipient addresses, amounts, and fees before confirming.

## The 30-day protocol limit on untouched zkAPI deposits

Funding **zkAPI Anon Inference** is a **two-step** flow:

1. **Step 1 — ETH Mainnet Wallet:** ETH sits in your local Cloak wallet under your control until you deposit or transfer it out.
2. **Step 2 — zkAPI Deposit:** Moving ETH from your wallet into your active zkAPI deposit locks that ETH in the Open Anonymity / zkAPI protocol vault for up to **30 days**. **One deposit funds many turns** — on every turn, Cloak proves deposit ownership in zero knowledge and mints a fresh one-time provider API key, then automatically settles actual token cost against your deposit balance. Only one deposit can be active at a time (to add more ETH, withdraw first and make a new deposit).

### Protocol expiry rule & withdrawal gas

- **Within 30 days:** You can withdraw unused ETH from your active zkAPI deposit back to your local ETH wallet at any time. Keep a small ETH buffer in your local ETH wallet outside the deposit to pay Ethereum Mainnet withdrawal gas.
- **After 30 days:** An untouched zkAPI deposit **expires at the protocol layer**, and the zkAPI service operator can claim the remaining deposit whether spent or unspent.

### How Cloak helps — and its limits

- Cloak displays the exact expiry timestamp and escalating warning badges in **Funds** and **Settings → Wallets**.
- Cloak sends local macOS notifications at **days 20, 25, and 28**.
- Cloak offers an **Auto-withdraw 3 days before expiry** toggle in **Funds** and **Settings → Wallets**.
- **Important limit:** Expiry notifications and auto-withdraw can only run while **your Mac is awake and Cloak is open and running**. If your Mac is powered off, asleep, wiped, or Cloak stays paused past day 30, auto-withdraw will not run and untouched deposits can expire at the protocol layer.

## Beta safety checklist

- **Keep balances small:** Start with `$5–$10` (`$5` unlocks up to Tier 25 models in zkAPI; `$5` is the Venice x402 minimum top-up).
- **Back up Venice & Boundless keys right away** via **Export Private Key…** (store offline or in a password manager — never paste a private key into any chat).
- **Sweep funds before wiping or switching Macs:**
  - **zkAPI:** Click **Withdraw** on your active deposit, wait for confirmation, then click **Transfer…** (`Max`) to sweep ETH to an external wallet.
  - **Boundless:** Click **Close** (or **Withdraw**) on any active deposit, then export your key or sweep remaining `USDC.e`.
  - **Venice:** Export your Base private key or spend down your Venice AI Credit.
- **Watch Ethereum Mainnet fees on small deposits:** Cloak displays the exact ETH gas fee and dollar total on the 30-second quote screen before you click **Confirm Deposit**.
