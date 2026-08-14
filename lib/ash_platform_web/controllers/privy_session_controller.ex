defmodule AshPlatformWeb.PrivySessionController do
  use AshPlatformWeb, :controller

  alias AshPlatform.{AccessContext, Formation}
  alias AshPlatform.Accounts.{SessionAuthority, VerifiedSession}
  alias AshPlatform.Actors.Human
  alias AshPlatform.Privy

  @doc """
  The browser-session state matrix.

  A browser with no claim is bootstrapped onto a fresh unbound lineage; an exact
  claim is only observed; a superseded or unrecoverable one is told which of the
  two it is instead of being silently reset.
  """
  def csrf(conn, _params) do
    case SessionAuthority.renew(claim(conn)) do
      {:bootstrap, claim} -> conn |> rotate_session(claim) |> issue_token()
      {:current, _claim} -> conn |> put_csrf_state() |> issue_token()
      {:error, :superseded} -> lifecycle_error(conn, "session_superseded")
      {:error, :reset} -> conn |> drop_session() |> lifecycle_error("session_reset_required")
    end
  end

  def create(conn, _untrusted_params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, verified} <- verifier().verify_access_token(token),
         {:ok, account, identity_conflicts} <- VerifiedSession.establish(verified) do
      bind(conn, account, identity_conflicts)
    else
      _unverified -> conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  def show(conn, _params), do: json(conn, session_payload(conn.assigns.current_human_account))

  def delete(conn, _params) do
    topic = SessionAuthority.revoke(claim(conn))

    %Plug.Conn{state: :sent} = conn = conn |> drop_session() |> json(%{ok: true})

    broadcast_disconnect(topic)
    conn
  end

  @doc """
  The one place a request turns a cookie into an account.

  The cookie names no account, so identity comes from the locked row and only
  after the claim is exactly current. Anything else — missing, malformed,
  superseded, revoked or absent authority, or an account whose verified evidence
  has lapsed — leaves the request anonymous.
  """
  def enforce_authority(conn) do
    {lineage, account} = conn |> claim() |> SessionAuthority.resolve()

    conn |> assign(:current_lineage, lineage) |> assign(:current_human_account, account)
  end

  # Privy is verified before the row lock, so only the transition itself is
  # serialized. A different account is a two-step cutover: this response revokes
  # and disconnects the old lineage and binds nothing.
  defp bind(conn, account, identity_conflicts) do
    case SessionAuthority.sign_in(claim(conn), account.id) do
      {:ok, transition, claim} ->
        conn
        |> rotate_session(claim)
        |> put_identity_conflict_header(identity_conflicts)
        |> put_resp_header("x-ash-session-changed", to_string(transition == :bind))
        |> json(session_payload(account))

      {:switch, topic} ->
        conn = conn |> drop_session() |> lifecycle_error("account_switch_required")
        broadcast_disconnect(topic)
        conn

      {:error, :superseded} ->
        lifecycle_error(conn, "session_superseded")

      {:error, :reset} ->
        conn |> drop_session() |> lifecycle_error("session_reset_required")
    end
  end

  defp claim(conn), do: conn |> get_session() |> SessionAuthority.claim()

  defp rotate_session(conn, claim) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_claim(claim)
    |> put_csrf_state()
  end

  defp put_claim(conn, claim) do
    claim
    |> SessionAuthority.session()
    |> Enum.reduce(conn, fn {key, value}, conn -> put_session(conn, key, value) end)
  end

  defp put_csrf_state(conn) do
    Plug.CSRFProtection.get_csrf_token()
    put_session(conn, "_csrf_token", Plug.CSRFProtection.dump_state())
  end

  defp issue_token(conn), do: json(conn, %{csrf_token: Plug.CSRFProtection.get_csrf_token()})

  defp lifecycle_error(conn, error), do: conn |> put_status(:conflict) |> json(%{error: error})

  defp drop_session(conn), do: configure_session(conn, drop: true)

  defp verifier, do: Application.get_env(:ash_platform, :privy_verifier, Privy)

  defp session_payload(nil),
    do: %{
      authenticated: false,
      account_control: %{
        kind: :sign_in,
        label: "Sign In",
        profile_path: nil,
        avatar_data_uri: nil
      }
    }

  defp session_payload(account) do
    access_context = AccessContext.human(account)
    control = AccessContext.account_control(access_context, current_regent(account))

    %{authenticated: true, account_control: Map.from_struct(control)}
  end

  defp current_regent(account) do
    case Formation.get_my_regent(actor: %Human{human_account_id: account.id}) do
      {:ok, regent} -> regent
      _no_regent -> nil
    end
  end

  defp broadcast_disconnect(nil), do: :ok

  defp broadcast_disconnect(topic),
    do: AshPlatformWeb.Endpoint.broadcast(topic, "disconnect", %{})

  defp put_identity_conflict_header(conn, []), do: conn

  defp put_identity_conflict_header(conn, _conflicts),
    do: put_resp_header(conn, "x-ash-identity-error", "already-connected")

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case String.trim(token) do
          "" -> {:error, :missing_token}
          token -> {:ok, token}
        end

      _missing ->
        {:error, :missing_token}
    end
  end
end
