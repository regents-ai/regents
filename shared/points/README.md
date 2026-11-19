# Regent Points

Share one account-linked Points ledger across Regent sites. The package owns the
`regent_points` schema, rules, award calculations, corrections and NFT reads.
Each host supplies verified source facts, its account lookups, Repo, PubSub and
Oban instance. Including the package starts no server, worker loop or migration.

## Configure the host

```elixir
config :regent_points,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  accounts: MySite.Points.Accounts,
  chain_client: MySite.ChainClient,
  ash_domains: [RegentPoints],
  program_id: "regents-points-v1",
  starts_at: nil,
  approved_rules: [],
  adapters: %{}
```

Earning is off while `starts_at` is `nil`. Setting it starts the program and its
30-day periods, and it never changes or returns to `nil` afterwards: awards still
being checked, corrections and bonuses all count periods from it. To stop earning
early, empty `approved_rules`.

Points runs in three seasons, one after the other from the start: program periods
1 to 3, 30 days each (Sean, 13 November 2026). The count belongs to the program,
like the 30 days, so it is `RegentPoints.Rules.season_count/0` and no site sets
it. Points stops by itself at the last season's end (`RegentPoints.Rules.ends_at/0`),
the same way it refuses before the start: an action done at or after the end
earns nothing (its check is refused with `rule_not_active`), and the start awards
job cancels with `:ended`. An action done before the end and checked after it
still earns in its season. Reads, the board, corrections and the last season's
bonus, tallied after its end, carry on; no fourth period is tallied.

`RegentPoints.Seasons.at(now)` is every site's one read of the seasons: each
season's number, `starts_at`, `ends_at`, `state` (`:upcoming`, `:running` or
`:ended`) and, for the running one, `days_left`. Before a start is set every season
is upcoming with no dates. `RegentPoints.Seasons.phase/1` says whether Points is
`:before` the first season, `:running`, or `:ended` after the last.

The accounts module implements `RegentPoints.Accounts`: `human/1` supplies the
verified wallet set for a canonical integer account ID; `agent_names/2` returns names
only for agents belonging to that account, as `{:ok, names}`; `people/1` returns how
each listed account shows to other people, for the leaderboard: its name, or `nil` and
its wallet (every wallet is public), the wallet's ENS name, and its pictures. Return `{:error, reason}`
on lookup failure so the account page shows an error rather than a false missing-agent label. Agent `actor_id` is the verified paired
agent record ID. The shared `regent_names.platform_human_users` table must exist;
this package references it but never creates, updates or merges people.

The chain client implements `RegentPoints.ChainClient`: `rpc(%{chain_id: 8453}, method, params)`.
The page reads current Base holdings as a preview. Confirmation reads one saved
finalized block immediately before the end of the 30-day period, shared by every
account. The RPC must support `finalized`, historical block headers and EIP-1898
`eth_call` by canonical block hash. Verify those capabilities before enabling earning;
missing historical evidence retries rather than falling back to current holdings.

Add `points: 5` and `points_chain: 2` queues to the site's existing Oban instance.
Only Regents, the one tally owner, adds a daily cron for `RegentPoints.TallyPeriods`;
every other site leaves it out. A site that lists at least one start rule it has a
source for adds `{"@hourly", RegentPoints.StartAwards}` for the start awards below; a
site with no start-rule source leaves it out. All hosts use the same shared database
and schema.
A site that can run without its job runner must not approve rules offered from a
person's action: the offer's job is inserted in that action's transaction, and without
the runner the action fails.
Use the same Repo for source actions and Oban. The package's notifier broadcasts
on the configured host PubSub under `points:<account_id>` when that account's total
moves, and under `points:board` when any account's does; cross-node notification
delivery follows the host's PubSub topology.

`RegentPoints.leaderboard/1` is system-only. The site reads it once for every reader,
on `points:board` and on a schedule, and keeps the answer on the server: `top`, the ten
highest rows (`account_id`, `name`, `wallet`, `ens_name`, `squares`, `picture`, `rank`,
`points_micro`). It reads ten stored totals from one index, never every account. A
reader gets the rows without their account ids and a mark on their own row. Their
own place, wherever they sit, is `place` in their summary: one more than the number
of accounts with strictly more points, counted on the same index when the summary is
read, or `nil` without points.

