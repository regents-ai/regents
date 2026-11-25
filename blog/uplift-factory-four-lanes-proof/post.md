---
title: "We Ran 16,126 Scored Agent Trials Across 4B–32B Models for $5.60 in GPU Compute. Here’s What Actually Works."
description: "Empirical proof across Skills, Evals, Environments, and Models: how a $0.08 4B fine-tune beat 32B-Thinking twice, why Skills show a double dissociation across model sizes, how static environment checks missed reward-hacking verifiers, and the multi-turn phase transition between 8B and 32B agents."
date: "2026-11-25"
author: "Techtree"
author_x: "https://x.com/regents_sh"
cover_alt: "Four-panel summary of 16,126 Techtree trials across Models, Evals, Skills, and Environments: 4B SFT beating 32B-Thinking on payment-terms and dependabot, 14B Thinking jumping +60.7 percentage points, Skills showing a model-size double dissociation, and Frontier Harbor authoring lifting sealed-Docker soundness from 12.5% to 95.8%."
draft: false
---

Every week, another thread argues over the same four questions in agent engineering:

1. **Can a tiny 4B fine-tune actually beat a 14B or 32B reasoning model — or does SFT collapse on complex rule sets?**
2. **Do Skills transfer across models, or can a Skill quietly destroy one model while lifting another?**
3. **Can cheap open models auto-generate evaluation sandboxes, or do they silently ship reward hacks?**
4. **When does giving an agent a multi-turn bash loop help — and when does it make the agent *worse*?**

Instead of speculating, we put all four lines of **Techtree’s Uplift Factory** ([Skills](/techtree/services/skills), [Evals](/techtree/services/evals), [Environments](/techtree/services/environments), and [Models](/techtree/services/models)) through a two-campaign empirical stress test on real held-out benchmarks (`regents/payment-terms`, `dependabot`, `gitmoji`, `react-best-practices`, and 39 Harbor Docker environments):

- **16,126 scored attempts** across 10 open model configurations (`4B` to `32B-Thinking`) plus a live frontier ceiling (`gpt-6.2-sol`, `reasoning_effort=high`)
- **9 live `prime-rl v0.11.0` training runs** (8 LoRA SFT + 1 pure verifier-reward GRPO RL with zero gold labels)
- **174 sealed offline Docker containers** (`network_mode=none`, digest-pinned Python)
- **260 adversarial local-judge calibration tests**
- **Total GPU spend: `56.11` Colab Compute Units (~\$5.60 at \$0.10/CU)**

Five sharp, counter-intuitive findings came out of the receipts — including **multiple honest failures** that changed how we build and scope every service.

## 1. A \$0.08–\$0.35 4B Fine-Tune Beat 8× Larger 32B-Thinking Models (Twice) — And Frontier Synthetic Data Fixed the One Benchmark Where SFT Got `+0.0%`

Our first test was a four-rung uplift ladder on `regents/payment-terms` (64 held-out 12-field exact x402 v2 payment-term JSON conversions, disjoint from 1,024 training rows) targeting `nvidia/NVIDIA-Nemotron-3-Nano-4B-BF16`:

