defmodule Regents.Techtree.WalletBench.AttemptEvent do
  @moduledoc """
  What happened in one attempt, in the order it happened: each state the
  attempt reached and each state each of its turns reached. `step` names the
  state, such as `leased` or `T1a judged`; `detail` holds what that step saw.
  Events are appended on techtree.sh and never changed.

  Read only here: who ran a step, when an operator did, is never read.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Techtree's own area of the shared database, where techtree.sh's bench writes
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_attempt_events"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    read :for_attempt do
      description "Everything that happened in one attempt, oldest first."
      argument :attempt_id, :uuid, allow_nil?: false
      filter expr(attempt_id == ^arg(:attempt_id))
      prepare build(sort: [inserted_at: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :step, :string do
      allow_nil? false
      public? true
      constraints max_length: 64
    end

    attribute :detail, :map, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :attempt, Regents.Techtree.WalletBench.Attempt do
      allow_nil? false
      public? true
    end
  end
end
