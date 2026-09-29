defmodule RegentsWeb.Plugs.AgentRateLimit do
  @moduledoc """
  Limits agent requests per client address per minute. Pairing gets a small
  budget; check-ins get their own, larger one, so several agents behind one
  home connection can keep working. Every answer names the budget it was
  counted against and what is left of it, so an agent can pace itself instead
  of learning the limit by a 429.
  """

  @behaviour Plug

  import Plug.Conn

  alias Regents.RateLimiter
  alias RegentsWeb.ClientAddress

  @window_seconds 60
  @pair_limit 10
  @check_in_limit 60

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: [_api, _agents, _v1, "pair"]} = conn, _opts),
    do: admit(conn, "pair", @pair_limit)

  def call(conn, _opts), do: admit(conn, "check-in", @check_in_limit)

  defp admit(conn, policy, limit) do
    {client, _source} = ClientAddress.key(conn)

    case RateLimiter.admit({policy, client}, limit, @window_seconds) do
      {:ok, budget} ->
        put_budget(conn, policy, budget)

      {:error, :rate_limited, budget} ->
        conn
        |> put_budget(policy, budget)
        |> put_resp_header("retry-after", "#{budget.reset}")
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode_to_iodata!(%{error: rate_limited()}))
        |> halt()
    end
  end

  defp put_budget(conn, policy, budget) do
    conn
    |> put_resp_header("ratelimit-policy", ~s("#{policy}";q=#{budget.limit};w=#{budget.window}))
    |> put_resp_header("ratelimit", ~s("#{policy}";r=#{budget.remaining};t=#{budget.reset}))
  end

  defp rate_limited,
    do: %{
      code: "rate_limited",
      message: "Too many requests.",
      hint: "Wait the number of seconds in Retry-After, then try again."
    }
end
