defmodule AshPlatformWeb.Live.Session do
  @moduledoc false

  alias AshPlatform.{AccessContext, Accounts}
  alias AshPlatform.Actors.Human

  def on_mount(:load_human, _params, session, socket) do
    access_context = load_access_context(session)

    {:cont,
     Phoenix.Component.assign(socket,
       access_context: access_context,
       account_control: AccessContext.account_control(access_context)
     )}
  end

  defp load_access_context(%{"human_account_id" => id}) when is_integer(id) do
    case Accounts.get_human_account(id, actor: %Human{human_account_id: id}) do
      {:ok, account} when not is_nil(account) -> AccessContext.human(account)
      _ -> AccessContext.anonymous()
    end
  end

  defp load_access_context(_session), do: AccessContext.anonymous()
end
