# GB-Pro fitness assessment

Assessment date: 2026-08-06
Scope: the GB-Pro-anchored Climb rehearsal, not a claim about the quality of the public benchmark by itself.

## Evidence reviewed

- The [GeneBench-Pro public Hugging Face package](https://huggingface.co/datasets/openai/genebench-pro-public-package/blob/main/README.md), including its stated package layout, ten released case studies, public answer material, and reference grader contract.
- OpenAI’s [GeneBench-Pro overview](https://openai.com/index/introducing-genebench-pro/), including the synthetic-data design, 129-question inventory, leakage/ablation checks, expert review, and published model results.
- The [GeneBench-Pro paper](https://www.biorxiv.org/content/10.64898/2026.06.29.735386v1), which describes the public set, held-out set, and evaluation design.
- This repository’s GB-Pro records and local fixture tests. The fixture is a protocol-shape test; it is not a live model evaluation and does not stand in for the Hugging Face data.

## Eight-criterion assessment

| Criterion | Finding | Status | What is still needed |
| --- | --- | --- | --- |
| Objective baseline | GeneBench-Pro publishes model results, but this repository has no measured Hermes baseline for the pinned capsule and no predeclared score target for the rehearsal. | Not assessed | Run the pinned baseline through the official paired path and record its score before selecting a treatment. |
| Mid-range difficulty | The public material reports a 28.7% pass rate for GPT-5.6 Sol at its highest reasoning level, which is evidence that the benchmark is not obviously saturated for that system. It is not evidence that the Regent capsule is in a useful mid-range band. | Not assessed | Use the same pinned model, harness, limits, and task batch to establish the baseline band. |
| SKILL.md sensitivity | The source material establishes multi-stage analysis and known targets, but does not show that the intended Regent intervention is a single comprehensible `SKILL.md` change. No baseline/challenger model run exists here. | Not assessed | Run the identical batch with only the skill folder changed and test that the difference is attributable to that change. |
| Public/hidden separability | The Hugging Face package explicitly says its ground truth and grader are public and is intended for case studies, not a hidden-answer leaderboard. The repository now separates public-reference calibration from sealed held-out scoring and binds held-out input content to authored records. | Structural pass; live custody not assessed | Use a separately stored, digest-pinned hidden batch for the official run and prove that the solver receives neither answers nor private verifier state. |
| Same-instance pairing | The local lock derives one matched selection for both arms and pins capsule/template identity, task content, and season rules. A live Prime paired episode has not been run. | Structural pass; live execution not assessed | Execute champion and challenger on the same task instances with identical model, sampling, runtime, permissions, limits, and seeds. |
| Cheap, repeatable runs | The public package supplies self-contained problem directories and a reference grader, and the repository fixture is inexpensive and repeatable. The cost, duration, and failure rate of the official hosted path are unknown. | Partial | Measure repeated official runs, including setup, scoring, trace, and cleanup cost, rather than extrapolating from the public case-study runner. |
| Enough variants | The source benchmark has 129 questions across ten domains, with ten public case studies. The repository fixture has ten calibration references and one authored held-out example; it does not yet demonstrate a sufficient set of comparable newly authored variants. | Not assessed | Author and validate the planned held-out batch, then show that the variants cover the intended capability without duplicating the references. |
| Interpretable failures | The public package includes task metadata, an answer schema, a grader contract, and public case-study reports; the local records preserve task, capsule, and protocol identities. No live traces or failure taxonomy have been inspected for the Regent skill intervention. | Partial | Review paired traces and classify failures into analysis-path, data/QC, output-contract, runtime, and infrastructure causes before making a fitness claim. |

## Decision

GB-Pro is a credible candidate for the rehearsal and the repository has the structural controls needed to keep public calibration separate from hidden scoring. This evidence is not a fitness pass. The decisive criteria—an objective mid-range Regent baseline, measurable `SKILL.md` sensitivity, enough comparable held-out variants, and interpretable paired failures—remain unassessed until live model runs are performed. No productization or uplift claim should be based on this memo alone.

The verify-runtime publication context is a local-development stand-in and provides no in-process trust guarantee. Its protocol and private verifier package preserve publisher, dataset, task-input, answer-commitment, and publication-reference bindings so an independent verifier can compare them with the platform's authoritative, digest-pinned publication record. This makes local forgery tamper-evident against that external record; it does not make the producing Python process tamper-proof.
