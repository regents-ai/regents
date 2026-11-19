defmodule RegentAgentAccess.RateLimit do
  @moduledoc """
  Counts each request against a per-client budget and tells the caller where it
  stands, with the IETF rate-limit headers (draft-ietf-httpapi-ratelimit-headers):
  `RateLimit-Policy` names the budget, how many requests it holds and its window
  in seconds; `RateLimit` says how many are left and the seconds until the
  window resets. Past the budget the answer is 429 with `Retry-After` and the
  JSON error body from `RegentAgentAccess.Recovery.json/2`.

  Place it in a router pipeline:

      plug RegentAgentAccess.RateLimit,
        policy: "default",
        limit: 120,
        window: 60,
        admit: &MyApp.RequestRateLimiter.admit/3,
        key: &MyAppWeb.ClientAddress.key/1

  Options:

    * `:policy` - the budget's name in both headers.
    * `:limit` - requests allowed in one window.
    * `:window` - the window in seconds.
    * `:admit` - the product's counter, called as `admit.({policy, key}, limit,
      window)`. It returns `{:ok, budget}` or `{:error, :rate_limited, budget}`,
      where `budget` is `%{limit: _, remaining: _, reset: _, window: _}` and
      `reset` is the whole seconds until the window resets.
    * `:key` - a function from the conn to the client the budget belongs to.

  A controller that counts its own budget calls `put_headers/3` with the budget
  its counter returned. Several budgets on one answer are listed together.
  """
  @behaviour Plug

  import Plug.Conn

  @type budget :: %{
          limit: pos_integer(),
          remaining: non_neg_integer(),
          reset: pos_integer(),
          window: pos_integer()
        }

  @hint "Wait the number of seconds in Retry-After, then send the request again."

  @impl Plug
  def init(opts),
    do: Map.new([:policy, :limit, :window, :admit, :key], &{&1, Keyword.fetch!(opts, &1)})

  @impl Plug
  def call(conn, %{policy: policy, limit: limit, window: window, admit: admit, key: key}) do
    case admit.({policy, key.(conn)}, limit, window) do
      {:ok, budget} ->
        put_headers(conn, policy, budget)

      {:error, :rate_limited, budget} ->
        conn
        |> put_headers(policy, budget)
        |> put_resp_header("retry-after", Integer.to_string(budget.reset))
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.json(RegentAgentAccess.Recovery.json("Too Many Requests", @hint))
        |> halt()
    end
  end

  @doc "Adds `budget`, counted under `policy`, to the answer's rate-limit headers."
  @spec put_headers(Plug.Conn.t(), String.t(), budget()) :: Plug.Conn.t()
  def put_headers(conn, policy, budget) do
    conn
    |> append("ratelimit-policy", ~s("#{policy}";q=#{budget.limit};w=#{budget.window}))
    |> append("ratelimit", ~s("#{policy}";r=#{budget.remaining};t=#{budget.reset}))
  end

  defp append(conn, header, item),
    do: put_resp_header(conn, header, Enum.join(get_resp_header(conn, header) ++ [item], ", "))
end
