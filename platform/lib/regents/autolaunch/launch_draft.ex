defmodule Regents.Autolaunch.LaunchDraft do
  @moduledoc """
  One person's private Revstake launch draft: the token's details, its links
  and picture, and where its treasury goes, saved as they are typed.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # What a paired agent may set: the token's details, its links and where its
  # treasury goes.
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
    :treasury,
    :treasury_path
  ]

  postgres do
    table "launch_drafts"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:human_account_id])
      index([:launch_draft_image_id])
    end
  end

  attributes do
    attribute :last_agent_pairing_id, :uuid
    uuid_primary_key :id

    attribute :name, :string do
      source :token_name
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end

    attribute :symbol, :string do
      allow_nil? false
      default ""
      public? true
      constraints allow_empty?: true
    end

    attribute :description, :string do
      source :summary
      public? true
    end

    attribute :website, :string, public?: true
    attribute :telegram, :string, public?: true
    attribute :discord, :string, public?: true
    attribute :other_link_1, :string, public?: true
    attribute :other_link_2, :string, public?: true
    attribute :other_link_3, :string, public?: true
    attribute :image, :string, public?: true
    attribute :treasury, :string, public?: true

    attribute :treasury_path, :atom do
      allow_nil? false
      public? true
      default :safe
      constraints one_of: [:safe, :eoa, :contract]
    end

    attribute :eoa_acknowledgement, :string do
      public? true
      constraints max_length: 512, trim?: false
    end

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

    belongs_to :launch_draft_image, Regents.Autolaunch.LaunchDraftImage do
      allow_nil? true
    end
  end

  identities do
    identity :one_account_owned_draft_per_human, [:human_account_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
