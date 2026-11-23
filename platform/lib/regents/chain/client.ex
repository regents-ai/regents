defmodule Regents.Chain.Client do
  @moduledoc """
  Unified JSON-RPC reads at the latest block for wallet steps, Points checks,
  Keyfleet launch upkeep, and Patchbay offers across all folded Regent products.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`;
  `RegentPoints.ChainClient` and domain callers use `rpc/3` or `rpc/4`.
  Every read is at `latest`: never wait for `safe` or `finalized`. Base is read
  through `:base_read_rpc_url` and Robinhood through `:robinhood_read_rpc_url`,
  never through a public RPC URL from a review.
  """

  @behaviour RegentPoints.ChainClient

  alias Regents.Chain.Rpc

  @base_chain_id 8453
  @robinhood_chain_id 4663
  @base %{chain_id: @base_chain_id, name: "Base", rpc_url: "https://mainnet.base.org"}

  @doc """
  Base, the one chain every wallet step goes to. The root layout names it to
  Privy (the `wallet-chain-id` meta), which connects wallets on it and switches
  them to no other.
  """
  def base, do: @base

  @doc "The transaction sent as `hash`, or `nil` while the chain does not know it."
  def transaction(chain, hash), do: rpc(chain, "eth_getTransactionByHash", [hash])

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  def receipt(chain, hash), do: rpc(chain, "eth_getTransactionReceipt", [hash])

  @doc """
  One JSON-RPC request at `latest` to the site's configured node for `chain`.
  Failed requests count in `health.chain_request_failures.total` under `scope`.
  """
  @impl RegentPoints.ChainClient
  def rpc(chain, method, params, scope \\ "wallet_steps")

  def rpc(%{chain_id: @base_chain_id}, method, params, scope) when is_binary(scope) do
    Rpc.answer(method, params, chain_id: @base_chain_id, scope: scope)
  end

  def rpc(%{chain_id: @robinhood_chain_id}, method, params, scope) when is_binary(scope) do
    url = Application.fetch_env!(:regents, :robinhood_read_rpc_url)
    Rpc.answer(method, params, url: url, chain_id: @robinhood_chain_id, scope: scope)
  end

  def rpc(%{chain_id: chain_id, rpc_url: url}, method, params, scope)
      when is_integer(chain_id) and is_binary(url) and is_binary(scope) do
    Rpc.answer(method, params, url: url, chain_id: chain_id, scope: scope)
  end
end
