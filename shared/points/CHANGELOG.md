# Changelog

## 0.1.0 (unreleased)

- The tests and their database are gone (19 Nov 2026). `mix check` compiles with
  warnings as errors and checks formatting and unused locks.
- The README says what the code does (19 Nov 2026). Only the Regents account is
  named by one `source_app` on every site (`"regents"`); a pairing keeps the site's
  own name, and the once-per-account limit lets one earn. A site that can run
  without its job runner approves no rule offered from a person's action, since the
  offer's job is inserted in that action's transaction.
- `StartAwards` stops before the start (19 Nov 2026): it answers `{:cancel,
  :not_started}`, as it does with no start time, and the first hourly run after the
  start does the work. Once a run succeeds no other runs that day.
- The start run offers again what has not earned (19 Nov 2026). `StartAwards`
  leaves out only accounts whose event for the rule is `confirmed` or `capped`; one
  whose event was refused or still waits is offered again. Any offer of a source
  whose event still waits queues that event's award, one job while it waits, even
  when the offer's facts differ: those facts are turned away as
  `source_identity_conflict` and never replace the waiting event's, and the award
  run awards or refuses the event under its own account's lock.
- The start run's work waits behind live awards (19 Nov 2026). `record_event/2`
  takes `start_run: true`, which only `StartAwards` passes: its checks run at a lower
  Oban priority than live ones, and each award job keeps its check's priority. A
  check job is unique on its four reference fields while it waits, so the same
  reference offered again before it runs, by a site or a repeated start run, is the
  same job.
- `record_event/2` always answers `{:ok, _}` (19 Nov 2026). With the rule on, an
  offer whose reference fields are not each a string of 1 to 512 bytes answers
  `{:ok, %{status: :invalid}}`, queues nothing and logs one warning with the rule,
  the source app and kind and each field's size in bytes; the action it rides in
  goes ahead.
- An award still waiting, or refused, blocks no later offer (Sean, 19 Nov 2026). A
  one-time rule records nothing more only once the account has earned it; the award's
  limits per account and per subject still let only one earn. A source whose event
  ended `rejected` can be offered again: the new facts replace the refused ones on the
  same event, which waits for its own award, and the award job is unique only while it
  waits.
