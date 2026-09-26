defmodule AshPlatformWeb.AgentController do
  @moduledoc """
  The two requests an agent signs with its SIWA key: joining a person's
  account with the code they gave it, and checking in afterwards.
  """

  use AshPlatformWeb, :controller

  alias AshPlatform.Actors.System
  alias AshPlatform.AgentAuth.{ClaimRateLimiter, VerificationClient}
  alias AshPlatform.Agents
  alias AshPlatformWeb.ClientAddress

  def pair(conn, %{"code" => code, "name" => name, "harness" => harness} = params)
      when map_size(params) == 3 and is_binary(code) and is_binary(name) and is_binary(harness) do
    {client, _source} = ClientAddress.key(conn)

    with :ok <- ClaimRateLimiter.admit(client),
         {:ok, %{wallet: wallet}} <- verify(conn) do
      case Agents.pair_agent(code, wallet, name, harness, actor: %System{}) do
        {:ok, agent} -> conn |> put_status(:created) |> json(%{data: public_agent(agent)})
        {:error, _error} -> pairing_failed(conn)
      end
    else
      {:error, :rate_limited} -> rate_limited(conn)
      {:error, _reason} -> verification_failed(conn)
    end
  end

  def pair(conn, _params), do: pairing_failed(conn)

  def me(conn, params) when map_size(params) == 0 do
    case verify(conn) do
      {:ok, %{wallet: wallet}} -> check_in(conn, wallet)
      {:error, _reason} -> verification_failed(conn)
    end
  end

  def me(conn, _params), do: not_paired(conn)

  defp check_in(conn, wallet) do
    case Agents.check_in_agent(wallet, actor: %System{}) do
      {:ok, agent} -> json(conn, %{data: public_agent(agent)})
      {:error, _not_paired} -> not_paired(conn)
    end
  end

  defp verify(conn) do
    VerificationClient.verify(%{
      method: conn.method,
      path: signed_path(conn),
      headers: Map.new(conn.req_headers),
      body: conn.assigns[:raw_body] || ""
    })
  end

  defp signed_path(%{request_path: path, query_string: ""}), do: path
  defp signed_path(%{request_path: path, query_string: query}), do: path <> "?" <> query

  defp public_agent(agent) do
    %{
      name: agent.name,
      harness: agent.harness,
      wallet: agent.wallet,
      paired_at: DateTime.to_iso8601(agent.paired_at),
      last_contact_at: DateTime.to_iso8601(agent.last_contact_at)
    }
  end

  defp pairing_failed(conn) do
    error(conn, :bad_request, "pairing_failed", "The pairing code could not be used.")
  end

  defp not_paired(conn) do
    error(
      conn,
      :not_found,
      "not_paired",
      "This agent is not paired with an account. Ask your person for a pairing code."
    )
  end

  defp verification_failed(conn) do
    error(
      conn,
      :unauthorized,
      "verification_failed",
      "The signed agent request could not be verified."
    )
  end

  defp rate_limited(conn) do
    error(
      conn,
      :too_many_requests,
      "rate_limited",
      "Too many pairing attempts. Please wait and try again."
    )
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
