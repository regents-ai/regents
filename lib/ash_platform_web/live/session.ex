defmodule AshPlatformWeb.Live.Session do
  @moduledoc false

  alias AshPlatform.{AccessContext, Accounts, Formation}
  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Actors.Human

  def on_mount(:load_human, _params, session, socket) do
    access_context = load_access_context(session)
    regent = load_regent(access_context)

    {:cont,
     Phoenix.Component.assign(socket,
       access_context: access_context,
       account_control: AccessContext.account_control(access_context, regent),
       current_regent: regent
     )}
  end

  defp load_access_context(%{"human_account_id" => id}) when is_integer(id) do
    case Accounts.get_human_account(id, actor: %Human{human_account_id: id}) do
      {:ok, account} when not is_nil(account) ->
        if VerifiedSession.current?(account),
          do: AccessContext.human(account),
          else: AccessContext.anonymous()

      _ ->
        AccessContext.anonymous()
    end
  end

  defp load_access_context(_session), do: AccessContext.anonymous()

  defp load_regent(%AccessContext{principal: {:human, account}}) do
    case Formation.get_my_regent(actor: %Human{human_account_id: account.id}) do
      {:ok, regent} -> regent
      _ -> nil
    end
  end

  defp load_regent(_access_context), do: nil
end