- The start awards cover a site that turned Points on after the start (Sean, 19
  Nov 2026): `StartAwards` asks each start rule's source for `existing(rule_id,
  now)` with the run's own time instead of the start, so what an account has that
  Points has not recorded yet is recorded: from before the start it earns at the
  start, from after it at its real time. The run is unique for a day instead of
  until Oban prunes it, so it runs at most once a day. A site adds its hourly line
  only when it lists a start rule it has a source for.
- The start awards' pairing list is read in pages (19 Nov 2026):
  `RegentAgents.pairings_held_from_before/1` answers a lazy stream of 500 people
  a read, and `StartAwards` walks a start rule's `existing/2` once, so an adapter
  that answers a stream holds one page at a time. A record every site shares, such
  as a pairing, is named by one `source_app` on every site.
- A rule that is off touches nothing (19 Nov 2026): `record_event/2` checks
  whether the rule is on before anything else and answers `{:ok, %{status:
  :disabled}}` whatever the reference. With the rule on, each reference field
  must still be a string of 1 to 512 bytes.
- At the award, the adapter's yes counts only for the account saved at the first
  check (19 Nov 2026). When its fresh facts name another account, no entry is
  written for either: the event ends `rejected` with `award_refused`, and the
  refusal is audited in `source_rejections` as `account_changed`.
- The rule's adapter is asked again, with the same reference, just before an award
  is written, under the account's lock and inside the award's transaction (14 Nov
  2026). `{:ok, _}` awards from the facts and rule saved at the first check, as
  before. `{:error, reason_atom}` writes no entry: the event ends `rejected` with
  `award_refused`, so the summary no longer counts it as pending, and the refusal
  is audited in `source_rejections` with the adapter's reason. `{:retry, _}` or an
  exception rolls the award back and Oban retries, ending `award_failed` after the
  last attempt. `verify/1` reads only the site's saved records and can be asked
  more than once. Start awards take the same path.
- The summary's `done` covers every listed rule, wherever it was earned, not only
  the rules this site earns (Sean, 14 Nov 2026). Each entry is now
  `%{times: n, here: boolean}` instead of a bare count: `times` is the old count,
  and `here` says whether this site earns the rule. `template.first_agent_note` has
  no entry. Earning, intake, start awards and limits are unchanged.
- New one-time rule `autolaunch.first_covered_call` 25, at version 1 (Sean, 14 Nov
  2026). The milestone catalog totals 390.
- The one-time rules change (Sean, 14 Nov 2026). New, at version 1:
  `autolaunch.first_launch` 25, `keyfleet.integration.git` 20,
  `keyfleet.integration.marimo` 20 and `cloak.first_download` 25. At version 2:
  `autolaunch.first_graduation` 25, `keyfleet.first_membership`,
  `keyfleet.first_authorized_agent`, `keyfleet.first_message` and
  `keyfleet.first_vote` 25 each, and `keyfleet.integration.activegraph` 20. Gone:
  `autolaunch.first_settled_auction`, `keyfleet.first_reveal` and
  `keyfleet.integration.twigpine`. The milestone catalog totals 365. Daily rules are
  unchanged.
- A Points page shows every catalog rule except `template.first_agent_note`, which
  the catalog marks `:hidden` and which earns as before. `Rules.listed/0` lists the
  rules a page shows; `Rules.groups/0` groups them by site, in the order Account,
  Autolaunch, Keyfleet, Patchbay, Cloak, as `[%{site: "Account", rules: [...]}, ...]`.
  `Rules.tracked/0` still lists the rules this site earns.
- Points runs in three 30-day seasons and stops by itself after the last (Sean, 13
  November 2026). The count is the program's own, `RegentPoints.Rules.season_count/0`,
  beside the 30-day period; sites set nothing. After `RegentPoints.Rules.ends_at/0`
  an action earns nothing: its check is refused with `rule_not_active`, as before the
  start, and `RegentPoints.StartAwards` cancels with `:ended`. `Rules.active/0` is
  empty, so the summary lists no daily limits, and its `current_period` is `nil`.
  An action done before the end still earns when checked after it; corrections,
  reads and the board carry on, the last season's bonus is tallied after its end,
  and `TallyPeriods` queues no fourth period. `RegentPoints.Seasons` is every site's
  read of the seasons (`at/1`, `phase/1`), moved here from the template so no site
  keeps a copy.
- Each account stores its balance (`accounts.balance_micro`), and the board reads ten
  rows from an index on it instead of summing every entry and bonus of every account
  on each read. That read grew with the whole ledger and, once period bonuses exist,
  scanned the bonus table once per account: 148 seconds at 100,000 accounts, and past
  the 15-second query limit at about 20,000 accounts after one period (local scratch
  data, 12 November 2026). Every entry, new period bonus and bonus that follows the
  ledger moves the stored total by what it added, atomically and in its own
  transaction (`RegentPoints.FollowBalance`). `RegentPoints.leaderboard/1` answers
  `top` only; `totals` and `RegentPoints.Leaderboard.place/2` are gone, and a reader's
  place is `place` in `RegentPoints.summary/1`, one count of the accounts above them.
  Two shared migrations: the column, filled from the ledger, then the index, built
  concurrently.
- Points no longer has a Credits rule (Sean, 6 November 2026): `credits.purchase_settled`,
  its `credits` category and 50-a-day limit, and the per-USDC rate are gone, so a rule
  snapshot's `daily_caps_micro` holds only `activity:account` and repeat actions earn
  at most 100 base Points a UTC day. `Rules.base_micro/1` takes the rule alone. Ledger
  entries no longer read or write `purchased_usdc_atomic`; the column leaves the
  `point_entries` table in a later shared change, once every site runs this version,
  because a site on an older version still reads it.
- `people/1` also answers each account's `wallet` and its `ens_name`, and `name` is
  `nil` when the site shows the wallet in place of a name; leaderboard rows carry
  both. Every wallet is public (Sean, 6 November 2026).
- `RegentPoints.leaderboard/1`: the board a site reads once for every reader, under
  the system actor only. It answers the ten highest totals by public name, each with
  its account id, and `totals`, every positive total, highest first; highest total
  first, then the lowest account id. `RegentPoints.Leaderboard.place/2` gives a
  reader's place from their own total: one more than the totals strictly above it,
  so accounts level on points share a place; an account with none has no place. The
  site keeps the ids and totals on the server. Each site's accounts module adds
  `people/1`.
- Every award, correction and period bonus also broadcasts `points:board`, so a
  site's shared board reads again when any account's total moves.
- `RegentPoints.summary/1` also answers `earned_yesterday_micro`, `done` (how many
  times the account has done each listed action, today for a daily one) and each
  daily limit beside what is left of it. `Amount.format/1` drops a trailing ".00".
- What an account already has at the start earns its one-time points at the start:
  the account, linked X, GitHub and Farcaster accounts and the first paired agent, at
  most 80 points. `RegentPoints.StartAwards` runs from an hourly cron line on every
  site and asks each approved start rule's adapter for `existing(rule_id, starts_at)`;
  each reference goes through `record_event/2` and earns at the start time. Sean,
  6 November 2026.
- `StartAwards` reads the accounts that already have an event for a rule once per
  rule and leaves them out, so a later run offers nothing and costs one read per rule.
- Each catalog entry carries its version. A changed rule keeps its id and gets the
  next version; an account that earned a one-time rule never earns it again, and a
  daily rule's count carries across the change.
- The approved list is the one switch: `Rules.tracked/0` lists only approved rules
  with an adapter, so a site's Points page drops a stopped rule.
- The catalog no longer has `patchbay.first_report`, `patchbay.first_reply` or
  `autolaunch.first_launch`. The milestone catalog totals 250; 240 can be earned at
  launch, with `template.first_agent_note` not approved. Sean, 6 November 2026.
- The guide gives the daily limit the code applies: repeat actions and Credits
  bought earn at most 150 base Points a UTC day together (100 and 50). It said 200.
- The catalog no longer has `identity.ens_selected`, `keyfleet.integration.marimo` or
  `keyfleet.integration.ddocs`. The milestone catalog totals 290. Sean, 4 Nov 2026.
- `RegentPoints.TallyPeriods` emits `[:regent_points, :tally_periods, :finished]`
  at the end of every daily run, with the tallies it queued (`accounts`) and the
  ended `periods`, including a run with nothing to queue, so the owner site can
  export when the tally last ran.
- `RegentPoints.Amount.format/1` is exact at any size. It divided micro-Points
  by 1,000,000 with Decimal's 34-digit precision, so an amount longer than 34
  digits was rounded half up and a page could show more Points than there are
  ("100,000,…,000.00" for "99,999,…,999.99"). It now moves the decimal point six
  places, as `RegentFormat` does since its exact-at-any-size change.
- `RegentPoints.Amount.format/1` shows Points the one Regent way
  (`RegentFormat.amount/1`): "1,234.56", "0.400".
- `RegentPoints.WalletSnapshot.owner/2` answers the account holding a wallet at
  a moment, from the wallet history: `{:ok, account_id}`, or
  `{:error, :unknown_owner}` when no account or more than one held it then. A
  wallet removed earlier has no owner, and the current owner is never used.
  The package's tests now run on an isolated local database
  (`regent_points_test_local*`), created on first run.
