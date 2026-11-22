defmodule Regents.Account.Agents.HostedAddress do
  @moduledoc """
  The wallet of each connected app's hosted identity: the identity an app such
  as Claude keeps for its person's account here, held by the sign-in service.
  Each app the person connects has its own. Once `RegentMCPAgents.address/1`
  answers, it is kept on this machine by the account and the app's client
  together. Failures are never cached.
  """

  @cache :regents_hosted_address

  @doc "The cache's name, for the application's supervisor."
  def cache, do: @cache

  @doc "The wallet of the identity the connection's app keeps for its account here."
  @spec read(map()) :: {:ok, String.t()} | {:error, :unavailable}
  def read(%{subject: subject, client_id: client} = principal) do
    case Cachex.fetch(@cache, {subject, client}, fn _key -> ask(principal) end) do
      {:error, _raised} -> {:error, :unavailable}
      {_kind, answer} -> answer
    end
  end

  defp ask(principal) do
    case RegentMCPAgents.address(principal) do
      {:ok, address} -> {:commit, {:ok, address}}
      {:error, _reason} -> {:ignore, {:error, :unavailable}}
    end
  end
end