| Rung | Method (`Nemotron-3-Nano-4B-BF16`) | Prompt at Inference | GPU Cost | Held-Out Exact (`n=64`) | Completion Tokens | Exact McNemar vs. Rung 1 |
|---|---|---|---:|---:|---:|---|
| **0** | Base 4B (No Skill) | None | `0.00 CU` | `0 / 64` (**0.0%**) | `7,623` | `−54.7 pp` |
| **1** | Base 4B + `SKILL.md` | ~600 tok Skill | `0.00 CU` | `35 / 64` (**54.7%**) | `15,110` | Baseline |
| **2** | **Pure GRPO RL** (`prime-rl v0.11.0`, **zero gold labels**, 640 live rollouts) | ~600 tok Skill | **`3.18 CU`** (A100) | **`49 / 64` (76.6%)** | `15,039` | **`+21.9 pp`** (`+14/−0`, **`p = 1.22e-04`**) |
| **3A** | **LoRA SFT (1 epoch)** (`prime-rl v0.11.0`) | **None (`0` tok!)** | **`3.34 CU`** (A100) | **`63 / 64` (98.4%)** | **`11,627` (−23%)** | **`+43.7 pp`** (`+29/−1`, **`p = 5.77e-08`**) |
| **3B** | *Same SFT weights + `SKILL.md` re-attached* | ~600 tok Skill | `0.00 CU` | `51 / 64` (**79.7%**) | `14,688` | **`−18.7 pp` regression (`p = 1.83e-03`)!** |
| *Ref* | *`Qwen2.5-14B-Instruct` (+Skill, 3.5× larger)* | ~600 tok Skill | — | `91.2%` (`175/192`) | `14,729 / rep` | 4B SFT wins by **`+7.2 pp`** |
| *Ref* | *`Qwen3-32B-AWQ (Thinking)` (+Skill, 8× larger)* | ~600 tok Skill | — | `97.4%` (`187/192`) | **`46,492 / rep`** | 4B SFT edges 32B-Think with **`12×` fewer tokens!** |

Two things jumped off the page immediately:

1. **Pure verifier-reward GRPO RL works on a single Colab A100.** With **zero reference answers** — only our deterministic `payment_terms.scoring` reward across 640 rollouts — `prime-rl v0.11.0` delivered **`+14 gained / 0 regressed` (`p = 1.22e-04`)** for `3.18 CU` (~\$0.32).
2. **SFT crushed it — until we hit a sparse 70-rule benchmark.** On published [Techtree Results](/techtree/results) splits (`×3` repeats, `temp=1.0`, `enable_thinking=False`), 46–48 rows of L4 LoRA SFT (`0.42–0.48 CU`) jumped `dependabot` from `2.6% → 55.3%` and `gitmoji` from `31.6% → 54.7%` (both beating 14B non-thinking models). **But on `react-best-practices` (70 distinct React rules, only 46 training examples), 4B SFT scored `45.9% → 45.9% (+0.0 pp)`.**

### Then We Tested Frontier Zero-Leakage Synthetic Distillation

Could a frontier teacher fix the sparse-data ceiling without touching held-out test cases? We ran `codex gpt-6.2-sol` (`reasoning_effort=high`, `0.00 CU`) to synthesize zero-leakage training examples covering all 70 React rules (`280` clean rows + `46` orig = `326` rows, `0` leaked under strict 6-gram filtering against `final_cases.json`) and all 24 Dependabot ecosystems (`199` clean rows after our filter caught and dropped `1` near-duplicate + `46` orig = `245` rows), then trained **both `Nemotron-3-Nano-4B` and `Qwen3-4B`** on a single cheap Colab L4 (`~0.74 CU` / ~\$0.08 per specialist):

| Benchmark (`final × 3`, `No Skill`) | Base 4B (+Skill) | 46-Row SFT (No Skill) | **Frontier-Distilled 4B SFT (No Skill)** | `Qwen3-32B-AWQ` *(Thinking, +Skill)* | Exact CMH `p` (Distilled vs. Prior) |
|---|---:|---:|---:|---:|---|
| **`dependabot` (`Nemotron-4B`)** | `2.6%` | `55.3%` | **`80.7%`** (`92/114`, `3.8s`) | `78.1%` (`89/114`, `62.0s`) | **`5.27e-09`** *(vs. 46-row SFT)* |
| **`dependabot` (`Qwen3-4B`)** | `1.8%` | — | **`82.5%`** (`94/114`, `2.7s`) | `78.1%` (`89/114`, `62.0s`) | **`2.41e-33`** *(vs. Base+Skill)* |
| **`react-best-practices` (`Nemotron-4B`)** | `40.5%` | `45.9%` (`+0.0`) | **`61.3%`** (`68/111`, `5.0s`) | `91.0%` (`101/111`, `118.7s`) | **`8.49e-04`** *(vs. 46-row SFT)* |
| **`react-best-practices` (`Qwen3-4B`)** | `54.1%` | — | **`65.8%`** (`73/111`, `3.1s`) | `91.0%` (`101/111`, `118.7s`) | **`7.23e-04`** *(vs. Base+Skill)* |

