defmodule Regents.Autolaunch.LaunchDiscovery do
  @moduledoc """
  One launch the chain shows on a Base launchpad, and whether it is a launch
  this site's accounts reviewed.

  A launch is listed from chain evidence alone: each Revstake factory and
  Memestock launchpad launch is recorded with the transaction that created it.
  A launch matched to the saved review it carried out is listed for that
  review's account. A Memestock launch no review of this site carried out is
  listed from the chain under the wallet that sent it; a Revstake one is
  `unlisted`. A launch the chain cannot answer for yet stays `pending`, with
  the reason, until it can. `listed` and `unlisted` are final.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "launch_discoveries"
    schema("autolaunch_app")
    repo(Regents.Repo)

    identity_index_names(one_per_launch: "launch_discoveries_launch_index")
  end

  attributes do
    uuid_primary_key :id

    attribute :launchpad, :atom,
      allow_nil?: false,
      constraints: [one_of: [:base_revstake, :base_memestock]]

    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]

    # The contract that numbers the launches: the Revstake factory, or the
    # Memestock launchpad.
    attribute :contract, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :launch_id, :integer, allow_nil?: false, constraints: [min: 1]

    # The wallet that sent the launch, as the launchpad recorded it.
    attribute :launcher, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :auction, :string,
      allow_nil?: false,
      constraints: [min_length: 42, max_length: 42]

    attribute :transaction_hash, :string,
      allow_nil?: false,
      constraints: [min_length: 66, max_length: 66]

    attribute :state, :atom,
      allow_nil?: false,
      default: :pending,
      constraints: [one_of: [:pending, :listed, :unlisted]]

    # Set once, from the matched review: the account it was prepared for.
    attribute :creator_human_account_id, :integer

    # Why a launch is still pending or was left unlisted.
    attribute :reason, :string, constraints: [max_length: 120]

    timestamps()
  end

  identities do
    identity :one_per_launch, [:chain_id, :contract, :launch_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
