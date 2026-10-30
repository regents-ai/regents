defmodule Regents.Agents.HostedAddress do
  @moduledoc """
  The wallet of each account's hosted identity: the one identity an app such as
  Claude keeps when its person connects it here, held by the sign-in service.
  It never changes for an account on this site, so once the service has given it
  (`RegentMCPAgents.address/1`) it is kept on this machine and every later call
  from the app reads it here. An answer that failed is not kept: the next call
  asks again.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @doc "The wallet of the identity the connection's account keeps here."
  @spec read(map()) :: {:ok, String.t()} | {:error, :unavailable}
  def read(%{subject: subject} = principal) do
    case get!(subject) do
      nil -> ask(principal)
      address -> {:ok, address}
    end
  end

  # Two calls that miss at once both ask; the service gives both the same wallet.
  defp ask(%{subject: subject} = principal) do
    case RegentMCPAgents.address(principal) do
      {:ok, address} ->
        put!(subject, address)
        {:ok, address}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end
end
