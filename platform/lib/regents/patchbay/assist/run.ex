defmodule Regents.Patchbay.Assist.Run do
  @moduledoc """
  One assist: what somebody asked Patchbay to work out on some site, what
  let it open, and what came of it.

  A run opens for an agent signed in with SIWA, under the free fixes its
  wallet has left. Paid assists have ended; the runs they bought keep their
  records, and a fee still on its way is forwarded as before. A run is read
  back by its asker, or by the browser it was asked from. The status and the
  outcome are the only things that move after it is opened.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Assist,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Assist.Types.DepositStatus
  alias Regents.Patchbay.Assist.Types.Grant
  alias Regents.Patchbay.Assist.Types.Outcome
  alias Regents.Patchbay.Assist.Types.RunStatus
  alias Regents.Patchbay.Assist.Types.SignIn

  postgres do
    table("assist_runs")
    schema("patchbay_app")
    repo(Regents.Repo)

    identity_wheres_to_sql(
      one_open_run_per_payer: "status IN ('paid', 'running')",
      one_open_run_per_browser: "status IN ('paid', 'running')"
    )
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    uuid_primary_key(:id)

    # The profile the run was asked by. It names a row in the identity
    # domain rather than pointing at one, so a run outlives the profile it
    # was bought by. A run the page once asked for without signing in has
    # none.
    attribute(:payer_profile_id, :uuid, allow_nil?: true, public?: true)

    # The browser's forum identity the run was asked under; a wallet author
    # has none.
    attribute(:browser_session_id, :uuid, allow_nil?: true, public?: true)

    attribute(:grant, Grant, allow_nil?: false, public?: true)

    # The key the page door derived for the connection a free run from the
    # page was once asked from. Never the address.
    attribute(:visitor_key, :string, allow_nil?: true, public?: true)

    # The payment that bought a run before paid assists ended, in the shared
    # payment records; a free run has none.
    attribute(:payment_intent_id, :uuid, allow_nil?: true, public?: true)

    attribute(:goal, :string, allow_nil?: false, public?: true)

    # What went wrong, in the asker's words, when they said.
    attribute(:error, :string, allow_nil?: true, public?: true)
    attribute(:site_url, :string, allow_nil?: false, public?: true)
    attribute(:sign_in, SignIn, allow_nil?: false, public?: true)

    # The calls the agent believed would work, each a tool name and, when
    # the agent knew them, its arguments, in the order the agent gave them.
    attribute(:believed_calls, {:array, :map}, allow_nil?: false, public?: true, default: [])

    attribute(:status, RunStatus, allow_nil?: false, public?: true, default: :paid)
    attribute(:outcome, Outcome, allow_nil?: true, public?: true)

    # What was tried, in order: the tool, its arguments, an excerpt of the
    # site's answer and what Jev made of it.
    attribute(:steps, {:array, :map}, allow_nil?: false, public?: true, default: [])

    attribute(:started_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:finished_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    # Where a paid run's fee stands on its way from the operator wallet to
    # the REGENT staking contract, and the deposit's transaction once it is
    # there; a free run has no fee.
    attribute(:deposit_status, DepositStatus, allow_nil?: false, public?: true)
    attribute(:deposit_tx_hash, :string, allow_nil?: true, public?: true)

    # When the fee's forward was last taken, which its wait for the chain is
    # counted from.
    attribute(:fee_taken_at, :utc_datetime_usec, allow_nil?: true)

    timestamps()
  end

  identities do
    # One payment buys one run; a second opening of the same payment is
    # refused by the database rather than by a check a retry could race past.
    identity(:one_run_per_payment, [:payment_intent_id], eager_check?: false)

    # One open run per payer: the check made before anyone pays is repeated
    # by the database when the run is opened, so two payments settling at
    # once still open one run now and the other on a later call.
    identity(:one_open_run_per_payer, [:payer_profile_id],
      where: expr(status in [:paid, :running]),
      eager_check?: false
    )

    # One open run per browser, the same way: a page may not ask for a
    # second fix while its first is still being worked on.
    identity(:one_open_run_per_browser, [:browser_session_id],
      where: expr(status in [:paid, :running]),
      eager_check?: false
    )
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
