defmodule Regents.OAuth do
  @moduledoc """
  Consent for connected apps, such as Claude's connector, through the person's
  verified account. The identity permission lets the app keep an identity, pair
  it with this account and check in through the MCP address at `/mcp`; the
  agent permission (`agent_scope/0`) lets it then work here as that paired
  agent, with that agent's rights and nothing more.
  """
  @behaviour RegentOAuth

  def config, do: Application.fetch_env!(:regents, __MODULE__)

  @doc "The permission to work here as the paired agent, beside the identity one."
  def agent_scope, do: "regents.agent"
  def repo, do: Regents.Repo

  @doc """
  Whether the Claude connector is switched on (`REGENTS_CLAUDE_CONNECTOR_ENABLED`,
  read once at boot): its sign-in, its MCP address, Claude in the pairing box and
  the Claude guide all follow this one setting.
  """
  def enabled?, do: Keyword.fetch!(config(), :enabled?)

  def current_subject(conn) do
    case conn.assigns[:current_human_account] do
      %{privy_user_id: subject} = account ->
        if Regents.Accounts.VerifiedSession.current?(account), do: subject

      _ ->
        nil
    end
  end

  def active_subject?(subject) do
    case Regents.Accounts.get_by_privy_did(subject, actor: %Regents.Actors.System{}) do
      {:ok, account} -> Regents.Accounts.VerifiedSession.current?(account)
      {:error, error} -> raise error
    end
  end
end
