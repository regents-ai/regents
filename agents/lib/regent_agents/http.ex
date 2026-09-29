defmodule RegentAgents.HTTP do
  @moduledoc """
  The two requests an agent signs with its SIWA key, the same on every site:
  `POST /pair` joins a person's account with the code they gave it, and
  `GET /me` checks in and answers with the pairing.

  Mount it with `forward "/api/agents/v1", RegentAgents.HTTP` behind the site's
  own rate limit and a body reader that keeps the raw body in
  `conn.assigns.raw_body`, since the agent signs the exact bytes. The SIWA
  service verifies every request for this site's audience; when it refuses
  one, the agent gets its status, code, message and hint back unchanged.

  A check-in names the person's account as the site's own pages name it, from
  the site's `config :regent_agents, account: {Module, :function}`, called with
  the person's Privy user ID and returning a JSON-ready map.
  """

  @behaviour Plug

  import Plug.Conn

  alias RegentAgents.{Agent, Broker, Harness}

  @guide "https://siwa.regents.sh/skill.md"
  @harnesses Enum.map_join(Harness.values(), ", ", &Atom.to_string/1)

  # Every refusal: a code for programs, a message and a hint for people.
  @errors %{
    "pairing_failed" =>
      {400, "The pairing code could not be used.",
       "Ask your person for a new pairing code. Each code works once and expires ten minutes after it was made."},
    "harness_unknown" =>
      {400, "That harness is not one we know.",
       "Send one of: #{@harnesses}. Send other if yours is not listed."},
    "not_paired" =>
      {404, "This agent is not paired with an account.",
       "Ask your person for a pairing code, then pair again."},
    "verification_failed" =>
      {401, "The signed agent request could not be verified.",
       "Sign the request with your agent key as #{@guide} describes, then send it again."},
    "verification_unavailable" =>
      {503, "The sign-in service could not be reached.", "Try again in a minute."},
    "not_found" =>
      {404, "There is no such agent request.",
       "Agents pair with POST /api/agents/v1/pair and check in with GET /api/agents/v1/me."}
  }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: ["pair"]} = conn, _opts), do: pair(conn)
  def call(%Plug.Conn{method: "GET", path_info: ["me"]} = conn, _opts), do: me(conn)
  def call(conn, _opts), do: error(conn, "not_found")

  defp pair(
         %{body_params: %{"code" => code, "name" => name, "harness" => harness} = params} = conn
       )
       when map_size(params) == 3 and is_binary(code) and is_binary(name) and is_binary(harness) do
    with {:ok, harness} <- harness(harness),
         {:ok, agent, conn} <- verify(conn),
         {:ok, paired} <- RegentAgents.pair_agent(code, name, harness, actor: agent) do
      conn |> put_status(:created) |> answer(%{data: present(paired)})
    else
      {:error, :harness_unknown} -> error(conn, "harness_unknown")
      {:refused, conn} -> conn
      {:error, _pairing} -> error(conn, "pairing_failed")
    end
  end

  defp pair(conn), do: error(conn, "pairing_failed")

  defp me(%{body_params: body, query_params: query} = conn)
       when map_size(body) == 0 and map_size(query) == 0 do
    with {:ok, agent, conn} <- verify(conn),
         {:ok, paired} <- RegentAgents.check_in_agent(actor: agent) do
      answer(conn, %{data: Map.put(present(paired), :account, account(paired))})
    else
      {:refused, conn} -> conn
      {:error, _not_paired} -> error(conn, "not_paired")
    end
  end

  defp me(conn), do: error(conn, "not_paired")

  defp harness(value) do
    case Harness.match(value) do
      {:ok, harness} -> {:ok, harness}
      :error -> {:error, :harness_unknown}
    end
  end

  # A request without a body, like a check-in, is signed without one.
  defp verify(conn) do
    conn =
      case conn.assigns do
        %{raw_body: ""} -> %{conn | assigns: Map.delete(conn.assigns, :raw_body)}
        _assigns -> conn
      end

    conn =
      Siwa.AgentAuthPlug.call(conn,
        client: Broker,
        hooks: __MODULE__.Hooks,
        audience: Broker.audience()
      )

    case conn.assigns do
      %{regent_agent: %Agent{} = agent} -> {:ok, agent, conn}
      %{regent_agent_refusal: refusal} -> {:refused, refuse(conn, refusal)}
    end
  end

  # The SIWA service's own refusal reaches the agent as it was given: the SIWA
  # service writes the message and next steps for this site and the agent's
  # signing tool.
  defp refuse(conn, %{
         siwa_status: status,
         siwa_code: code,
         siwa_message: message,
         siwa_hint: hint
       })
       when status in 400..599 do
    conn
    |> put_status(status)
    |> answer(%{error: %{code: code, message: message, hint: hint}})
  end

  defp refuse(conn, %{siwa_status: status}) when status >= 500,
    do: error(conn, "verification_unavailable")

  defp refuse(conn, %{transport_error: _reason}), do: error(conn, "verification_unavailable")

  defp refuse(conn, _refusal), do: error(conn, "verification_failed")

  defp present(agent) do
    %{
      name: agent.name,
      harness: agent.harness,
      wallet: agent.wallet,
      paired_at: DateTime.to_iso8601(agent.paired_at),
      last_contact_at: DateTime.to_iso8601(agent.last_contact_at)
    }
  end

  defp account(agent) do
    {module, function} = Application.fetch_env!(:regent_agents, :account)
    apply(module, function, [agent.privy_user_id])
  end

  defp error(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> answer(%{error: %{code: code, message: message, hint: hint}})
  end

  defp answer(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode_to_iodata!(body))
    |> halt()
  end

  defmodule Hooks do
    @moduledoc false
    @behaviour Siwa.AgentAuthPlug.Hooks

    @base_chain_id 8453

    @impl true
    def before_verify(_conn, _headers), do: {:ok, nil}

    # An agent signs in with a key it made itself; the key's address is who it
    # is, on Base, for this site only.
    @impl true
    def accept(conn, data, _context) do
      audience = RegentAgents.Broker.audience()

      case data do
        %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => "0x" <> _hex = wallet,
            "chain_id" => @base_chain_id,
            "audience" => ^audience
          }
        } ->
          wallet = String.downcase(wallet)

          if Regex.match?(~r/\A0x[0-9a-f]{40}\z/, wallet),
            do: {:ok, Plug.Conn.assign(conn, :regent_agent, %RegentAgents.Agent{wallet: wallet})},
            else: {:error, %{reason: :invalid_principal, source: :regent_agents}}

        _other ->
          {:error, %{reason: :invalid_principal, source: :regent_agents}}
      end
    end

    @impl true
    def deny(conn, refusal), do: Plug.Conn.assign(conn, :regent_agent_refusal, refusal)
  end
end