## Record committed actions

In the source action's transaction, call the system-only domain action:

```elixir
{:ok, _} =
  RegentPoints.record_event(%{
    rule_id: "patchbay.reply_published",
    source_app: "patchbay",
    source_kind: "reply",
    source_event_key: reply.id
  }, actor: %{role: :system})
```

It always answers `{:ok, _}`, so Points never refuses the action it rides in. While
the rule is off it answers `{:ok, %{status: :disabled}}` before it looks at anything
else, whatever the reference. With the rule on, an offer whose four fields are not
each a string of 1 to 512 bytes is set aside on its own: it answers `{:ok, %{status:
:invalid}}`, queues nothing and logs one warning with the rule, the source app and
kind and each field's size in bytes, never the source event key. Any other offer
answers `{:ok, %{status: :queued, id: job_id}}`.

Only those four reference fields enter the Oban job. The job is unique on them while
it waits, so the same reference offered again before its check runs is the same job. No adapter, Points table or
chain read runs in the product transaction. The job is inserted in the source's own
transaction, so the action and its Points job commit or roll back together; an insert
failure raises and rolls back the action. Outside a transaction, the same API can
resubmit a reference to an already committed source. Never repeat a post or
wallet action to recover Points; reconcile from authoritative source records.

The background verifier calls the rule's configured adapter `verify(reference)`,
and the award asks it again with the same reference just before it writes the
award, under the account's lock and inside the award's transaction. It must load
authoritative persisted records, not trust browser assertions, and read only the
site's own saved records, never another website or the chain, since the second ask
holds the account's lock. It changes nothing, so it can be asked any number of
times. Return `{:ok, facts}`, `{:error, reason_atom}` for a permanent rejection, or
`{:retry, reason}` for an outage. Exceptions also retry through Oban. Invalid facts
and conflicting evidence get a permanent private `source_rejections` audit, without
changing an accepted event. Infrastructure failures retry; discarded Oban jobs need
operator diagnosis.

At the award only the answer counts: the facts and the rule saved at the first
check decide the award, and a yes counts only when its facts name the account saved
at the first check. A source refused by then, such as a post hidden or marked as
spam, or one that now names another account, such as a social account linked to
someone else since, earns nothing for either account: its event ends `rejected`
with `award_refused` (audited as `account_changed` when the account moved), leaves the
summary's `pending` count, and the refusal gets the same private audit as one at
the first check. A source that cannot answer rolls the award back and Oban tries
again; after the last attempt the event ends `award_failed`. Start awards are
recorded like any action, so they are asked again too.

A source whose event ended `rejected` earned nothing, so it can be offered again,
such as a social account let go while its award waited and linked again later: the
new offer's facts replace the refused ones on the same event, which waits for its
own award and is asked again as usual. An event that earned, or was capped, stands.
An event still waiting keeps its facts: the same source offered again with other
facts, such as a social account now linked to someone else, is turned away as
`source_identity_conflict`, and the waiting event's award runs, under its own
account's lock, and awards or refuses it. Any offer of a waiting event's source
queues its award, one job while it waits. The start run offers again every account
whose event for the rule was refused or still waits, so a refused account, or the
account a source now names, can earn it later; only one account ever earns it.

Facts have atom keys: `source_app`, `source_kind`, `source_event_key`, `account_id`,
`actor_kind` (`"human"` or `"agent"`), `actor_id`, `source_action_at`, `qualified_at`,
`evidence_ref` and `evidence`. Both times are UTC DateTimes. Freeze the beneficiary
at action time. Source identity must match the job.
Agent evidence contains `"attribution_link_id"`; Keyfleet additionally needs
`"key_id"` and `"ownership_epoch"`; social milestones need a stable
restricted `"subject_key"`. Reports through WebMCP, HTTP, CLI, MCP or the site UI
must use the same business source identity for the same completed action. Transport
never establishes agent identity or creates a second award.

