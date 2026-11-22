defmodule Regents.Techtree.WalletBench.Payment do
  @moduledoc """
  One send from the bench's funder wallet on Base: the USDC or the ETH for gas
  that funds a money attempt. A send is `signed` before it is broadcast, and
  ends `confirmed` or `reverted` from its receipt on Base, `unknown` when no
  receipt came in time, or `replaced` once another send used its nonce.

  Read only here: a test's page shows what was sent, its state and its
  transaction, so only those columns are attributes. The recipient, the signed
  bytes, the block and who settled it are never read.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Techtree's own area of the shared database, where techtree.sh's bench writes
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_payments"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:usdc, :eth]
    end

    attribute :state, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:signed, :confirmed, :reverted, :unknown, :replaced]
    end

    attribute :from, :string, allow_nil?: false, public?: true, description: "The funder."

    attribute :amount, :integer do
      description "In units of 0.000001 USDC, or in wei."
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :nonce, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :hash, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :attempt, Regents.Techtree.WalletBench.Attempt do
      allow_nil? false
      public? true
    end
  end
end
