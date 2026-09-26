defmodule AshPlatformWeb.AgentController do
  @moduledoc """
  The two requests an agent signs with its SIWA key: joining a person's
  account with the code they gave it, and checking in afterwards.
  """

  use AshPlatformWeb, :controller

  alias AshPlatform.Actors.System
  alias AshPlatform.AgentAuth.VerificationClient
  alias AshPlatform.{Agents, RateLimiter}
  alias AshPlatformWeb.ClientAddress

  # Requests per client address per minute. Check-ins get their own, larger
  # budget, so several agents behind one home connection can keep working.
  @window_seconds 60
  @pair_limit 10
  @check_in_limit 60

  def pair(conn, params) do
    case admit(conn, "pair", @pair_limit) do
      {:ok, conn} -> pair_admitted(conn, params)
      {:rate_limited, conn} -> rate_limited(conn)
    end
  end

  def me(conn, params) do
    case admit(conn, "check-in", @check_in_limit) do
      {:ok, conn} -> check_in_admitted(conn, params)
      {:rate_limited, conn} -> rate_limited(conn)
    end
  end

  defp pair_admitted(conn, %{"code" => code, "name" => name, "harness" => harness} = params)
       when map_size(params) == 3 and is_binary(code) and is_binary(name) and
              is_binary(harness) do
    case verify(conn) do
      {:ok, %{wallet: wallet}} -> pair_wallet(conn, code, wallet, name, harness)
      {:error, _reason} -> verification_failed(conn)
    end
  end

  defp pair_admitted(conn, _params), do: pairing_failed(conn)

  defp pair_wallet(conn, code, wallet, name, harness) do
    case Agents.pair_agent(code, wallet, name, harness, actor: %System{}) do
      {:ok, agent} -> conn |> put_status(:created) |> json(%{data: public_agent(agent)})
      {:error, _error} -> pairing_failed(conn)
    end
  end

  defp check_in_admitted(conn, params) when map_size(params) == 0 do
    case verify(conn) do
      {:ok, %{wallet: wallet}} -> check_in(conn, wallet)
      {:error, _reason} -> verification_failed(conn)
    end
  end

  defp check_in_admitted(conn, _params), do: not_paired(conn)

  # Every answer names the budget it was counted against and what is left of
  # it, so an agent can pace itself instead of learning the limit by a 429.
  defp admit(conn, policy, limit) do
    {client, _source} = ClientAddress.key(conn)

    case RateLimiter.admit({policy, client}, limit, @window_seconds) do
      {:ok, budget} ->
        {:ok, put_budget(conn, policy, budget)}

      {:error, :rate_limited, budget} ->
        conn =
          conn |> put_budget(policy, budget) |> put_resp_header("retry-after", "#{budget.reset}")

        {:rate_limited, conn}
    end
  end

  defp put_budget(conn, policy, budget) do
    conn
    |> put_resp_header("ratelimit-policy", ~s("#{policy}";q=#{budget.limit};w=#{budget.window}))
    |> put_resp_header("ratelimit", ~s("#{policy}";r=#{budget.remaining};t=#{budget.reset}))
  end

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
      body: signed_body(conn)
    })
  end

  # A request without a body, like a check-in, is signed without one.
  defp signed_body(%{assigns: %{raw_body: body}}) when body != "", do: body
  defp signed_body(_conn), do: nil

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
      "Too many requests. Wait the number of seconds in Retry-After, then try again."
    )
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
