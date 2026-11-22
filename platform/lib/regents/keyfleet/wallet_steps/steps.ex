defmodule Regents.Keyfleet.WalletSteps.Steps do
  @moduledoc """
  One group of wallet buttons' steps, built for a signer as
  `Regents.Keyfleet.WalletSteps.Build` describes.

  Only a signed-in person or agent may build steps, and only for their own
  wallet: one the person's account links, or the agent's own. The signer is
  checked against the actor's own wallets, never taken from the request on
  trust.

  Anyone may read the figures some groups show, which are public on the
  chain: the Key on sale, the daily split's preview, whether keys are
  present, and the fleet's launch. They are read the same way, and nothing
  is built to send.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.WalletSteps,
    authorizers: [Ash.Policy.Authorizer]

  @flows [
    :buy,
    :reveal,
    :claim,
    :claim_all,
    :club_claim,
    :present,
    :present_idle,
    :issue_shard,
    :end_shard,
    :agent_voting,
    :ballot,
    :propose,
    :cancel,
    :carry_out,
    :run_split,
    :return_advance,
    :send_share,
    :convert,
    :launch_upkeep
  ]

  actions do
    action :build, :map do
      description "The steps one group of wallet buttons sends, for one signer."
      argument :fleet_id, :string, allow_nil?: false
      argument :flow, :atom, allow_nil?: false, constraints: [one_of: @flows]

      argument :signer, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A0x[0-9a-fA-F]{40}\z/]

      argument :component_id, :string, allow_nil?: false

      argument :inputs, :map,
        allow_nil?: false,
        default: %{},
        description: "The form's values as the page shows them, as strings."

      argument :proposal, :integer, constraints: [min: 1]
      argument :token_id, :integer, constraints: [min: 1]
      argument :advance_id, :integer, constraints: [min: 1]

      argument :sending, :boolean,
        allow_nil?: false,
        default: true,
        description:
          "Whether a press sends from the signer now; false when the steps only show the figures of a wallet that isn't open."

      validate present(:proposal), where: argument_in(:flow, [:ballot, :cancel, :carry_out])

      validate present(:token_id),
        where: argument_in(:flow, [:claim, :club_claim, :reveal, :end_shard])

      validate present(:advance_id), where: argument_in(:flow, [:return_advance])

      run Regents.Keyfleet.WalletSteps.Build
    end

    action :figures, :map do
      description "What a group of wallet buttons shows, for anyone, with nothing to send."
      argument :fleet_id, :string, allow_nil?: false

      argument :flow, :atom,
        allow_nil?: false,
        constraints: [one_of: [:buy, :run_split, :present, :launch_upkeep]]

      argument :token_id, :integer, constraints: [min: 1]

      run Regents.Keyfleet.WalletSteps.Figures
    end
  end

  policies do
    policy action(:build) do
      authorize_if Regents.Keyfleet.WalletSteps.LinkedSigner
    end

    policy action(:figures) do
      authorize_if always()
    end
  end
end