What an account already has at the start earns its one-time points at the start,
without the person doing anything: the account (`account.activated`), its linked X,
GitHub and Farcaster accounts (`social.*`) and its first paired agent
(`agent.activated`), at most 80 points (`RegentPoints.Rules.start_rules/0`). Sean,
6 November. The same run gives what came after the start that Points has not
recorded yet, such as an account that joined after the start but before its site
turned Points on (Sean, 19 November). `RegentPoints.StartAwards` stops with
`:not_started` while there is no start time or the start has not come, so the first
hourly run after the start does the work. Once a run succeeds no other runs that day;
one that ends cancelled or discarded lets the next hourly run start another. It asks each approved start rule's adapter for `existing(rule_id, at)`, with the
run's own time as `at`: one `{account_id, reference}` per account for state that
existed before `at` and still holds (a pairing still paired, a link still linked). It
leaves out accounts whose event for the rule earned or was capped and records each
other reference through `record_event/2`, so the adapter's `verify/1` proves it as usual and
reports the real time; what was there before the start earns at the start time, and
anything later at its real time. The run offers with `start_run: true`, so its checks
and their awards run at a lower Oban priority than live ones and a large run waits
behind live awards; a run repeated before its checks run queues nothing more. The milestone ids are the same as for new actions,
so an account earns each once whichever site records it. `existing/2` may answer any enumerable, which the run walks
once, so a lazy stream read in pages, such as `RegentAgents.pairings_held_from_before/1`
looked up and turned into references a page at a time, keeps the run's memory to one
page. The Regents account is named by one `source_app` on every site, `"regents"`,
never the site that happens to read it. Every other record, a pairing included, keeps
the site's own `source_app`, so two sites reading one pairing make two events; the
award's once-per-account limit lets only one of them earn. No other rule earns for anything before the start. A site
lists only the start rules it has a source for: Patchbay has no linked accounts, so it
lists the account and the first pairing.

## Rates and allowances

Repeat actions share one limit of 100 points per UTC day for the account and all its
paired agents, across every interface, with one count per action for the account
whoever acted. The actions add up
to more than 100 on purpose: the limit decides. One-time actions use no daily limit
and remain once per canonical account: one ledger entry, however many qualifying
actions arrive. Once the account has earned one, a later qualifying action records
no event and queues no award. An award still being checked, or one refused, blocks
nothing: a later action is recorded and checked too, and the award's own limits,
read under the account's lock, let only one of them earn, so actions arriving
together still earn once. A repeat action over its limit still writes a 0-point
entry that shows the reduction. `RegentPoints.summary/1` lists only the daily allowances that a rule
earning now on this site counts against. Its `done` holds every listed rule
(`Rules.listed/0`), whichever site earned it, since every site writes to the same
tables: `%{"account.activated" => %{times: 1, here: true}, ...}`. `times` is how many
times the account has had the award in the rule's own window, ever for a one-time
rule and today (UTC) for a daily one; `here` is whether this site earns the rule
(`Rules.enabled?/1`), so a page can say where to go for one it does not.
`template.first_agent_note` has no entry.

The repeat actions (Sean, 13 October) are: Autolaunch auction created 20 once a day,
auction bid 20 once a day, token trade through the site 10 once a day; Keyfleet key
bought 10 up to five a day; Patchbay Offer placed 5 up to ten a day, report published
10 once a day and reply published 5 once a day (Patchbay values, Sean, 14 October).
A Patchbay bid, starting or takeover, earns at the moment its Offer starts showing,
once for that bid; a bid that only leads and is then replaced earns nothing. Staking
an Autolaunch token earns 40 once per account. Regents staking, Techtree, the first
use of a site, and Patchbay's accepted solution and resolved report earn nothing.
There is no active-day or recurring vote rule; Keyfleet retains its 25-point
first-vote milestone. Every Patchbay report and reply must be accepted by Patchbay's
own quality check before it is published and earns; that check is Patchbay's, not
this package's.
Once Points has started, a rule that has ever earned is never removed from the
catalog: the points it awarded are still read against it. A rule's id never changes:
a changed rule keeps its id and gets the next version in the catalog, so what an
account earned under the old version still counts against the new one, and each
ledger entry keeps the version it earned under. A new id is only for a new action. To
stop a rule, take it off `approved_rules`.
Two approved candidates stay out of the catalog until their products exist (Sean, 8
October): Keyfleet rollcall, 5 once/day, and independently verified Patchbay repair, 15
twice/day. All rules remain operationally disabled in the template.

