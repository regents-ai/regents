# Changelog

## 0.1.0 (unreleased)

- The tests and their database are gone (19 Nov 2026). `mix check` runs in dev
  against `RegentAgents.Repo` in `dev/`, which no `:prod` build compiles, and
  compiles with warnings as errors and checks unused locks, formatting, Credo and the
  usage rules.

- `RegentAgents.pairings_held_from_before/1` answers a lazy stream instead of
  `{:ok, list}` (19 Nov 2026). It reads 500 people at a time as it is walked, each
  read after the last person of the one before, in order of Privy user ID, in no
  transaction. Each person still comes once, with their earliest pairing before the
  moment that is still paired. Callers walk the stream instead of matching
  `{:ok, pairings}`.

- Hello cards (`RegentAgents.HelloCard`). `POST /api/agents/v1/pairing` answers
  the SIWA service's question before it signs a card naming this site:
  `{"name", "person", "pairedAt"}` for a paired agent, `not_paired_here` (404)
  for an agent with no pairing, `person_has_no_profile` (409) for a paired agent
  whose person has no profile code yet, or `service_token_invalid` (401)
  without its EdDSA service token for this site's origin and that subject. A
  site adds `origin` to its `siwa` settings and a `person` function giving the
  person's profile code (the id of their shared Regent profile, never the Privy
  user ID, an email, a wallet or a name), or nil while they have none. Pages
  say "paired with a person on <site>" and never show or greet anyone with the
  `person` code. Every agent request the package verifies carries a card that
  passes in its `x-siwa-hello-card` header as `conn.assigns.hello_card`, and a
  site's own hooks do the same with `RegentAgents.HelloCard.put_card/2`. The
  SIWA service's keys are kept for an hour.

- `RegentAgents.pairings_held_from_before/1` lists each person's earliest
  pairing made before a moment that is still paired, one per person, for the
  agents people already had when Points started (`RegentPoints.StartAwards`).

- `RegentAgents.pairing_at/2` gives the one pairing that held a wallet at a
  moment (paired by then, not yet unpaired), or `{:error, :unknown_owner}` when
  none or more than one did, the same answer as `RegentPoints.WalletSnapshot.owner/2`.
  It never answers with a later or current pairing.

- `RegentAgents.pairing_history/1` (by pairing id, `{:ok, pairing | nil}`) and
  `RegentAgents.pairing_histories/1` (by Privy user ID, oldest first) read the
  kept pairings, unpaired ones included, as `id`, `privy_user_id`, `wallet`,
  `name`, `paired_at` and `revoked_at`, so a site no longer queries
  `regent_agents.pairing_history` itself.

