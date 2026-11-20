defmodule Regents.Patchbay.Assist.Decision do
  @moduledoc """
  One time Jev chose among the known fixes for an agent stuck on a site:
  what the agent said, which fix Jev chose (or that none fits) and how sure
  it was, and, once the agent says so, whether the fix worked.

  Its id is handed to the agent with the answer: whoever holds it may say
  once whether the fix worked, and that word stands. Reports are the agent's
  own word, counted as such and never as a check.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Assist,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Assist.Types.AskedFrom
  alias Regents.Patchbay.Assist.Types.FixResult

  postgres do
    table("assist_decisions")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:assist_run, on_delete: :nilify)
    end

    custom_indexes do
      # What agents said of each known fix is counted by its choice and result.
      index([:choice, :result])
      # A run's removal clears its decisions' link to it.
      index([:assist_run_id])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    attribute(:site, :string, allow_nil?: false, public?: true)
    attribute(:goal, :string, allow_nil?: true, public?: true)
    attribute(:error, :string, allow_nil?: true, public?: true)

    attribute(:asked_from, AskedFrom, allow_nil?: false, public?: true)

    # The key of the connection that asked, on decisions the earlier free help
    # made. A decision made inside a fix has the fix's run instead.
    attribute(:visitor_key, :string, allow_nil?: true, public?: true)

    # The known fix's id, or `none_fits`.
    attribute(:choice, :string, allow_nil?: false, public?: true)
    attribute(:confidence, :float, allow_nil?: false, public?: true)
    attribute(:model, :string, allow_nil?: false, public?: true)

    attribute(:result, FixResult, allow_nil?: true, public?: true)
    attribute(:reported_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to(:assist_run, Regents.Patchbay.Assist.Run, allow_nil?: true, public?: true)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
