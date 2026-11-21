defmodule Regents.Autolaunch.Stocks.LaunchDraft do
  @moduledoc """
  One private Stocks launch draft per human account, independent of the Agent
  draft. The creator moves it between Base and Robinhood; the token details go
  with it, and the paired stock is chosen again from the new chain's list.

  Every section autosaves partial text. The creator chooses no price or
  minimum: every launch opens at the lowest price the auction accepts.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # What a paired agent may set: the token's details and links, the chain and
  # the paired stock, which must be one the chain lists.
  @agent_fields [
    :name,
    :symbol,
    :description,
    :website,
    :telegram,
    :discord,
    :other_link_1,
    :other_link_2,
    :other_link_3,
    :chain,
    :stock_address
  ]

  postgres do
    table "stock_launch_drafts"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:stock_launch_draft_image_id])
    end

    references do
      reference(:human_account, on_delete: :restrict)
      reference(:stock_launch_draft_image, on_delete: :restrict)
    end
  end

  attributes do
    attribute :last_agent_pairing_id, :uuid
    uuid_primary_key :id

    attribute :chain, :atom do
      allow_nil? false
      public? true
      default :base
      constraints one_of: [:base, :robinhood]
    end

    attribute :name, :string, allow_nil?: false, default: "", constraints: [allow_empty?: true]
    attribute :symbol, :string, allow_nil?: false, default: "", constraints: [allow_empty?: true]
    attribute :description, :string
    attribute :website, :string
    attribute :telegram, :string
    attribute :discord, :string
    attribute :other_link_1, :string
    attribute :other_link_2, :string
    attribute :other_link_3, :string
    attribute :image, :string

    attribute :stock_address, :string
    attribute :stock_chain_id, :integer, allow_nil?: false

    # The fields a paired agent set and the creator has not changed since.
    attribute :agent_set_fields, {:array, :atom} do
      allow_nil? false
      public? true
      default []
      constraints items: [one_of: @agent_fields ++ [:image]]
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :stock_launch_draft_image, Regents.Autolaunch.Stocks.LaunchDraftImage do
      allow_nil? true
    end
  end

  identities do
    identity :one_stocks_draft_per_human, [:human_account_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
