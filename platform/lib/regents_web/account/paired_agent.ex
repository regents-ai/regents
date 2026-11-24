defmodule RegentsWeb.Account.PairedAgent do
  @moduledoc "Verify SIWA once, admit only an agent paired with a person who has an account here, and check the pairing again before the answer is sent."
  @behaviour Plug
  import Plug.Conn
  alias RegentAgents.{Authority, Broker}
  alias Regents.Account.Actors.{Agent, Human}

  @not_paired_message "This agent has no current pairing."
  @not_paired_hint "Ask your person to sign in on this site and pair you with Pair New Agent on their Agents page, then send the request again. Help: https://regents.sh/patchbay/errors/agent_not_paired"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    conn =
      Siwa.AgentAuthPlug.call(conn,
        client: Broker,
        hooks: RegentAgents.HTTP.Hooks,
        audience: Broker.audience()
      )

    with %{regent_agent: %RegentAgents.Agent{} = verified} <- conn.assigns,
         {:ok, credential_ref} <- credential_ref(conn) do
      resolve(conn, verified, credential_ref)
    else
      %{regent_agent_refusal: refusal} ->
        refuse_proof(conn, refusal)

      _ ->
        refuse(
          conn,
          401,
          "authentication_required",
          "A signed agent request is required.",
          "Prepare and sign the exact request with your SIWA signer."
        )
    end
  end

  defp resolve(conn, verified, credential_ref) do
    case verified |> agent(credential_ref) |> Agent.with_pairing() do
      {:ok, %Agent{pairing: %Human{}} = actor} ->
        conn
        |> assign(:actor, actor)
        |> register_before_send(&recheck(&1, actor))

      {:ok, %Agent{pairing: :none}} ->
        refuse(conn, 403, "agent_not_paired", @not_paired_message, @not_paired_hint)

      {:ok, %Agent{pairing: :person_not_here}} ->
        refuse(
          conn,
          403,
          "person_not_here",
          "The person this agent is paired with hasn't signed in on this site yet.",
          "Ask your person to sign in on this site once, then send the request again. Help: https://regents.sh/patchbay/errors/person_not_here"
        )

      {:error, _} ->
        refuse(
          conn,
          503,
          "unavailable",
          "The paired account could not be read.",
          "Try again in a moment with fresh proof."
        )
    end
  end

  # The verified request's credential, `sha256:` over its receipt and key id,
  # each sent exactly once. The SIWA plug refuses a repeat on this node; a
  # missing one is refused by the SIWA service, not here, so it is answered
  # here too.
  defp credential_ref(conn) do
    case {get_req_header(conn, Siwa.Contract.header_for("receipt")),
          get_req_header(conn, Siwa.Contract.header_for("key_id"))} do
      {[receipt], [key_id]} ->
        {:ok,
         "sha256:" <>
           Base.encode16(:crypto.hash(:sha256, [receipt, "\n", key_id]), case: :lower)}

      _missing ->
        :error
    end
  end

  # The agent the verified request names: its wallet and what the SIWA service
  # said of it, this site's audience, which the request was verified for, and
  # its credential. The SIWA answer as the shared hook keeps it carries neither
  # the chain, the verification method nor the receipt's end, so those are nil.
  defp agent(%RegentAgents.Agent{} = verified, credential_ref) do
    %Agent{
      wallet_address: verified.wallet,
      chain_id: nil,
      verification_method: nil,
      audience: Broker.audience(),
      credential_ref: credential_ref,
      registry_url: verified.registry_listing,
      human_id: verified.human_id,
      same_person_agent_count: verified.same_person_agent_count
    }
  end

  # The read ran after the pairing was resolved. Before anything is sent, the
  # wallet's current pairing must still be this request's episode and owner;
  # otherwise the answer is replaced, so a revoke or re-pairing during the read
  # never sends the former owner's data.
  defp recheck(conn, %Agent{} = actor) do
    case Authority.resolve(Regents.Repo, actor.wallet_address) do
      {:ok, %{id: id, privy_user_id: owner}}
      when id == actor.pairing_id and owner == actor.privy_user_id ->
        conn

      {:error, reason} when reason != :not_paired and conn.status not in 200..299 ->
        conn

      {:error, reason} when reason != :not_paired ->
        replace(
          conn,
          503,
          "unavailable",
          "The paired account could not be read.",
          "Try again in a moment with fresh proof."
        )

      _changed ->
        replace(conn, 403, "agent_not_paired", @not_paired_message, @not_paired_hint)
    end
  end

  # The refusal carries nothing of the answer it replaces: a download's file
  # name, built from the former owner's title, goes with its body.
  defp replace(conn, status, code, message, hint) do
    %{conn | status: status, resp_body: error_body(code, message, hint)}
    |> delete_resp_header("content-disposition")
    |> put_resp_content_type("application/json")
  end

  defp refuse_proof(conn, %{
         siwa_status: status,
         siwa_code: code,
         siwa_message: message,
         siwa_hint: hint
       })
       when status in 400..599,
       do: refuse(conn, status, code, message, hint)

  defp refuse_proof(conn, %{source: :siwa_plug, reason: reason}),
    do:
      refuse(
        conn,
        401,
        Atom.to_string(reason),
        "The signed request was refused.",
        "Sign the exact method, path and body without query parameters or duplicate proof headers."
      )

  defp refuse_proof(conn, %{reason: :siwa_request_failed}),
    do:
      refuse(
        conn,
        503,
        "siwa_request_failed",
        "The sign-in service could not be reached.",
        "Try again with fresh proof in a moment."
      )

  defp refuse_proof(conn, _),
    do:
      refuse(
        conn,
        401,
        "verification_failed",
        "The signed request could not be verified.",
        "Sign fresh proof with your SIWA signer for audience regents."
      )

  defp refuse(conn, status, code, message, hint) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, error_body(code, message, hint))
    |> halt()
  end

  defp error_body(code, message, hint),
    do: Jason.encode_to_iodata!(%{error: %{code: code, message: message, hint: hint}})
end
