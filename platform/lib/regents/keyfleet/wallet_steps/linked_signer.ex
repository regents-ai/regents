defmodule Regents.Keyfleet.WalletSteps.LinkedSigner do
  @moduledoc """
  The signer is the actor's own wallet: one the signed-in person's account
  links, or the signed-in agent's own.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human

  @impl true
  def describe(_opts), do: "the signer is the signed-in person's or agent's own wallet"

  @impl true
  def match?(
        %Human{wallet_addresses: wallets},
        %{subject: %{arguments: %{signer: signer}}},
        _opts
      )
      when is_binary(signer),
      do: String.downcase(signer) in wallets

  def match?(
        %Agent{wallet_address: wallet} = agent,
        %{subject: %{arguments: %{signer: signer}}},
        _opts
      )
      when is_binary(signer),
      do: Agent.valid?(agent) and String.downcase(signer) == wallet

  def match?(_actor, _context, _opts), do: false
end
