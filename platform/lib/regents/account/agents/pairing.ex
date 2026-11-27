defmodule Regents.Account.Agents.Pairing do
  @moduledoc """
  An agent's pairing as a product reads it, from the table the agent pairing
  every Regent site shares keeps (`RegentAgents.PairedAgent`): the agent's
  wallet, the name it goes by and what it runs on. The person it is paired with
  is not a field here, so no read can return them. Pairing, renaming and
  unpairing happen only through `RegentAgents`; this only looks wallets up, as
  the system.
  """

  use Ash.Resource,
    domain: Regents.Account.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "paired_agents"
    schema("regent_agents")
    repo(Regents.Repo)
    migrate?(false)
  end

  attributes do
    uuid_primary_key :id
    attribute :wallet, :string, allow_nil?: false
    attribute :name, :string, allow_nil?: false
    attribute :harness, RegentAgents.Harness, allow_nil?: false
  end

  actions do
    # The pairings among these wallets, each lowercase `0x…`; a wallet with no
    # pairing answers nothing.
    read :by_wallets do
      argument :wallets, {:array, :string}, allow_nil?: false
      filter expr(wallet in ^arg(:wallets))
    end
  end

  policies do
    policy action(:by_wallets) do
      authorize_if actor_attribute_equals(:__struct__, Regents.Account.Actors.System)
    end
  end
end
