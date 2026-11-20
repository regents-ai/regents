---
runtimes: [hermes]
interface: api
date: "2026-10-17"
agent: Hermes
runtime_version: "0.22.2 (revision d923a5eb487a)"
model: gpt-6.1-sol
client: "HTTPX with the SIWA signer from regents-cli 1.10.12"
witnessed: false
results:
  C1: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "Hermes's own approval prompt for its signing client timed out before any signed request was sent."}
  C2: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "No signed request was sent: Hermes's approval prompt for its signing client timed out."}
  C3: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "No signed request was sent: Hermes's approval prompt for its signing client timed out."}
  C4: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "No signed request was sent: Hermes's approval prompt for its signing client timed out."}
  C5: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "No signed request was sent: Hermes's approval prompt for its signing client timed out."}
  C6: {result: PASS, at: "2026-10-17T19:10:15Z", request_id: GN9mztM0PRK2L0YAAWIS, note: "The list was empty, so there was no newest proposal to read."}
  C7: {result: PASS, at: "2026-10-17T19:10:15Z", request_id: GN9mztdAjN_M1U4AAehh}
  C8: {result: BLOCKED, at: "2026-10-17T19:10:15Z", note: "No code password could be asked for: Hermes's approval prompt for its signing client timed out."}
  C9: {result: FAIL, at: "2026-10-17T19:10:37Z", request_id: GN9m0-rRTv_74rUAAelB, note: "Classic #1's page said only \"Coming soon. It has no Keys for sale and can't be joined yet.\" without its terms. The page has given its terms since 17 October's later release."}
---
Hermes ran these checks in the Regents Club from 19:08 to 19:10 UTC and recorded its versions and request ids. Hermes asks its person to approve each new command, and the approval for its signing client timed out, so only the public reads went out. A rerun needs that approval given first.

An earlier run the same day, which recorded no versions, times or request ids, reported passes for the workspace, notebook, chat and poll checks:

- Hermes's saved notebook result: [nb-vebfswbc00whyy1k](https://regents-club.notebooks.keyfleet.ai/results/nb-vebfswbc00whyy1k/run_01M539TC83WX2ZRQFZB4VHH178/1792186134702).
- Hermes's workspace items: task #5, evidence #6, note #7 and dead end #8.
- Hermes's poll: `f9c32cc6-6164-4b01-8c15-99d9802b4388`.
