defmodule Regents.Autolaunch.Stocks.AdmissionScan do
  @moduledoc """
  How far the site has read one stock launchpad's `StockAdmitted` logs: the
  next block to read from, and the stocks those logs named that it could not
  read or save yet. One row per chain, launchpad and deployment run, so a local
  chain deployed again, which puts the same launchpad address on a new
  history, is read from its own first block.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stock_admission_scans"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]

    attribute :launchpad, :string,
      allow_nil?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]

    attribute :run_id, :string, allow_nil?: false, constraints: [max_length: 200]
    attribute :next_block, :integer, allow_nil?: false, constraints: [min: 0]

    attribute :unread, {:array, :string},
      allow_nil?: false,
      default: [],
      constraints: [items: [match: ~r/\A0x[0-9a-f]{40}\z/]]

    timestamps()
  end

  identities do
    identity :one_per_launchpad, [:chain_id, :launchpad, :run_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
