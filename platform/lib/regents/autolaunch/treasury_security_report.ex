defmodule Regents.Autolaunch.TreasurySecurityReport do
  @moduledoc """
  One reading of a launch treasury's setup on chain, at one block: what kind of
  account it is, its owners, threshold, modules and guard, and the evidence it
  was judged on.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @classifications [
    :supported_safe,
    :safe_1_of_1,
    :eoa,
    :delegated_eoa,
    :unknown_contract,
    :split,
    :unsupported
  ]

  @verification_states [:verified, :unverified]
  @downgrade_states [:none, :downgraded]

  postgres do
    table "treasury_security_reports"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:address, :source_block_number])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :address, :string do
      allow_nil? false
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :chain_id, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :classification, :atom do
      allow_nil? false
      public? true
      constraints one_of: @classifications
    end

    attribute :safe_version, :string, public?: true
    attribute :safe_singleton, :string, public?: true

    attribute :owner_addresses, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :owner_count, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :threshold, :integer do
      public? true
      constraints min: 0
    end

    attribute :modules, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :guard, :string, public?: true
    attribute :fallback_handler, :string, public?: true

    attribute :configuration_fingerprint, :string do
      allow_nil? false
      public? true
      constraints min_length: 66, max_length: 66, match: ~r/\A0x[0-9a-f]{64}\z/
    end

    attribute :source_block_number, :integer do
      allow_nil? false
      public? true
      constraints min: 0
    end

    attribute :source_block_hash, :string do
      allow_nil? false
      public? true
      constraints min_length: 66, max_length: 66, match: ~r/\A0x[0-9a-f]{64}\z/
    end

    attribute :observed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :verification_state, :atom do
      allow_nil? false
      public? true
      constraints one_of: @verification_states
    end

    attribute :verification_reason, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100
    end

    attribute :usdc_evidence, :map, public?: true
    attribute :regent_evidence, :map, public?: true
    attribute :outbound_evidence, :map, public?: true

    # No longer written (Sean, 9 Nov, 4 a: a treasury is judged by its current
    # setup alone). Both fields are dropped by the next release, once no
    # machine of the release before still reads them.
    attribute :downgrade_state, :atom do
      allow_nil? false
      select_by_default? false
      default :none
      constraints one_of: @downgrade_states
    end

    attribute :prior_verified_fingerprint, :string do
      select_by_default? false
      constraints min_length: 66, max_length: 66, match: ~r/\A0x[0-9a-f]{64}\z/
    end

    timestamps()
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
