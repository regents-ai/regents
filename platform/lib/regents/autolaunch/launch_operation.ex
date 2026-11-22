defmodule Regents.Autolaunch.LaunchOperation do
  @moduledoc """
  One launch review this site built for an account, saved so the launch it
  carries out is known as this site's whether or not the page is still open.

  `review` is fixed once saved: the chain, the signer, the one `launch` step
  (target and calldata) and the facts the page showed. Nothing about a press is
  stored. A launch the chain shows is matched to the review whose step it
  sent, which is then marked `chain_verified`.

  A review stays `prepared` until the chain shows its launch, even once its
  page has let it go: its exact step can still be sent, and the launch is then
  this site's. An account may hold any number of the reviews its pages save;
  one never cancels another. A paired agent's review of the person's draft is
  `prepared_by: :agent`.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @steps [:launch]
  @states [:prepared, :chain_verified]

  postgres do
    table "launch_operations"
    schema("autolaunch_app")
    repo(Regents.Repo)

    references do
      reference(:human_account, on_delete: :restrict)
      reference(:launch_draft, on_delete: :restrict)
    end
  end

  attributes do
    uuid_primary_key :id

    # Never accepted by an update: the reviewed identity is the operation.
    attribute :action_id, :string,
      allow_nil?: false,
      constraints: [min_length: 64, max_length: 64]

    attribute :review, :map, source: :envelope, allow_nil?: false, sensitive?: true

    attribute :signer, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :step, :atom, allow_nil?: false, constraints: [one_of: @steps]
    attribute :state, :atom, allow_nil?: false, default: :prepared, constraints: [one_of: @states]

    # Set only by a paired agent's preparation.
    attribute :prepared_by, :atom,
      allow_nil?: false,
      default: :person,
      constraints: [one_of: [:person, :agent]]

    # Adopted from the verified `LaunchCreated`, never guessed before mining: the
    # launch id, subject, auction, escrow and the fixed schedule it recorded.
    attribute :result, :map, default: %{}

    # Written by nothing; dropped by the next release, once no machine of the
    # release before this one still reads it.
    attribute :reason, :string, constraints: [max_length: 120], select_by_default?: false
    attribute :terminal_at, :utc_datetime_usec
    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    belongs_to :launch_draft, Regents.Autolaunch.LaunchDraft do
      allow_nil? false
    end
  end

  identities do
    identity :unique_launch_action_id, [:action_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