**Read that `dependabot` row twice:** both **4B non-thinking specialists** (`80.7%` and `82.5%`) **beat an 8× larger 32B reasoning model (`78.1%`)** — with **zero Skill prompt**, **zero chain-of-thought tokens**, and **23× faster wall-clock latency (`2.7s` vs `62.0s`)**, for **~8 cents of Colab L4 compute**.

> **The Prompt Alignment Law (Replicated 5 out of 5 Times):**
> Every single time we took a model fine-tuned *without* `SKILL.md` and re-attached `SKILL.md` at inference, accuracy **dropped sharply**: `payment-terms` (`−18.7 pp, p = 1.83e-3`), `Nemotron react` (`−9.0 pp`), `Nemotron dependabot` (`−17.5 pp, p = 2.15e-5`), `Qwen3-4B react` (`−6.3 pp, p = 3.62e-2`), and `Qwen3-4B dependabot` (`−19.3 pp, p = 4.98e-5`). And our GRPO RL model trained *with* `SKILL.md` scored `76.6%` with the Skill and `0.0%` without it. **Match your serving prompt to your training prompt — never mix them.**

## 2. Thinking Beats 2.3× Parameter Scaling — And Single-Pass Evals Lie

Across `6,670` scored attempts spanning `4B` through `32B-Thinking` plus the frontier ceiling (`8.64 CU` total across Colab L4, A100, and G4 96GB Blackwell, `0` errors), three eval myths died on the spot:

| Model (`+Skill`, `×3` repeats; Frontier `×1`) | `payment-terms` | `dependabot` | `gitmoji` | `react-best-practices` |
|---|---:|---:|---:|---:|
| `Qwen2.5-14B-Instruct` (No-Think) | `91.2%` | `13.2%` | **`62.4%`** | `75.7%` |
| `Qwen3-14B` (No-Think) | `90.6%` | `22.8%` | `28.2%` | `80.2%` |
| **`Qwen3-14B` (Thinking)** *(exact same weights!)* | **`100.0%`** (`+9.4`) | **`64.0%`** (**`+41.2`**) | **`88.9%`** (**`+60.7`**) | **`90.1%`** (`+9.9`) |
| `Qwen2.5-Coder-32B-AWQ` (No-Think) | `92.2%` | `49.1%` | `77.8%` | `78.4%` |
| `Qwen3-32B-AWQ` (No-Think) | `92.7%` | `29.8%` | `79.5%` | `79.3%` |
| **`Qwen3-32B-AWQ` (Thinking)** | `97.4%` | `78.1%` (`+48.3`) | `93.2%` | `91.0%` |
| **Frontier Ceiling (`gpt-6.2-sol`, high)** | **`100.0%`** | **`100.0%`** | **`100.0%`** | **`97.3%`** (`177/178 = 99.4%`) |

1. **Test-time thinking beat 2.3× more parameters on all 4 benchmarks.** Simply turning Thinking ON for `Qwen3-14B` crushed `Qwen2.5-Coder-32B` and `Qwen3-32B (No-Think)` across the board (at the cost of `3×` more completion tokens).
2. **Single-pass (`repeats=1`) evals ship noise.** On `payment-terms`, `Nemotron-4B` swung **14.1 percentage points** (`35/64 → 26/64`, `31/64` flaky cases) between repeats, and `Qwen2.5-7B` swung **11.0 pp** (`26/64` flaky cases). Without multi-repeat stratified testing (CMH), single-shot leaderboards are coin flips.
3. **Public leaderboards don’t predict private winners.** `Qwen2.5-14B` beat `Qwen3-14B` by **`+34.2 pp`** on `gitmoji` (`62.4%` vs `28.2%`) while losing to it on `dependabot` (`13.2%` vs `22.8%`). Meanwhile, a calibrated \$0 local 4B judge (`temp=0.0`) scored **`260/260 (100.0%, Cohen’s κ = 1.000)`** across gold answers, subtle near-misses, paraphrases, and **20/20 prompt-injection attacks**.