- `RegentAgents.Signals` `:agent_paired` (`paired_agent_id`, `privy_user_id`) is
  emitted by `PairedAgent` `:record` inside the pairing's transaction, so a site
  can react to a new pairing (Points' "First paired agent") with `signals_in`.
  A site that does not listen is unchanged.

- Pairing is on each site's Agents page, at `/account/agents#account-pairing`, as
  ash-template has it. The `pairing_failed`, `agent_limit` and `agent_not_paired`
  hints and the `not_paired` next step say "on their Agents page", and a hosted
  runtime's pairing message ends "My Agents page is
  <origin>/account/agents#account-pairing." instead of the account page.

- A check-in refused as `agent_not_paired` or `person_not_here` ends its hint
  with "Help: https://patchbay.help/errors/<code>", Patchbay's page for that
  refusal, so an agent can read what to do next.

- Pairing moves from the side panel to each site's Account page, so every refusal
  hint and next step that sent a person to Pair New Agent "in the side panel" now
  says "on their Account page" (`pairing_failed`, `agent_limit`, `agent_not_paired`
  and the `not_paired` next step).
- Claude pairs as a hosted runtime, like ChatGPT: a `claude` harness, and a
  pairing message that tells Claude to connect through the site's connector and
  pair with `pair_identity`, the name Claude and the harness `claude`.
  ChatGPT's message now names its harness the same way.
- `config :regent_agents, hosted_pairing: [...]` lists the hosted runtimes a
  site serves (`RegentAgents.Harness.hosted/0`, from `hosted_runtimes/0`:
  `chatgpt` and `claude`), replacing `chatgpt_pairing: true`. The pairing box
  (`Harness.offered/0`), the pair request and its `harness_unknown` hint offer
  only those, so a site that switches on Claude does not also offer ChatGPT. A
  site that set `chatgpt_pairing: true` sets `hosted_pairing: [:chatgpt]`.

- `RegentAgents.agents_paired_with(codes, actor: person)` names the agent each
  of the person's codes paired, by code; a code not yet used, or not the
  person's, is left out. Pairing stamps the agent's `paired_at` and the code's
  `used_at` with the one time, which is how a code finds its agent. A pairing box
  holding codes for several runtimes named the newest agent under whichever code
  was on screen and offered the spent code again (Autolaunch, 27 Oct 2026); it
  now asks this once per notice.
- Every pairing message but ChatGPT's gains the line "If other agents share your
  computer, use your own key: begin every shell with export
  SIWA_AGENT_HOME=~/.siwa-agent/<runtime>", the folder named after the agent's
  runtime (`claude-code`, `codex`, `openclaw`, `muse` and so on), so agents
  sharing one computer each keep their own key and pair as separate agents
  (Sean, 27 Oct 2026, AGENT-KEY-HOME a). Any other agent, and a message with no
  runtime named, gets `YOUR-RUNTIME` to fill in. Grok Bot is told
  `/workspace/.siwa-agent` instead, the folder its agent guide names, because
  only `/workspace` survives a Grok Bot restart. The line follows the pairing
  lines, before the site's `setup:` lines. Keyfleet's own copy of the line can go
  from its `setup:` once it uses this version.
- Pairing, check-in and making a code run in `Ash.transact/2` instead of
  `Ash.DataLayer.transaction/2`, so Ash sends what their actions notify once the
  transaction commits. Every agent check-in used to log "Missed 1 notifications
  in action RegentAgents.PairedAgent.touch" in production. A refused pairing or
  check-in still writes nothing: `Ash.transact/2` rolls back on `{:error, _}`,
  and an agent over the limit still hears `agent_limit`. The test settings now
  raise on a missed notification (`config :ash, :missed_notifications, :raise`),
  so the suite fails if one comes back.

- `PairingMessage.text/4` takes options: `start:`, the page a pairing link names
  (a path on the same site), ends the message "Once paired, start at <page>", so
  an agent brought to one project begins there (the template's /pair?to=<path>);
  `setup:`, the site's own lines for that agent (such as Keyfleet's check-in
  steps), goes after the pairing lines and before the start line.
- `RegentAgents.Listener` listens on the site's own `Postgrex.Notifications`
  connection, named in the required `notifications:` setting, instead of opening
  one with the repository's settings. The site opens that connection on the
  database's direct address, so its repository can serve through the pooler, and
  Credits' listener shares it: one listening connection per machine, not two.
- ash_postgres comes from Regent's copy of 2.15.2 (regents-ai/ash_postgres at
  cc886ab3), which carries ash-project/ash_postgres#910: upserts are written to the
  schema the site's repo picks, as on 2.13.0. It clears the two 2.13.0 advisories.
  Ash 3.37.2, ash_sql 0.8.4.
- Hermes's first-pairing line says "Keep the key you pair with" instead of
  naming regents-cli, since agents make their key with the SIWA client
  (siwa_agent.py keygen) or sign with their own wallet.
