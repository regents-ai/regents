defmodule Regents.Techtree.WalletBench.Attempt do
  @moduledoc """
  One run of one pair: a harness and a wallet, tested on a machine of their own.

  `state` moves forward one step per job on techtree.sh's bench: `requested`,
  `leased` (a ready machine is taken for it), `testing` (the turns run,
  `Regents.Techtree.WalletBench.Turn`), `revoking` (the tests are over or one
  failed; the model key comes off) and `done`, or `failed` with the reason. An
  attempt of the `money` plan goes on after a passed wallet test through
  `funding` and `sending`, then `testing` again for the money tests; when the
  agent did not earn its funding the reason is kept in `funding_refused`.

  Read only here: only the columns the pages read are attributes.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Techtree's own area of the shared database, where techtree.sh's bench writes
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_attempts"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    defaults [:read]

    read :recent do
      description "Every attempt, newest first."
      prepare build(sort: [inserted_at: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :harness_id, :string, allow_nil?: false, public?: true
    attribute :wallet_id, :string, allow_nil?: false, public?: true

    attribute :state, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :requested,
                    :leased,
                    :testing,
                    :funding,
                    :sending,
                    :revoking,
                    :done,
                    :failed
                  ]
    end

    attribute :plan, :atom do
      description "`wallet`: install and wallet tests. `money`: then funded, T3 to T5 and returning what is left."
      allow_nil? false
      public? true
      constraints one_of: [:wallet, :money]
    end

    attribute :failure, :string, public?: true, description: "Why the attempt failed."

    attribute :agent_address, :string,
      public?: true,
      description: "The Base address the wallet test found, which the bench funds."

    attribute :funding_refused, :string,
      public?: true,
      description:
        "Why this money attempt was not funded: the install or wallet test it had to pass."

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :machine, Regents.Techtree.WalletBench.Machine, public?: true

    has_many :turns, Regents.Techtree.WalletBench.Turn do
      public? true
      sort inserted_at: :asc
    end

    has_many :payments, Regents.Techtree.WalletBench.Payment do
      public? true
      sort nonce: :asc
    end
  end

  aggregates do
    sum :model_spend_usd, :turns, :model_spend_usd, public?: true
    sum :judge_cost_usd, :turns, :judge_cost_usd, public?: true
  end
end
