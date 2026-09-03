# Stake approval feedback sentence

Ticket regent-gu2.11. Base `f64b428`. One founder sentence, shown on every approval the
wallet was actually asked for and did not confirm — all of which Stake currently answers with
silence.

Founder, verbatim: "Stake: 'The wallet token approval step has not been completed yet, check
popup windows or try again' ."

## The approval flow today

A Stake click for an amount larger than the allowance the page was rendered with is two
wallet prompts, in order: the exact REGENT approval, then the stake itself. The page builds
both transactions in the browser; the server only decides whether the click may be built at
all (it withholds the signer, the allowance and the action while the gate is not `:ready`)
and, once a transaction has a hash, watches Base for its result.

The click reserves one slot for the whole attempt and the approval borrows it. There are seven
ways the approval can end:

| how the approval ends | what the page does today |
| --- | --- |
| the customer rejects the wallet prompt (rejection code 4001) | the slot is thrown away — no dialog, nothing on screen |
| the wallet or its RPC fails after the prompt was handed over | the slot is thrown away — nothing on screen |
| the wallet answers with something that is not a transaction hash | the slot is thrown away — nothing on screen |
| the wallet holds the prompt past the two-minute wait | the page returns early for an approval — nothing on screen, and the prompt stays open, so a late answer can still confirm |
| the prompt never reaches the wallet: the wrong network, a chain switch the wallet cannot make, a chain check that times out, or an active wallet that no longer matches the signer | the sender has already worked out the instruction for each of these — "Switch to Base before continuing.", "Use the connected wallet shown on this account." — and the slot is thrown away with it, so nothing is on screen |
| the wallet is released or swapped while the approval is still in its pre-send phase | the attempt dies with the wallet it belonged to: no callback runs at all and the slot is purged — nothing on screen, by design |
| the wallet returns a hash | the approval gets a slot of its own and the server watches it, ending as "REGENT approval confirmed", or — when a confirmed hash is not the end of it — "REGENT approval reverted", "Confirmation is taking longer" or "Confirmation unavailable", each with its BaseScan link |

A wallet that changes under the click is two of those rows, not one, and they behave
differently: if the pre-send check notices the swap, the attempt is refused and named; if the
click's own cancellation gets there first — the usual outcome when the wallet is released —
the attempt is purged without a word. Once the prompt has gone out, neither applies: the
wallet's answer still comes back, and lands in one of the first four rows.

So six of the seven endings are silent. That is the gu2.1 review's P2-1: the customer clicks
Stake, dismisses or misses the approval popup, and the page says nothing at all — no receipt,
no error, and no stake either, because an approval that does not go through also stops the
stake behind it.

Only the last row survives to the server. The approval outcome never reaches Elixir unless it
has a hash, and the dialog the sentence appears in is already on the page. **Nothing on the
server changes, and no Elixir file is touched.**

## What changes

Every ending where the wallet was actually asked — rejected, failed, answered with an
unusable hash, or still holding the prompt when the wait runs out — says the founder's
sentence, in the transaction dialog Stake already uses, under the heading and closing line
that failed stake attempts already carry ("Stake not completed", and "No confirmed Base
transaction changed your staking position"). The sentence is the only new copy on the page.

An approval that never reached the wallet stops being silent too, but it says what the sender
had already worked out and the page was throwing away: "Switch to Base before continuing." or
"Use the connected wallet shown on this account." — the same words the stake itself shows for
the same conditions, and the same words Redeem and Autolaunch show. There is no popup to go
looking for on those endings, the cause has a name, and the customer can fix it. An attempt
that dies with its wallet stays silent, as it is today.

Nothing else about the dialog moves: the stake transaction's own failures, the confirmed
approval receipt, the reverted, delayed and unavailable wordings, the BaseScan link, and the
queue order are all untouched. The transaction gate, the Privy sign-in requirement and the
connected-wallet mismatch notice are untouched.

The sentence is a statement about a step that has not finished, so it has to leave when the
step does:

- **The wallet answers late.** Only the timed-out ending can still come good: the prompt is
  still open with the wallet. If the approval goes out after the sentence is on screen, the
  sentence is replaced where it stands by the same "Transaction submitted" wording and
  BaseScan link the stake itself shows after its own wait, and then by "REGENT approval
  confirmed" when Base confirms it — one dialog, changing what it says, never closing and
  never leaving a blank page while Base is still being asked.
- **The customer put it away first.** A notice dismissed before the wallet answered is
  retired: a rejection or an error arriving minutes later says nothing new, and a modal
  reopening then would read as the attempt the customer has since made. A prompt that is
  answered still speaks, the same way the stake does after its own wait.
- **The customer starts again.** Dismissing the dialog retires the attempt it belonged to, so
  the next Stake click starts with an empty dialog, and a click whose approval succeeds shows
  the approval receipt and never the sentence.

One thing this does not fix, and it is worth writing down: a second attempt's result can sit
behind a first attempt that is still waiting on its wallet, because the dialog shows one
attempt at a time in the order the clicks were made. That queue is older than this change and
is left exactly as it is.

## Tests

- The stake hook's unit tests gain a case per silent ending — rejected, failed, and answered
  with an unusable hash — each checking the sentence word for word, that the stake behind the
  approval was never sent, and that the next attempt's confirmed approval replaces it.
- One case holds the two-minute wait: the sentence appears while the wallet still has the
  prompt, a hash arriving afterwards replaces it in the same open dialog with "Transaction
  submitted" and the BaseScan link without waiting for Base, and the approval receipt then
  takes over in place.
- One case holds a notice the customer dismissed before the wallet rejected it: nothing
  reopens.
- One case holds an approval that never reached the wallet: it shows "Switch to Base before
  continuing." and not the sentence, and nothing is sent.
- The browser spec drives a real rejected approval through the page's wallet stub (which gains
  a rejection seam beside the malformed-answer one it already had) and reads the sentence off
  the rendered dialog. The existing malformed-approval case, which asserted the silence this
  ticket removes, now asserts the sentence instead and keeps everything else it checked.