## 3. The Double Dissociation of Agent Skills: Why One-Size-Fits-All Skills Quietly Break Production

First, we tested letting an open 8B model (`Qwen3-8B`) act as an automated 3-round Skill editor. It truncated `payment-terms/SKILL.md` to 485 characters — deleting the 12-field schema — and collapsed performance to **`0/192 (0.0%)`**. Cheap small models cannot reliably engineer complex Skills.

Next, we ran a true **3-round closed-loop automated Frontier (`gpt-6.2-sol`) SkillOpt** targeting `Nemotron-3-Nano-4B` (strictly blind to selection and final splits, `0` leaks across all 9 revisions, `0.00 CU` for authoring) and evaluated the selection-gated winners across **5 models (`4B` → `32B`)** on Colab G4 (`5.25 CU`, `3,384` scored attempts):

- **The Selection Gate caught overfitting in real time.** On `react-best-practices`, Round 3 climbed monotonically on the working split (`64% → 72% → 76% → 84%`), yet dropped to `42.9%` on Selection. Our gate automatically rejected Round 3 and promoted Round 1 (`65.1%` selection).
- **All 3/3 automated Frontier Skills lifted the target 4B tier (`6/6` positive cells across `Nemotron-4B` and `Qwen3-4B`).**
- **Cutting `dependabot/SKILL.md` by 62% (`13,799 → 5,286` chars)** into a sharp lookup table lifted **4 out of 5 models** — including `Qwen3-8B` (**`+19.3 pp, p = 2.66e-6`**) and `Qwen3-32B-AWQ` (**`+16.7 pp, p = 4.37e-4`**).

**And then we saw the most surprising result of the entire campaign — a textbook double dissociation across model capacity:**

| Model | `payment-terms` (Campaign 1 *Verbose* Skill) | `payment-terms` (Campaign 2 *Compact 4B* `r3`) | `dependabot` (*Lean Table* `r2`) | `react-best-practices` (*Compact 4B* `r1`) |
|---|---|---|---|---|
| **`Nemotron-3-Nano-4B`** *(target)* | **`−18.2 pp`** (`p = 2.93e-5`, blocked!) | **`+16.7 pp`** (`42.2% → 58.9%`, **`p = 3.14e-4`**) | **`+10.5 pp`** (`p = 2.11e-3`) | `+5.4 pp` (`40.5% → 46.0%`) |
| **`Qwen3-4B`** *(4B transfer)* | `−2.6 pp` | **`+9.4 pp`** (`75.0% → 84.4%`, **`p = 1.23e-4`**) | **`+14.0 pp`** (`p = 3.30e-6`) | `+3.6 pp` (`55.9% → 59.5%`) |
| **`Qwen2.5-7B-Instruct`** *(transfer)* | **`+13.0 pp`** (`63.5% → 76.6%`, **`p = 2.05e-3`**) | **`−18.2 pp`** (`63.0% → 44.8%`, **`p = 2.20e-5`**) | `−3.5 pp` | `−5.4 pp` |
| **`Qwen3-8B`** *(transfer)* | `+1.6 pp` | `−1.0 pp` | **`+19.3 pp`** (`11.4% → 30.7%`, **`p = 2.66e-6`**) | `+0.0 pp` |
| **`Qwen3-32B-AWQ`** *(transfer)* | — | **`−14.6 pp`** (`92.7% → 78.1%`, **`p = 2.42e-6`**) | **`+16.7 pp`** (`34.2% → 50.9%`, **`p = 4.37e-4`**) | **`−26.1 pp`** (`76.6% → 50.5%`, **`p = 1.69e-6`**) |

