defmodule AshPlatformWeb.PrivySessionController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Privy

  def csrf(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> put_session("_csrf_token", Plug.CSRFProtection.dump_state())
    |> json(%{csrf_token: token})
  end

  def create(conn, _untrusted_params) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, verified} <- verifier().verify_access_token(token),
         {:ok, account} <- VerifiedSession.establish(verified) do
      conn
      |> configure_session(renew: true)
      |> clear_session()
      |> put_session(:human_account_id, account.id)
      |> json(session_payload(account))
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  def show(conn, _params) do
    account = conn |> get_session(:human_account_id) |> current_account()
    json(conn, session_payload(account))
  end

  defp verifier, do: Application.get_env(:ash_platform, :privy_verifier, Privy)

  defp current_account(id) when is_integer(id) do
    case AshPlatform.Accounts.get_human_account(id,
           actor: %AshPlatform.Actors.Human{human_account_id: id}
         ) do
      {:ok, account} -> account
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
    control =
      account |> AshPlatform.AccessContext.human() |> AshPlatform.AccessContext.account_control()

    %{authenticated: true, account_control: Map.from_struct(control)}
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> clear_session()
    |> json(%{ok: true})
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
