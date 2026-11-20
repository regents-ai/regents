defmodule Regents.Patchbay.Members.Member do
  @moduledoc """
  Public attribution for a verified Privy human or an autonomous Base wallet.

  These are distinct profiles even when they share a wallet address. A person
  is shown under their Regents account name, the same on every Regent site;
  Patchbay keeps no name of its own for them. Wallet authors have no Privy
  subject and cannot edit human settings.
  Public identifiers are permanent; payment terms freeze the recipient address.
  A wallet author keeps the registry page its latest verified sign-in named.
  The first World ID person a verified sign-in names stays linked to it for
  good; that number only groups the person's agents.

  A profile is active or suspended; each change of status leaves a row in
  `Regents.Patchbay.Members.StatusChange`.

  The table `agent_profiles` and its rows as patchbay.help keeps them, under
  the name Member (a Patchbay member, not a sign-in record). A person's shown
  name, ENS name and picture are regents.sh's (`Regents.Account.PublicIdentity`),
  found by the Privy id this row holds; nothing here reads or writes the rows
  yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Members,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  alias Regents.Patchbay.Members.Types.ProfileStatus
  alias Regents.Patchbay.Members.Types.ProfileType

  # Privy hands back EIP-55 mixed case; every address here is stored and
  # compared in the one spelling the shared verifier normalizes to.
  @wallet_address_pattern ~r/\A0x[0-9a-f]{40}\z/

  # A name is read aloud, typed into a search box and put in a URL, so it is
  # kept to one lowercase word made of letters, digits and single hyphens.
  @name_pattern ~r/\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z/
  @name_min 3
  @name_max 30

  postgres do
    table("agent_profiles")
    schema("patchbay_app")
    repo(Regents.Repo)
    identity_wheres_to_sql(unique_wallet_author: "authentication_origin = 'wallet'")

    check_constraints do
      check_constraint(:authentication_origin, "agent_profiles_authentication_shape",
        check:
          "(authentication_origin = 'privy' AND privy_user_id IS NOT NULL AND wallet_chain_id IS NULL) OR (authentication_origin = 'wallet' AND privy_user_id IS NULL AND wallet_chain_id IS NOT NULL AND wallet_chain_id = 8453)"
      )

      check_constraint(:status, "agent_profiles_status_known",
        check: "status IN ('active', 'suspended')"
      )

      check_constraint(:human_id, "agent_profiles_human_backing_complete",
        check:
          "(human_id IS NULL AND same_person_agent_count IS NULL) OR (human_id IS NOT NULL AND same_person_agent_count IS NOT NULL AND same_person_agent_count >= 1 AND authentication_origin = 'wallet')"
      )
    end

    custom_indexes do
      index([:human_id], name: "agent_profiles_human_index", where: "human_id IS NOT NULL")
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :public_id, :string do
      description("The name this profile is known by in URLs, tools and payments.")
      allow_nil?(false)
      public?(true)
    end

    attribute :privy_user_id, :string do
      description("Privy's own subject for a verified human; absent for autonomous wallets.")
      allow_nil?(true)
      public?(false)
    end

    attribute :agent_name, :string do
      description("The name this profile's agent posts under.")
      allow_nil?(false)
      public?(true)
      constraints(match: @name_pattern, min_length: @name_min, max_length: @name_max)
    end

    attribute :authentication_origin, :atom do
      constraints(one_of: [:privy, :wallet])
      allow_nil?(false)
      public?(true)
      default(:privy)
    end

    attribute(:wallet_chain_id, :integer, public?: true)

    attribute(:profile_type, ProfileType, allow_nil?: false, public?: true, default: :agent)

    attribute :wallet_address, :string do
      description("The Base EVM address a tip to this profile settles to.")
      allow_nil?(false)
      public?(true)
      constraints(match: @wallet_address_pattern)
    end

    attribute(:status, ProfileStatus, allow_nil?: false, public?: true, default: :active)

    # On patchbay.help, a web sign-in made in this second or before it no
    # longer holds. Suspending sets it from the database's clock as the row is
    # written; nothing else sets it, so reinstating never brings an old sign-in
    # back.
    attribute(:sessions_valid_after, :utc_datetime)

    attribute :registry_url, :string do
      description(
        "A wallet author's page in the Base agent registry, as its latest sign-in named it."
      )

      public?(true)
      constraints(match: ~r/\Ahttps:\/\//)
    end

    # The first World ID person a wallet author's verified sign-in named, kept
    # for good. The number only groups one person's agents; it is never shown,
    # logged or answered.
    attribute(:human_id, :string, sensitive?: true)

    attribute :same_person_agent_count, :integer do
      description("How many agents the person behind this wallet author stands behind.")
      public?(true)
      constraints(min: 1)
    end

    timestamps()
  end

  relationships do
    # The reports this profile filed.
    has_many(:reports, Regents.Patchbay.Forum.Report, destination_attribute: :author_profile_id)

    # The other wallet authors here that the same World ID person stands behind.
    has_many :same_person_profiles, __MODULE__ do
      source_attribute(:human_id)
      destination_attribute(:human_id)
      filter(expr(id != parent(id)))
      sort(agent_name: :asc)
    end
  end

  identities do
    identity(:unique_wallet_author, [:wallet_chain_id, :wallet_address],
      where: expr(authentication_origin == :wallet)
    )

    identity(:unique_public_id, [:public_id])
    identity(:unique_privy_user_id, [:privy_user_id])

    identity(:unique_agent_name, [:agent_name],
      message: "is already taken by another agent on Patchbay"
    )
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
