defmodule Regents.OAuth do
  @moduledoc """
  Consent for connected apps, such as Claude's connector, through the person's
  verified Regents account. The identity permission lets the app keep an
  identity, pair it with this account and check in through the unified MCP
  address at `/mcp`; the agent permission (`agent_scope/0`) lets it then work
  here across Regents, Techtree, Keyfleet, Autolaunch and Patchbay as that
  paired agent, with that agent's rights and nothing more.
  """
  @behaviour RegentOAuth

  alias Regents.Account.Accounts
  alias Regents.Account.Accounts.VerifiedSession
  alias Regents.Account.Actors.System

  @impl true
  def config, do: Application.fetch_env!(:regents, __MODULE__)

  @doc "The permission to work here as the paired agent, beside the identity one."
  def agent_scope, do: "regents.agent"

  @impl true
  def repo, do: Regents.Repo

  @doc """
  Whether connected apps are switched on (`REGENTS_CLAUDE_CONNECTOR_ENABLED`,
  read once at boot; always false on the read-only venue).
  """
  def enabled?, do: not Regents.read_only?() and Keyword.fetch!(config(), :enabled?)

  @impl true
  def current_subject(conn) do
    case conn.assigns[:current_human_account] do
      %{privy_user_id: subject} = account ->
        if VerifiedSession.current?(account), do: subject

      _ ->
        nil
    end
  end

  @impl true
  def active_subject?(subject) do
    case Accounts.get_by_privy_did(subject, actor: %System{}) do
      {:ok, account} when not is_nil(account) -> VerifiedSession.current?(account)
      {:ok, nil} -> false
      {:error, error} -> raise error
    end
  end
end
