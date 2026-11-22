defmodule Regents.Keyfleet.WalletSteps do
  @moduledoc """
  The steps a person's wallet sends from Keyfleet's wallet buttons, built on
  the server for the one wallet that may send them. Pages push the built
  steps to the browser before anyone presses; the browser never encodes a
  transaction. Any route that offers the same actions builds them here too.
  """
  use Ash.Domain

  resources do
    resource Regents.Keyfleet.WalletSteps.Steps do
      define :build_steps, action: :build, args: [:fleet_id, :flow, :signer, :component_id]
      define :read_figures, action: :figures, args: [:fleet_id, :flow]
    end
  end

  @doc """
  The one chain the site's wallet buttons send on, the only entry in
  `:wallet_chains`, as `chain/1` gives it. The root layout hands it to the
  page, and Privy connects every wallet on it (`privy_bridge.tsx`).
  """
  def chain do
    [chain_id] = :regents |> Application.fetch_env!(:keyfleet_wallet_chains) |> Map.keys()
    chain(chain_id)
  end

  @doc """
  The chain a fleet on `chain_id` sends to, as a review names it:
  `%{chain_id: id, name: name, rpc_url: url}` from `:wallet_chains`, or nil
  when the site sets none for it. The page's words use the name. Privy takes
  the name and the public `rpc_url` for a network not in its own list, such as
  the anvil lab's; `RegentChain.Review` requires the `rpc_url` too.
  """
  def chain(chain_id) do
    case Application.fetch_env!(:regents, :keyfleet_wallet_chains) do
      %{^chain_id => %{name: name, rpc_url: rpc_url}} ->
        %{chain_id: chain_id, name: name, rpc_url: rpc_url}

      _unlisted ->
        nil
    end
  end
end