Look at those two `payment-terms` columns side by side:

- **Verbose Skill (Campaign 1):** Crushed `4B` (`−18.2 pp`, `p = 2.93e-5`), **lifted `7B` (`+13.0 pp`, `p = 2.05e-3`)**.
- **Ultra-Compact 4B Skill (Campaign 2):** **Lifted both `4B` models (`+16.7 pp` & `+9.4 pp`, `p <= 3.14e-4`)**, crushed `7B` (`−18.2 pp`, `p = 2.20e-5`) and `32B` (`−14.6 pp`, `p = 2.42e-6`; and `−26.1 pp` on `react`).

**Why?** A 4B model has a tiny attention budget and needs aggressive compression; a 32B model thrives on nuanced edge-case prose that gets stripped away when you compress for 4B. **There is no universal Skill.** Every Skill must be co-optimized and selection-gated on the exact model you run in production.

## 4. Static Environment Checks Passed 98% of Broken Tasks (Including Reward Hacks) — Frontier Models Jumped Docker Soundness from `12.5% → 95.8%`

If you build Harbor/Docker RL environments without executing every single task inside a sealed offline container (`network_mode=none`, digest-pinned image) against both `oracle` (must score `1.0`) and `nop` (must score `0.0`), you are almost certainly shipping broken benchmarks.

We ran the exact same **24 Harbor task specs** (Data Pipelines, Python Bugfixes, SQLite/Log Forensics) through both `Qwen3-8B` and automated Frontier `codex gpt-6.2-sol` (zero manual edits), validating every container locally (`174` sealed Docker containers total, `0` leaked):

| Authoring Pipeline | Specs | Static Harbor `tasks.py` Passed | **Sealed Offline Docker Sound (`oracle=1, nop=0`)** | Leaky Reward-Hack Verifiers (`nop=1.0`) |
|---|---:|---:|---:|---:|
| `Qwen3-8B` — Naive JSON | 24 | `15 / 15` (`100%`) | **`0 / 15` (0.0%)** | 0 |
| `Qwen3-8B` — Hardened JSON | 24 | `6 / 6` (`100%`) | **`0 / 6` (0.0%)** | **1** (`py-fix-lru-cache`) |
| `Qwen3-8B` — Delimiters + 3× Repair | 24 | `21 / 22` (`95%`) | **`3 / 24` (12.5%)** | **1** (`csv-join-left`) |
| **Frontier `gpt-6.2-sol` (Pass 1 Cold, Zero Edits)** | **24** | **`24 / 24` (100%)** | **`23 / 24` (95.8%, `+83.3 pp`!)** | **`0`** |

Static Harbor checks passed **42 of 43** broken 8B tasks — including **two verifiers (`py-fix-lru-cache` and `csv-join-left`) that awarded `1.0` for doing literally nothing (`nop = 1.0`)**. Upgrading the automated author to a frontier model leaped cold Pass-1 Docker soundness from **`12.5%` to `95.8%`** with zero reward hacks (the sole miss, `checksum-manifest-verify`, required mental SHA-256 hashing without tools and was caught cleanly as `oracle=0.0, nop=0.0`).

## 5. The Multi-Turn Phase Transition: Why 4B–8B Agents Collapse in Bash Loops While 32B-Thinking Soars `8×` Higher

Finally, we benchmarked 5 open models across **15 curated sealed-Docker-sound Harbor tasks** (`390` total trials) in two modes: **1-turn blind bash** vs. **6-turn interactive bash** (inspect `/app`, write code, test, iterate, call `DONE`):