Awards save points only. The NFT bonus is added once per program period, at the
tally when the period ends (Sean, 9 October). Periods last 30 days, counted from
`starts_at`, and there are three: the seasons above. Animata I, Animata II and Regents Club count together across the
account's verified linked wallets at the period-end snapshot: 1–2 pieces add 20%, 3–6 add
45%, 7 or more add 75%. One tier applies, without stacking, to the points the account
earned in that period after all limits and corrections, one-time awards included.
`RegentPoints.TallyAccount` writes one `period_bonuses` row per account and period with
the tier held at period end, and Oban retries a Base outage. The tier is never read
again for that period: an award checked after the tally, or a correction, moves the
period's earned total and bonus at the saved tier in the same locked transaction as
its ledger entry. An account's balance is its entries plus its period bonuses, and the
account row stores it (`balance_micro`): each entry, new bonus and bonus that follows
moves it by what it added, with an atomic update in the same transaction. Repeat actions earn at
most 100 base Points a UTC day, excluding one-time awards. The milestone catalog
totals 390 (`RegentPoints.Rules.milestone_total/0`), 380 without
`template.first_agent_note` (Sean, 14 November 2026). Sean approved the trial
values on 7 October; enabling any rule still needs his go. `RegentPoints.Rules.catalog/0` lists them,
`label/1` names each one for people, and `active/0` lists those earning now.
`tracked/0` lists the rules that are approved and have a source adapter on this site:
the ones it earns. A site's Points page shows every catalog rule except
`template.first_agent_note`, which the catalog marks `:hidden`: it earns like any
other rule, but no page lists it. `listed/0` lists the rules a page shows, and
`groups/0` groups them by site in the page's order, Account, Autolaunch, Keyfleet,
Patchbay and Cloak, from each id's first segment (`account`, `social` and `agent`
are Account). `daily_apps/1` names the apps of the daily rules among the rules it is
given. There is no uncapped revenue-points rule.

Accepted events save the rule's points and daily limits with the rule. Delayed
processing uses that snapshot. A rule version never changes after approval; a changed
value is the rule's next version. `RegentPoints.Bonus` owns
the tiers used by the tally and the database constraint. `Bonus.current/1` reads
the tier an account's wallets hold now. The page shows a projected bonus and total,
with the actual period-end snapshot date. Moving an NFT changes this preview; only
holding it at the period-end snapshot determines the confirmed bonus.

Only the server system actor may intake, award or correct. Human actors with a
verified `human_account_id` can read only their own entries and summary. Rejections
and raw evidence are system-only. Corrections append negative entries and never
reopen allowances. There is no browser award API.

## Migrate and verify

`RegentPoints.Migrator.up(MySite.Repo)` runs the package's generated migrations on
a dedicated connection, with its own history in `regent_points`. One designated
owner runs production migrations only with Sean's grant. The period bonus migration
removes the action-time NFT columns and the transfer cursor table; its rollback runs
only while the Points tables hold no awards.
The account balance migration adds `accounts.balance_micro` and fills it from the
ledger in one transaction that locks the accounts table while it reads every entry and
bonus once; a later migration builds the board's index on it concurrently. Apply it
while no site on an older version records Points: an older version appends entries
without moving the stored total.
The period-end snapshot migration records the existing verified wallet sets and
installs a capture trigger on the canonical account table, covering every site's
wallet changes. Wallet history, capture coverage and period snapshots are immutable.
Set `starts_at` at or after this capture coverage begins; older periods cannot be
reconstructed from current account state and are refused. Conflicting wallet ownership
at period end also refuses the tally. Snapshot creation is serialized, so concurrent
jobs reuse the same saved block. The generated capture migration wraps its statements
in one SQL block because Postgrex prepares one statement per call.
`RegentPoints.WalletSnapshot.owner/2` reads the same history for a site's
source action: the account holding a wallet at the moment of the event, or
`:unknown_owner` when no account, or more than one, held it then. It never
answers with the wallet's current owner.

Shared Ash SQL extensions belong to the host and are not migrated by this package.

For package development:

```sh
mix deps.get
mix check
mix ash.codegen --check
# After a resource change:
mix ash.codegen describe_change
```

The package's development Repo uses an isolated local database. Only package config
enables migration generation. Source adapters, approved rates/start time, the tally
cron on Regents and live product acceptance remain required before earning is enabled.
