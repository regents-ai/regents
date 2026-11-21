defmodule Regents.Keyfleet.ChainClient do
  @moduledoc """
  JSON-RPC reads at the latest block of the chain a review names.

  `RegentChain.Outcome` reads sent steps through `transaction/2` and `receipt/2`;
  Regent Points reads the NFTs an account's wallets hold through `rpc/3`.
  Every read is at `latest`: never count confirmations and never wait for `safe`
  or `finalized`. The node is the site's own for the chain (`:chain_nodes`), never
  the public address a wallet adds the chain with, and never from the browser, so a
  private node or a lab fork reads what the site's steps sent.
  """

  @behaviour RegentPoints.ChainClient

  @doc "The transaction sent as `hash`, or `nil` while the chain does not know it."
  def transaction(chain, hash), do: rpc(chain, "eth_getTransactionByHash", [hash])

  @doc "The receipt for `hash`, or `nil` while it has not landed."
  def receipt(chain, hash), do: rpc(chain, "eth_getTransactionReceipt", [hash])

  @doc """
  One JSON-RPC request to the chain's node. Every request that gets no answer
  is counted in `health.chain_request_failures.total` (`RegentsWeb.Keyfleet.Telemetry`)
  under the scope "wallet"; the fleet reader counts its own under "fleet"
  (`Regents.Keyfleet.Chain.RpcClient`).
  """
  @impl RegentPoints.ChainClient
  def rpc(%{chain_id: chain_id} = chain, method, params) do
    url = :regents |> Application.fetch_env!(:keyfleet_chain_nodes) |> Map.fetch!(chain_id)

    case Req.post(url,
           json: %{jsonrpc: "2.0", id: 1, method: method, params: params},
           retry: false,
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"result" => result}}} -> {:ok, result}
      {:ok, %{body: %{"error" => error}}} -> failed(chain, method, {:rpc, error})
      {:ok, %{status: status}} -> failed(chain, method, {:http, status})
      {:error, error} -> failed(chain, method, error)
    end
  end

  defp failed(chain, method, reason) do
    :telemetry.execute([:regents, :keyfleet_chain, :failure], %{count: 1}, %{
      method: method,
      class: class(reason),
      chain_id: chain.chain_id,
      scope: "wallet"
    })

    {:error, reason}
  end

  defp class({:rpc, _error}), do: "rpc"
  defp class({:http, status}), do: "http_#{status}"

  defp class(%Req.TransportError{reason: reason}) when reason in [:timeout, :connect_timeout],
    do: "timeout"

  defp class(_transport), do: "transport"
end