- The side panel offers IronClaw in NemoClaw's place, so the ten agents are any
  agent, Codex, Grok Bot, Muse, Hermes, Dots, IronClaw, OpenClaw, Claude Code and
  Pi (Sean, 21 Oct 2026, for Keyfleet's nine-agent pilot). NemoClaw agents pair
  as any agent.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. phoenix 1.8.16.
- The pairing message opens "Pair with my Regents Labs account on <host>" (for
  example techtree.sh), and the ChatGPT one "Connect ChatGPT to my existing
  Regents Labs account on <host>", so agents learn the account is the person's
  Regents Labs account (Sean, 19 Oct 2026). `PairingMessage.text/3` takes
  `(code, origin, harness)`; the site name argument is gone, since the host
  comes from the origin.
- `GET /whoami` tells every signed agent its `status` on the site (`not_paired`,
  `person_not_here` or `paired`), what it may do in it (`allowed`, from the
  site's required `config :regent_agents, :allowed`) and its `next_step` (null
  when paired). `effective_access` is gone.
- A check-in from an agent paired to nobody answers `agent_not_paired` (403),
  the code every Regent site gives such an agent, in place of `not_paired`
  (404). Its hint, and the `pairing_failed` and `agent_limit` hints, point the
  person at Pair New Agent in this site's side panel.

- One check covers how `RegentAgents.Activity` reads the SIWA service's answer:
  Regent days come back newest first with their site names, a day at another site
  is left out, an unreadable day gives `{:error, :bad_day}` and an answer without a
  list of days gives `{:error, :bad_days}` (agreed with Sean, 16 Oct 2026).
- `RegentAgents.Activity.recent/1` answers `{:error, :bad_days}` when the SIWA
  service answers 200 without a list of days, instead of
  `{:error, {:unexpected_status, 200}}`, which named the wrong problem.
- `RegentAgents.Activity.recent/1` answers `{:error, :bad_day}` when any day from
  the SIWA service is missing a field or has a value it cannot read, such as an
  empty time. Before, such a day raised, and the side panel page that asked closed
  with it. A day at a site outside the Regent family is still left out.
- `RegentAgents.Activity` names the SIWA service's `regents-mobile` audience
  "Regents mobile app", so an agent's requests through the Regents mobile app
  show among its sites instead of being skipped.
- `RegentAgents.Activity.recent/1` reads the SIWA service's daily lines: for each
  Regent site and day in the last 30, when the agent's first and last request
  there was verified, newest day first, with its registry listing.
  `RegentAgents.Activity.latest/1` gives the site and time of its newest request.
  There are no pages, no request-by-request wording and no operations argument.
- `RegentAgents.Harness.featured/0` lists the ten agents the side panel offers:
  any agent, Codex, Grok Bot, Muse, Hermes, Dots, NemoClaw, OpenClaw, Claude Code
  and Pi.
- Every pairing message says the code works once, for ten minutes, and to ask for
  a new one if it fails. Codex's adds what to do when its sandbox blocks the
  network and where pair.json goes; Grok Bot's says never to post the code in
  public; Hermes's says to keep one key; Muse's keeps the SIWA service's other
  address.
- A check-in before the person's first sign-in on the site answers
  `person_not_here` (403), the code every Regent site gives an agent whose person
  has not signed in there yet, asking the agent to have its person sign in
  there once, instead of crashing: the site's `account` callback returns nil
  until that sign-in. Every site's callback returns a map or nil.
- The check-in looks up the account before it records contact, so a
  `person_not_here` answer leaves the agent's last contact unchanged and
  announces nothing.
- `check_in_agent/2` takes the person's Privy user ID and records contact only
  when the agent's pairing is still with that person; otherwise it answers
  `not_paired`. The check-in request passes the person whose account it looked
  up, so an agent unpaired and paired to someone else in between never answers
  with the previous person's account.
- The pair request accepts only the harnesses the site offers
  (`RegentAgents.Harness.offered/0`), and its `harness_unknown` hint lists
  those, so a site without `chatgpt_pairing: true` refuses `chatgpt`.
- New `RegentAgents.Refusal.describe/2`: the status, code, message and hint an
  agent gets when its signed request is refused, for a site's own
  `Siwa.AgentAuthPlug` `deny/2` hook to call with its sign-in hint. The pairing
  and check-in requests use it too. When the sign-in service cannot be reached
  the hint now reads "Try again in a moment."
- `RegentAgents.Activity` (where a paired agent has been active across the
  Regent sites, read with the site's `activity_read_token`) and `RegentAgents.PairingMessage`
  (the message a person pastes to their agent), moved here from ash-template.
- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/agents`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- Runs on Ash 3.36. Ash postgres stays at 2.13.0.
- `RegentAgents.AgentPicture`: the picture a person chose for one of their
  paired agents. The person sets it (`set_agent_picture/3`, a WebP of at most
  65,536 bytes, judged by its first bytes) and removes it
  (`remove_agent_picture/2`); a team member, a `RegentAgents.Person` with
  `role: :admin` whom `config :regent_agents, admins: [...]` names, may only
  remove it (`remove_agent_picture_by_team/2`). Anyone may read it by the
  agent's wallet (`agent_picture/2`). `RegentAgents.PairedAgent` gains
  `picture_updated_at`, nil when the agent has no picture. Each set and
  remove tells every site, as a pairing does. Unpairing removes the picture. Migration `20261014150000_agent_pictures` adds
  `regent_agents.agent_pictures` and must run before any site uses this
  version.
- The person who paired an agent may rename it (`rename_agent/3`, the
  `RegentAgents.PairedAgent` `:rename` action), on every Regent site at once since
  the pairing is shared. Only that person may; the agent itself may not. Each
  rename tells every site, as a pairing does, and the pairing history keeps the
  new name.
- An agent's name follows the one rule for names (`RegentFormat.Name`, founder,
  2026-10-19): trimmed, 1 to 80 characters, and no hidden characters. Pairing
  with any other name answers `invalid_name` (400) and the code stays unused.
  `regent_format` is a new path dependency.
- `RegentAgents.HelloCard`: a read of the published keys that fails is not tried again
  for a minute, and a site with no `siwa: [origin: ...]` accepts no service token.