| Model | `1-Turn` Blind | `6-Turn` Interactive Bash | Delta (`6T − 1T`) | Avg Turns (`6T`) | CMH `p` | Verifiable RL Headroom |
|---|---:|---:|---:|---:|---|---:|
| `Nemotron-3-Nano-4B` (No-Think) | `2.2%` (`1/45`) | `6.7%` (`3/45`) | `+4.5 pp` | `4.16` | `0.598` | `93.3%` |
| `Qwen3-4B` (No-Think) | `11.1%` (`5/45`) | **`6.7%`** (`3/45`) | **`−4.4 pp` (worse!)** | `4.87` | `0.598` | `93.3%` |
| `Qwen3-8B` (No-Think) | `15.6%` (`7/45`) | **`6.7%`** (`3/45`) | **`−8.9 pp` (worse!)** | `5.22` | `0.221` | `93.3%` |
| `Qwen2.5-Coder-32B-AWQ` | `30.0%` (`9/30`) | **`46.7%`** (`14/30`) | **`+16.7 pp`** | `5.47` | `0.228` | `53.3%` |
| **`Qwen3-32B-AWQ` (Thinking)** | `30.0%` (`9/30`) | **`53.3%`** (`16/30`) | **`+23.3 pp`** | **`3.97`** | **`0.0455`** | **`46.7%`** |

Giving un-trained `4B–8B` non-thinking models an interactive shell **actually made `Qwen3-4B` and `Qwen3-8B` worse** (`15.6% → 6.7%`) while burning `2.3×–5.6×` more tokens looping on broken edits. Crossing into `32B` flipped the sign completely: **`Qwen3-32B (Thinking)` jumped `+23.3 pp` (`p = 0.0455`) to `53.3%`** — **`8×` higher than `4B–8B`**, while finishing in **fewer turns (`3.97` vs `5.47`)** because it verified its own outputs before calling `DONE`. Even then, **`46.7%` of tasks remained unsolved**, leaving massive verifiable headroom for multi-turn RL.

## The Practical Playbook: Which Uplift Should You Actually Buy?

Every line of [Techtree](/techtree/app) now has a sharp empirical boundary:

| Your Bottleneck | Start Here | What Our Receipts Prove | Typical Compute |
|---|---|---|---|
| **"Which model + prompt actually wins on our task, and is our benchmark noisy?"** | **[Evals](/techtree/services/evals)** | Caught `14.1 pp` single-pass noise, `34.2 pp` 14B ranking reversals, and `260/260` local-judge accuracy for `3–6 CU` (~\$0.30–\$0.60). **Start here first.** | `1–6 CU` |
| **"We have subtle workflow rules and want uplift on an existing model with zero weight hosting."** | **[Skills](/techtree/services/skills)** | Automated frontier SkillOpt lifted 4B `+16.7 pp` (`payment-terms`) and 8B/32B `+19.3 / +16.7 pp` (`dependabot`), while Selection Gating blocked `−18.2 to −26.1 pp` cross-size regressions. | `1–5 CU` + frontier editing |
| **"We run high-volume extraction, routing, or tool-calling and want a tiny cheap specialist."** | **[Models](/techtree/services/models)** (`prime-rl` SFT + GRPO RL) | Frontier-distilled 4B SFT beat **32B-Thinking** on *two* benchmarks (`98.4%` & `82.5%`) with zero Skill prompt (`23×` faster, `12×` fewer tokens) for `~0.7–3.3 CU`. Pure GRPO RL lifted `+21.9 pp` with zero gold labels. | `1–15 CU` |
| **"We need an offline verifiable sandbox to evaluate or RL-train coding/ops agents."** | **[Environments](/techtree/services/environments)** (Harbor + Sealed Docker) | Never trust static checks or cheap 8B auto-gen (`0–14%` sound, `nop=1.0` reward hacks). Frontier authoring + sealed offline Docker delivers `95.8–100%` sound tasks with `47–93%` RL headroom. | `0 CU` Docker + `4–12 CU` bench |

**Every number above is backed by reproducible open-source artifacts (`verifiers`, `harbor`, `prime-rl v0.11.0`, `vllm`, digest-pinned Docker images, and stratified CMH / exact McNemar p-values).** Want to run this exact uplift ladder on your own agent workflow? Explore [Skills](/techtree/services/skills), [Evals](/techtree/services/evals), [Environments](/techtree/services/environments), and [Models](/techtree/services/models).
