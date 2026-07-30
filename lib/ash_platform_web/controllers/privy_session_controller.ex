defmodule AshPlatformWeb.PrivySessionController do
  use AshPlatformWeb, :controller

  @logout_epoch_cookie "_ash_platform_logout_epoch"
  @logout_epoch_session_key :privy_logout_epoch

  alias AshPlatform.{AccessContext, Formation}
  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Actors.Human
  alias AshPlatform.Privy

  def csrf(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> json(%{csrf_token: token})
  end

  def create(conn, _untrusted_params) do
    conn = fetch_cookies(conn)
    previous_account_id = get_session(conn, :human_account_id)
    logout_epoch = conn.req_cookies[@logout_epoch_cookie]

    with {:ok, token} <- bearer_token(conn),
         {:ok, verified} <- verifier().verify_access_token(token),
         {:ok, account} <- VerifiedSession.establish(verified) do
      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(:human_account_id, account.id)
      |> put_logout_epoch_session(logout_epoch)
      |> put_resp_header(
        "x-ash-session-changed",
        to_string(previous_account_id != account.id)
      )
      |> json(session_payload(account))
    else
      _ -> unauthorized(conn)
    end
  end

  def show(conn, _params) do
    account_id = get_session(conn, :human_account_id)

    case current_account(account_id) do
      nil when is_integer(account_id) ->
        conn
        |> drop_local_session()
        |> json(session_payload(nil))

      account ->
        json(conn, session_payload(account))
    end
  end

  defp verifier, do: Application.get_env(:ash_platform, :privy_verifier, Privy)

  defp current_account(id) when is_integer(id) do
    case AshPlatform.Accounts.get_human_account(id,
           actor: %AshPlatform.Actors.Human{human_account_id: id}
         ) do
      {:ok, account} -> if VerifiedSession.current?(account), do: account
      _ -> nil
    end
  end

  defp current_account(_id), do: nil

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
      _ -> nil
    end
  end

  def delete(conn, _params) do
    conn
    |> drop_local_session()
    |> put_resp_cookie(@logout_epoch_cookie, logout_epoch(), logout_epoch_cookie_options())
    |> json(%{ok: true})
  end

  def enforce_logout_epoch(conn) do
    conn = fetch_cookies(conn)
    account_id = get_session(conn, :human_account_id)
    session_epoch = get_session(conn, @logout_epoch_session_key)
    current_epoch = conn.req_cookies[@logout_epoch_cookie]

    if is_integer(account_id) and session_epoch != current_epoch,
      do: drop_local_session(conn),
      else: conn
  end

  defp unauthorized(conn) do
    conn
    |> drop_local_session()
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end

  defp drop_local_session(conn) do
    conn
    |> configure_session(drop: true)
    |> clear_session()
  end

  defp put_logout_epoch_session(conn, nil), do: conn

  defp put_logout_epoch_session(conn, logout_epoch) do
    put_session(conn, @logout_epoch_session_key, logout_epoch)
  end

  defp logout_epoch do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp logout_epoch_cookie_options do
    session_options = Application.fetch_env!(:ash_platform, :session_options)

    [
      http_only: true,
      same_site: Keyword.fetch!(session_options, :same_site),
      secure: Keyword.fetch!(session_options, :secure)
    ]
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case String.trim(token) do
          "" -> {:error, :missing_token}
          token -> {:ok, token}
        end

      _ ->
        {:error, :missing_token}
    end
  end
end
