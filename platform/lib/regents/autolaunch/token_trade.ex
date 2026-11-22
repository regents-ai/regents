defmodule Regents.Autolaunch.TokenTrade do
  @moduledoc """
  Confirmed trades in a launched token's pool, one row per `Swap` log. A buy
  took the token out of the pool and a sell put it in. The currency amount is
  the pool's other side, in its own currency: REGENT for a Revstake token, the
  paired stock for a Memestock one.

  The trader is the wallet that sent the swap's transaction, written with the
  row and never changed by a later write of it. Rows saved before the site
  recorded traders have none.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "token_trades"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:token_id, :block_number])
      index(["occurred_at DESC", "id"], name: "token_trades_recent_index")
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :transaction_hash, :string, allow_nil?: false
    attribute :block_hash, :string, allow_nil?: false
    attribute :block_number, :integer, allow_nil?: false
    attribute :log_index, :integer, allow_nil?: false
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false
    attribute :side, :atom, allow_nil?: false, constraints: [one_of: [:buy, :sell]]
    # The pool's other side: what the buyer paid or the seller received.
    attribute :currency_amount, :decimal, allow_nil?: false, constraints: [greater_than: 0]
    attribute :currency_symbol, :string, allow_nil?: false
    attribute :token_amount, :decimal, allow_nil?: false, constraints: [greater_than: 0]
    # The lowercase wallet that sent the swap's transaction.
    attribute :trader, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]
  end

  relationships do
    belongs_to :token, Regents.Autolaunch.Token do
      allow_nil? false
    end
  end

  identities do
    identity :pool_log, [:token_id, :transaction_hash, :log_index]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
