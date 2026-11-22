defmodule RegentsWeb.Techtree.PublicationRate do
  @moduledoc """
  How many runs one caller may publish before being asked to wait.

  Every other address on this site is a read, with a generous budget per
  caller (`RegentsWeb.Endpoint`). The one address that accepts something has
  a small budget of its own, so a caller over the limit is told to come back — with the number of seconds until
  they may, because a refusal that does not say when is a refusal that invites
  a retry loop.

  The refusal says retrying could help, and it is true here: the window turns
  over.

  Every answer to that address says where the caller stands in this budget,
  named `publication`, with the same `RateLimit-Policy` and `RateLimit` headers
  the rest of the API sends for its own budget. The rest of the API's budget
  does not count this address: this one is the limit here.

  It stands in the endpoint, in front of the parser, so a caller already over
  the limit is refused before their body is read, let alone decoded. Each
  request is counted against its address here and nowhere else.
  `RegentsWeb.Techtree.PublicationAddress` decides which requests those are, and
  `RegentsWeb.ClientAddress` says who the caller is. A publication is counted
  once more, against its paired agent's own budget, `publication-agent`, by
  `RegentsWeb.Techtree.PublicationController` once the agent is known.

  The refusal also closes the connection. A body that was sent is otherwise
  still read off a kept-alive connection after the answer, and the point of
  refusing here is that it is not read.
  """

  @behaviour Plug

  alias Regents.RateLimiter
  alias Regents.Techtree.Network
  alias RegentsWeb.ClientAddress
  alias RegentsWeb.Techtree.ExactResponse

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _options) do
    if publication_post?(conn), do: count(conn), else: conn
  end

  defp publication_post?(%{method: "POST", path_info: ["api", "v1", "techtree", "publications"]}),
    do: true

  defp publication_post?(%{
         method: "POST",
         path_info: ["api", "v1", "techtree", "model-climb", "reports"]
       }),
       do: true

  defp publication_post?(_conn), do: false

  defp count(conn) do
    {key, _source} = ClientAddress.key(conn)
    admit(conn, "publication", {:publication, key}, Network.rate_limit())
  end

  @doc """
  Count one request by `key` against `limits`, under the budget named `policy`:
  the connection with that budget's headers, or the refusal, halted.
  `RegentsWeb.Techtree.PublicationController` counts each paired agent this way too.
  """
  @spec admit(Plug.Conn.t(), String.t(), term(), keyword()) :: Plug.Conn.t()
  def admit(conn, policy, key, limits) do
    case RateLimiter.admit(
           key,
           Keyword.fetch!(limits, :limit),
           Keyword.fetch!(limits, :window_seconds)
         ) do
      {:ok, budget} ->
        RegentAgentAccess.RateLimit.put_headers(conn, policy, budget)

      {:error, :rate_limited, budget} ->
        conn
        |> RegentAgentAccess.RateLimit.put_headers(policy, budget)
        |> ExactResponse.put_api_headers()
        |> Plug.Conn.put_resp_header("retry-after", Integer.to_string(budget.reset))
        |> Plug.Conn.put_resp_header("connection", "close")
        |> ExactResponse.send_error(
          429,
          :publication_rate_limited,
          "runs are published and withdrawn one at a time by a person, not in a stream; try again shortly",
          "Wait the seconds in the Retry-After header, then send the same request again."
        )
        |> Plug.Conn.halt()
    end
  end
end
