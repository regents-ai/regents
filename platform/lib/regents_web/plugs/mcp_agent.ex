defmodule RegentsWeb.Plugs.McpAgent do
  @moduledoc """
  Admits a request to the unified hosted MCP server at `/mcp`, and sets the Ash
  actor before `AshAi.Mcp.Router` runs the tool. Cookies are never read, and
  `RegentsWeb.Plugs.ReadOnly` refuses every request on the read-only venue.

  Every request must be `POST /mcp`, JSON, single JSON-RPC call (no batch),
  with no query string and either no `Origin` or this site's own origin, and
  must present exactly one credential:

  - A SIWA-signed request from a paired agent (`RegentsWeb.Account.PairedAgent`).
  - A Bearer token issued by `Regents.OAuth` for this site's `/mcp` resource.
  """

  @behaviour Plug

  import Plug.Conn

  alias RegentAgentAccess.RateLimit
  alias Regents.Account.Actors.{Agent, ConnectedApp, Human}
  alias Regents.Account.Agents.HostedAddress
  alias Regents.RateLimiter
  alias RegentsWeb.Account.PairedAgent
  alias RegentsWeb.{ClientAddress, PublicDocuments}

  @address RateLimit.init(
             policy: "mcp_address",
             limit: 120,
             window: 60,
             admit: &RateLimiter.admit/3,
             key: &__MODULE__.address_key/1
           )

  @connected_address RateLimit.init(
                       policy: "mcp_connected_address",
                       limit: 600,
                       window: 60,
                       admit: &RateLimiter.admit/3,
                       key: &__MODULE__.address_key/1
                     )

  @budget RateLimit.init(
            policy: "mcp",
            limit: 120,
            window: 60,
            admit: &RateLimiter.admit/3,
            key: &__MODULE__.account/1
          )

  @impl true
  def init(opts), do: opts

  @doc """
  Counts the request against its address before the body is read. While the
  connector is on, one with a token waits for token verification unless its
  address has spent its 120/min budget.
  """
  def limit_address(conn) do
    if waits_for_token?(conn) and not spent?(conn, @address),
      do: conn,
      else: RateLimit.call(conn, @address)
  end

  defp waits_for_token?(conn),
    do: Regents.OAuth.enabled?() and get_req_header(conn, "authorization") != []

  defp spent?(conn, %{policy: policy, limit: limit, window: window, key: key}),
    do: RateLimiter.spent?({policy, key.(conn)}, limit, window)

  @impl true
  def call(conn, _opts) do
    conn =
      conn
      |> Ash.PlugHelpers.set_context(%{patchbay_limit_key: ClientAddress.tag(conn)})
      |> register_before_send(&put_resp_header(&1, "cache-control", "private, no-store"))

    cond do
      conn.query_string != "" ->
        refuse(conn, :none, "unsupported_query")

      conn.path_info != ["mcp"] ->
        refuse(conn, :none, "not_found")

      conn.method != "POST" ->
        conn |> put_resp_header("allow", "POST") |> refuse(:none, "method_not_allowed")

      not own_origin?(conn) ->
        refuse(conn, :none, "origin_not_allowed")

      not json?(conn) ->
        refuse(conn, :none, "unsupported_media_type")

      is_list(conn.body_params["_json"]) ->
        refuse(conn, :none, "batch_not_supported")

      true ->
        caller(conn)
    end
  end

  @doc false
  def address_key(conn) do
    {key, _source} = ClientAddress.key(conn)
    key
  end

  @doc false
  def account(conn), do: conn |> Ash.PlugHelpers.get_actor() |> person()

  defp person(%ConnectedApp{principal: %{subject: subject}}), do: subject
  defp person(%Agent{privy_user_id: privy_user_id}), do: privy_user_id

  defp caller(conn) do
    case {Siwa.AgentAuthPlug.signed_request?(conn), get_req_header(conn, "authorization")} do
      {true, [_ | _]} -> refuse(conn, :both, "ambiguous_credentials")
      {true, []} -> agent(conn)
      {false, [_ | _] = token} -> connected_app(conn, token)
      {false, []} -> no_one(conn)
    end
  end

  defp own_origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin == PublicDocuments.url("")
      _several -> false
    end
  end

  defp json?(conn) do
    case get_req_header(conn, "content-type") do
      [type] -> match?({:ok, "application", "json", _params}, Plug.Conn.Utils.content_type(type))
      _none_or_several -> false
    end
  end

  defp agent(conn) do
    conn = PairedAgent.call(conn, [])

    if conn.halted do
      counted(conn, :siwa_request)
    else
      {actor, assigns} = Map.pop!(conn.assigns, :actor)

      %{conn | assigns: assigns}
      |> Ash.PlugHelpers.set_actor(actor)
      |> spend(@budget)
      |> counted(:siwa_request)
    end
  end

  defp connected_app(conn, token) do
    with true <- Regents.OAuth.enabled?(),
         ["Bearer " <> bearer] <- token,
         {:ok, principal} <- RegentOAuth.verify(bearer, RegentOAuth.resource(), scope()) do
      conn
      |> Ash.PlugHelpers.set_actor(%ConnectedApp{principal: principal})
      |> spend(@connected_address)
      |> spend(@budget)
      |> as_paired_agent(principal)
      |> counted(:site_oauth)
    else
      false -> refuse(conn, :site_oauth, "delegated_access_not_enabled")
      _not_this_sites -> refuse(conn, :site_oauth, &challenge/1)
    end
  end

  defp spend(%{halted: true} = conn, _budget), do: conn
  defp spend(conn, budget), do: RateLimit.call(conn, budget)

  defp as_paired_agent(%{halted: true} = conn, _principal), do: conn

  defp as_paired_agent(conn, %{subject: subject} = principal) do
    with true <- Regents.OAuth.agent_scope() in principal.scopes,
         {:ok, address} <- HostedAddress.read(principal),
         {:ok, %Agent{pairing: %Human{}, privy_user_id: ^subject} = agent} <-
           Agent.with_pairing(%Agent{
             wallet_address: address,
             chain_id: 8453,
             verification_method: :connected_app,
             audience: "regents",
             connection: principal
           }) do
      conn
      |> Ash.PlugHelpers.set_actor(agent)
      |> PairedAgent.recheck_before_response(agent)
    else
      false ->
        conn

      {:ok, %Agent{}} ->
        conn

      {:error, _reason} ->
        refusal(conn, "identity_unavailable")
    end
  end

  defp no_one(conn) do
    if Regents.OAuth.enabled?(),
      do: refuse(conn, :none, &challenge/1),
      else: refuse(conn, :none, "agent_auth_required")
  end

  defp challenge(conn) do
    conn
    |> put_resp_header(
      "www-authenticate",
      RegentOAuth.challenge(Enum.join(RegentOAuth.scopes(), " "))
    )
    |> refusal("connection_required")
  end

  defp scope, do: RegentMCPAgents.identity_scope()

  defp refuse(conn, mode, code) when is_binary(code), do: refuse(conn, mode, &refusal(&1, code))

  defp refuse(conn, mode, refusal) do
    conn = if waits_for_token?(conn), do: RateLimit.call(conn, @address), else: conn

    if conn.halted, do: counted(conn, mode), else: conn |> refusal.() |> counted(mode)
  end

  defp refusal(conn, code) do
    {status, message, hint} = words(code)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: %{code: code, message: message, hint: hint}})
    |> halt()
  end

  defp words("unsupported_query"),
    do:
      {400, "The MCP address takes no query string.",
       "Send the same request to #{url()} with nothing after it. #{guide()}"}

  defp words("not_found"),
    do:
      {404, "There is nothing at this address.",
       "The hosted MCP server is at #{url()} alone. #{guide()}"}

  defp words("method_not_allowed"),
    do:
      {405, "The MCP address takes POST only.",
       "Send each JSON-RPC call as a POST to #{url()}. #{guide()}"}

  defp words("origin_not_allowed"),
    do:
      {403, "A page on another site can't call this server.",
       "Call it from your agent or app, not from a web page on another site. #{guide()}"}

  defp words("unsupported_media_type"),
    do:
      {415, "The MCP address takes a JSON body only.",
       "Send one JSON-RPC call with Content-Type: application/json. #{guide()}"}

  defp words("batch_not_supported"),
    do:
      {400, "Send one call a request.",
       "Send each call in its own request, each signed on its own, then send the request again. #{guide()}"}

  defp words("ambiguous_credentials"),
    do:
      {401, "Send your agent's signature or a connected app's token, not both.",
       "Leave out the Authorization header to call as your agent, or the signature headers to call as the connected app, then send the request again."}

  defp words("delegated_access_not_enabled"),
    do:
      {401, "This site doesn't take a connected app's token yet.",
       "Call as your agent instead: #{sign_in_how()}"}

  defp words("connection_required"),
    do:
      {401, "Connect this site, or sign the request as your agent.",
       "Add #{url()} to your app's connectors, such as Claude's, and approve it on this site, or #{sign_in_how()}"}

  defp words("identity_unavailable"),
    do:
      {503, "This connection's identity could not be read right now.",
       "Try again in a minute. #{guide()}"}

  defp words("agent_auth_required"),
    do: {401, "This server needs your agent's signature.", sign_in_how()}

  defp url, do: PublicDocuments.url("/mcp")

  defp guide, do: "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/agents.md")}."

  defp sign_in_how,
    do:
      "run regents mcp, which signs each call with your agent's wallet, or sign it yourself as the guide at #{PublicDocuments.url("/agents.md")} sets out, then send the request again."

  defp counted(conn, mode) do
    outcome = if conn.halted, do: :refused, else: :accepted
    :telemetry.execute([:regents, :mcp, :auth], %{count: 1}, %{mode: mode, outcome: outcome})
    conn
  end
end
