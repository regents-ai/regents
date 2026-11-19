defmodule RegentAgents.HTTP do
  @moduledoc """
  The requests an agent signs with its SIWA key, the same on every site:
  `GET /whoami` tells the agent its status on this site, what it may do in it and
  its next step; `POST /pair` joins a person's account with the code they gave
  it; and `GET /me` checks in and answers with the pairing. The pair and
  check-in answers carry the page of the agent's listing in the agent registry,
  or null, whether a person verified with World ID stands behind the agent, and
  how many agents that same person stands behind, or null when none does, as
  this request saved them.

  Mount it with `forward "/api/agents/v1", RegentAgents.HTTP` behind the site's
  own rate limit and a body reader that keeps the raw body in
  `conn.assigns.raw_body`, since the agent signs the exact bytes. The SIWA
  service verifies every request for this site's audience; when it refuses
  one, the agent gets its status, code, message and hint back unchanged.

  An agent has one of three statuses on a site: `not_paired` (paired to nobody),
  `person_not_here` (paired, but its person has never signed in on this site)
  and `paired` (it acts for its person). The site names what each status may do
  in `config :regent_agents, allowed: %{"not_paired" => [...],
  "person_not_here" => [...], "paired" => [...]}`, short plain sentences that
  `whoami` answers as they are.

  A check-in names the person's account as the site's own pages name it, from
  the site's `config :regent_agents, account: {Module, :function}`, called with
  the person's Privy user ID and returning a JSON-ready map, or nil until the
  person first signs in on this site. Until then the agent's status is
  `person_not_here` and a check-in is refused with that code; an agent paired to
  nobody is refused with `agent_not_paired`.

  `POST /pairing` is the SIWA service's question, before it gives an agent a
  hello card naming this site (`RegentAgents.HelloCard`): is the agent
  `{"subject": "eip155:<chain id>:<address>"}` paired here? No agent signs it;
  the service's token in `authorization: Bearer <token>` proves the caller, for
  this site's origin and that subject (`RegentAgents.HelloCard.verify_service_token/2`),
  or the answer is `service_token_invalid` (401). The answer is exactly
  `{"name", "person", "pairedAt"}` (200): the agent's name, its person's profile
  code (the id of their shared Regent profile, never the Privy user ID, an
  email, a wallet or a name), from the site's
  `config :regent_agents, person: {Module, :function}`, called with the
  person's Privy user ID, and when it paired, in ISO 8601 UTC. An agent with no
  pairing is `not_paired_here` (404); a paired agent whose person has no profile
  code yet (the function gives nil) is `person_has_no_profile` (409).

  Every agent request this module verifies also carries the hello card in its
  `x-siwa-hello-card` header, when one passes, as `conn.assigns.hello_card`
  (`RegentAgents.HelloCard.put_card/2`).
  """

  @behaviour Plug

  import Plug.Conn

  alias RegentAgents.{Agent, Broker, Harness, HelloCard, HumanBacking, Refusal}
  alias RegentAgents.PairedAgent.AgentLimit

  @sign_in_hint "Sign the request with your agent key as https://siwa.regents.sh/skill.md describes, then send it again."

  # The refusals made here: a code for programs, a message and a hint for people.
  # `RegentAgents.Refusal` words a request whose signature was refused. An unknown
  # harness is refused by `error/2`'s own clause, which names the harnesses this site offers.
  @errors %{
    "invalid_name" =>
      {400, "That name can't be used.",
       "Send a name of 1 to 80 characters with no hidden characters: no control, line-break, text-direction or zero-width characters, except a zero-width joiner between two visible characters, as in an emoji. The same code works until it expires."},
    "pairing_failed" =>
      {400, "The pairing code could not be used.",
       "Ask your person for a new code from Pair New Agent on their Agents page on this site. Each code works once and expires ten minutes after it was made."},
    "agent_limit" =>
      {409, "This account already has 100 paired agents.",
       "Ask your person to unpair an agent on their Agents page on this site, then pair again. The same code works until it expires."},
    "agent_not_paired" =>
      {403, "This agent is not paired with an account.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page, then check in again. Help: https://patchbay.help/errors/agent_not_paired"},
    "person_not_here" =>
      {403, "The person this agent is paired with hasn't signed in on this site yet.",
       "Ask your person to sign in on this site once, then check in again. Help: https://patchbay.help/errors/person_not_here"},
    "service_token_invalid" =>
      {401, "The SIWA service token could not be verified.",
       "Only the SIWA service asks this, with a token it signed for this site in the last minute."},
    "not_paired_here" =>
      {404, "This agent is not paired with a person on this site.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page."},
    "person_has_no_profile" =>
      {409, "The person this agent is paired with has no Regent profile yet.",
       "Ask your person to sign in on this site once, then ask for a hello card again."},
    "not_found" =>
      {404, "There is no such agent request.",
       "Agents see their status with GET /api/agents/v1/whoami, pair with POST /api/agents/v1/pair and check in with GET /api/agents/v1/me."}
  }

  @next_steps %{
    "not_paired" =>
      "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page.",
    "person_not_here" => "Ask your person to sign in on this site once.",
    "paired" => nil
  }

  @doc """
  What an agent in `status` does next, one sentence, the same on every site, or
  nil when it acts for its person. A site's agent guides quote it.
  """
  def next_step(status), do: Map.fetch!(@next_steps, status)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "POST", path_info: ["pair"]} = conn, _opts), do: pair(conn)
  def call(%Plug.Conn{method: "GET", path_info: ["me"]} = conn, _opts), do: me(conn)
  def call(%Plug.Conn{method: "GET", path_info: ["whoami"]} = conn, _opts), do: whoami(conn)
  def call(%Plug.Conn{method: "POST", path_info: ["pairing"]} = conn, _opts), do: pairing(conn)
  def call(conn, _opts), do: error(conn, "not_found")

  defp pair(
         %{body_params: %{"code" => code, "name" => name, "harness" => harness} = params} = conn
       )
       when map_size(params) == 3 and is_binary(code) and is_binary(name) and is_binary(harness) do
    with {:ok, harness} <- harness(harness),
         {:ok, agent, conn} <- verify(conn),
         {:ok, paired} <- RegentAgents.pair_agent(code, name, harness, actor: agent) do
      conn |> put_status(:created) |> answer(%{data: present(paired, agent)})
    else
      {:error, :harness_unknown} -> error(conn, "harness_unknown")
      {:error, %Ash.Error.Invalid{errors: [%AgentLimit{}]}} -> error(conn, "agent_limit")
      {:refused, conn} -> conn
      {:error, error} -> error(conn, pair_refusal(error))
    end
  end

  defp pair(conn), do: error(conn, "pairing_failed")

  defp pair_refusal(%Ash.Error.Invalid{errors: errors}) do
    if Enum.any?(errors, &match?(%{field: :name}, &1)),
      do: "invalid_name",
      else: "pairing_failed"
  end

  defp pair_refusal(_error), do: "pairing_failed"

  # The proof is checked first; the shared plug refuses a query string. The
  # account is looked up before contact is recorded, so a refused check-in
  # leaves the agent's last contact as it was.
  defp me(conn) do
    with {:ok, agent, conn} <- verify(conn),
         {:ok, %{privy_user_id: privy_user_id}} <- RegentAgents.current_pairing(actor: agent),
         %{} = account <- account(privy_user_id),
         {:ok, paired} <- RegentAgents.check_in_agent(privy_user_id, actor: agent) do
      answer(conn, %{data: Map.put(present(paired, agent), :account, account)})
    else
      {:refused, conn} -> conn
      {:ok, nil} -> error(conn, "agent_not_paired")
      nil -> error(conn, "person_not_here")
      {:error, _no_longer_paired} -> error(conn, "agent_not_paired")
    end
  end

  # This probe verifies the proof once and never performs a check-in or awards Points.
  defp whoami(conn) do
    with {:ok, agent, conn} <- verify(conn),
         {:ok, pairing} <- RegentAgents.current_pairing(actor: agent) do
      status = status(pairing)

      answer(conn, %{
        data: %{
          agent: %{wallet: agent.wallet, registry_listing: agent.registry_listing},
          audience: Broker.audience(),
          authenticated: true,
          pairing: if(pairing, do: %{id: pairing.id, paired_at: pairing.paired_at}, else: nil),
          status: status,
          allowed: Map.fetch!(Application.fetch_env!(:regent_agents, :allowed), status),
          next_step: next_step(status)
        }
      })
    else
      {:refused, conn} -> conn
      {:error, _error} -> refuse(conn, %{reason: :siwa_request_failed})
    end
  end

  # The SIWA service's token names the subject, and the body names exactly the
  # same one. The service vouches for the agent it names, which reads its own
  # pairing as itself.
  defp pairing(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, subject} <- HelloCard.verify_service_token(token, DateTime.utc_now()),
         %{"subject" => ^subject} = body when map_size(body) == 1 <- conn.body_params do
      paired_here(conn, subject)
    else
      _refused -> error(conn, "service_token_invalid")
    end
  end

  defp paired_here(conn, "eip155:8453:" <> wallet) do
    with {:ok, %{privy_user_id: privy_user_id} = pairing} <-
           RegentAgents.current_pairing(actor: %Agent{wallet: wallet}),
         person when is_binary(person) <- person(privy_user_id) do
      answer(conn, %{
        "name" => pairing.name,
        "person" => person,
        "pairedAt" => pairing.paired_at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      })
    else
      {:ok, nil} -> error(conn, "not_paired_here")
      nil -> error(conn, "person_has_no_profile")
    end
  end

  # Agents sign in on Base only, so an agent on another chain is paired nowhere here.
  defp paired_here(conn, _other_chain), do: error(conn, "not_paired_here")

  defp person(privy_user_id) do
    {module, function} = Application.fetch_env!(:regent_agents, :person)
    apply(module, function, [privy_user_id])
  end

  defp status(nil), do: "not_paired"

  defp status(%{privy_user_id: privy_user_id}) do
    if account(privy_user_id), do: "paired", else: "person_not_here"
  end

  defp harness(value) do
    with {:ok, harness} <- Harness.match(value),
         true <- harness in Harness.offered() do
      {:ok, harness}
    else
      _not_offered -> {:error, :harness_unknown}
    end
  end

  defp verify(conn) do
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

  defp refuse(conn, refusal) do
    {status, error} = Refusal.describe(refusal, @sign_in_hint)
    conn |> put_status(status) |> answer(%{error: error})
  end

  defp present(paired, agent) do
    %{
      id: paired.id,
      name: paired.name,
      harness: paired.harness,
      wallet: paired.wallet,
      paired_at: DateTime.to_iso8601(paired.paired_at),
      last_contact_at: DateTime.to_iso8601(paired.last_contact_at),
      registry_listing: agent.registry_listing
    }
    |> Map.merge(HumanBacking.describe(paired))
  end

  defp account(privy_user_id) do
    {module, function} = Application.fetch_env!(:regent_agents, :account)
    apply(module, function, [privy_user_id])
  end

  defp error(conn, "harness_unknown") do
    harnesses = Enum.map_join(Harness.offered(), ", ", &Atom.to_string/1)

    refusal(
      conn,
      {400, "harness_unknown", "That harness is not one we know.",
       "Send one of: #{harnesses}. Send other if yours is not listed."}
    )
  end

  defp error(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    refusal(conn, {status, code, message, hint})
  end

  defp refusal(conn, {status, code, message, hint}) do
    conn |> put_status(status) |> answer(%{error: %{code: code, message: message, hint: hint}})
  end

  defp answer(conn, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(conn.status || 200, Jason.encode_to_iodata!(body))
    |> halt()
  end

  defmodule Hooks do
    @moduledoc false
    @behaviour Siwa.AgentAuthPlug.Hooks

    alias RegentAgents.{Agent, HumanBacking}

    @base_chain_id 8453

    @impl true
    def before_verify(_conn, _headers), do: {:ok, nil}

    # An agent signs in with a key it made itself; the key's address is who it
    # is, on Base, for this site only. The SIWA service also names the page of
    # its listing in the agent registry, or null when it has none, and the World
    # ID person behind it with their agent count, or null; the agent's pairing
    # saves both.
    @impl true
    def accept(conn, data, _context) do
      audience = RegentAgents.Broker.audience()

      with %{
             "verified" => true,
             "principal" => %{
               "kind" => "wallet",
               "wallet_address" => "0x" <> _hex = wallet,
               "chain_id" => @base_chain_id,
               "audience" => ^audience
             },
             "agentRegistration" => registration,
             "agentBook" => book
           } <- data,
           wallet = String.downcase(wallet),
           true <- Regex.match?(~r/\A0x[0-9a-f]{40}\z/, wallet),
           {:ok, listing} <- registry_listing(registration),
           {:ok, backing} <- HumanBacking.read(book) do
        agent = struct!(Agent, Map.merge(backing, %{wallet: wallet, registry_listing: listing}))

        {:ok,
         conn
         |> Plug.Conn.assign(:regent_agent, agent)
         |> RegentAgents.HelloCard.put_card(wallet)}
      else
        _other -> {:error, %{reason: :invalid_principal, source: :regent_agents}}
      end
    end

    defp registry_listing(nil), do: {:ok, nil}
    defp registry_listing(%{"registryUrl" => "https://" <> _rest = url}), do: {:ok, url}
    defp registry_listing(_other), do: :error

    @impl true
    def deny(conn, refusal), do: Plug.Conn.assign(conn, :regent_agent_refusal, refusal)
  end
end
