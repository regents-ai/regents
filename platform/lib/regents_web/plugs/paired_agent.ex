defmodule RegentsWeb.Plugs.PairedAgent do
  @moduledoc "Verify SIWA once, then resolve the current pairing and local beneficiary."
  @behaviour Plug
  import Plug.Conn
  alias Regents.Actors.{Agent, System}
  alias RegentAgents.{Authority, Broker}

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
      assign(conn, :actor, Agent.paired(wallet, pairing, account))
    else
      {:error, :not_paired} ->
        refuse(
          conn,
          403,
          "agent_not_paired",
          "This agent has no current pairing.",
          "Ask your owner to sign in at /account and use Agents > Pair an agent, then redeem the code and sign fresh proof."
        )

      {:ok, nil} ->
        refuse(
          conn,
          403,
          "person_not_here",
          "The paired owner has no Regents account yet.",
          "Ask your owner to sign in at /account here, then sign fresh proof."
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
    |> send_resp(
      status,
      Jason.encode_to_iodata!(%{error: %{code: code, message: message, hint: hint}})
    )
    |> halt()
  end
end
