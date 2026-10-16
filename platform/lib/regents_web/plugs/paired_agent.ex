defmodule RegentsWeb.Plugs.PairedAgent do
  @moduledoc "Verify SIWA once, resolve the current pairing and local beneficiary, and check the pairing again before the answer is sent."
  @behaviour Plug
  import Plug.Conn
  alias RegentAgents.{Authority, Broker}
  alias Regents.Actors.{Agent, System}

  @not_paired_message "This agent has no current pairing."
  @not_paired_hint "Ask your person to sign in on this site and pair you with Pair New Agent in the side panel, then send the request again."

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    conn =
      if conn.assigns[:raw_body] == "",
        do: %{conn | assigns: Map.delete(conn.assigns, :raw_body)},
        else: conn

    conn =
      Siwa.AgentAuthPlug.call(conn,
        client: Broker,
        hooks: RegentAgents.HTTP.Hooks,
        audience: Broker.audience()
      )

    case conn.assigns do
      %{regent_agent: %RegentAgents.Agent{wallet: wallet}} ->
        if conn.method == "GET" and is_binary(conn.assigns[:raw_body]) do
          refuse(
            conn,
            400,
            "invalid_input",
            "This read accepts no request body.",
            "Sign the GET request without a body or query string."
          )
        else
          resolve(conn, wallet)
        end

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

  defp resolve(conn, wallet) do
    with {:ok, pairing} <- Authority.resolve(Regents.Repo, wallet),
         {:ok, account} when not is_nil(account) <-
           Regents.Accounts.get_by_privy_did(pairing.privy_user_id, actor: %System{}) do
      actor = Agent.paired(wallet, pairing, account)

      conn
      |> assign(:actor, actor)
      |> register_before_send(&recheck(&1, actor))
    else
      {:error, :not_paired} ->
        refuse(conn, 403, "agent_not_paired", @not_paired_message, @not_paired_hint)

      {:ok, nil} ->
        refuse(
          conn,
          403,
          "person_not_here",
          "The person this agent is paired with hasn't signed in on this site yet.",
          "Ask your person to sign in on this site once, then send the request again."
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

  defp replace(conn, status, code, message, hint) do
    %{conn | status: status, resp_body: error_body(code, message, hint)}
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
