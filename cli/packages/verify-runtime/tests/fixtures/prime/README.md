# Prime Verifiers recorded fixtures

These fixtures were hand-authored on 2026-08-04 against the adapter's documented
wire contract for the public v1 `Taskset`, `Harness`, `Rollout`, and `Trace` shapes
in Prime Intellect `verifiers==0.2.1`. They validate this adapter against that
documented contract; they do not prove live provider behavior. Live behavior remains
subject to a future authorized substrate smoke.
The pinned PyPI wheel was published from
`PrimeIntellect-ai/verifiers@ab65b6e8d34b03d162408d4bcb854430a86809e6` and has
SHA-256 `6b31b20a0d2b42ec7dbcd6824124d085535aaaed2be36fe6b4fdf59ebf65a42f`.
PyPI's provenance attestation is the version authority.

`completed.json` is a deterministic wire-contract `Trace` v2 result wrapped in the
adapter lifecycle record. Its task data intentionally contains a sealed answer-key
sentinel so the privacy test proves that normalization omits provider task data.
`taskset.json` is the agent-visible half of the one allowed Forge-to-Prime taskset
format; verifier content is separately sealed and is intentionally not fixtured in
plaintext. `lifecycle.json`
records the start/monitor/finalize sequence, and `failure-states.json` exhaustively
records every recognized terminal provider state. `live-derivation.json` records the
post-finalization precedence between a clean harness timeout and a subsequent scoring
`TaskError`. Refresh these files only when the
pinned SDK and this provenance note are deliberately updated together.
