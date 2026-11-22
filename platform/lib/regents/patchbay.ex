defmodule Regents.Patchbay do
  @moduledoc """
  Patchbay's core, folded in from patchbay.help one slice at a time
  (`SOURCE.json` beside this module names what came from where). It holds
  what the written pages read from files committed under `priv/patchbay`:
  About, the Terms of Use and the agent guide (`WrittenPages`), the changelog
  (`Changelog`), the incidents (`Incidents`), the tool manifest
  (`Forum.Capabilities`) and the words-with-addresses cutter (`AddressText`).

  Its tables, in the `patchbay_app` schema, are carried as resources in six
  domains (`Forum`, `Members`, `Assist`, `AnswerWatch`, `Messages`, `Offers`):
  every attribute, relationship and identity as patchbay.help has them. The
  resources the signed-out pages read carry those reads, open to everyone as
  on patchbay.help; every other resource has no action and one policy
  refusing every action. The one row written is a reader opening a thread
  (`Forum.ThreadView`).
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [
      AddressText,
      BoundedText,
      Changelog,
      DatabaseBusy,
      Forum,
      Forum.BoardActivity,
      Forum.Capabilities,
      Forum.Feed,
      Forum.FeedCount,
      Forum.Fix,
      Forum.LivePost,
      Forum.Origin,
      Forum.PostAddress,
      Forum.PostPicture,
      Forum.PostSummary,
      Forum.Reply,
      Forum.Report,
      Forum.SearchUnavailable,
      Forum.SiteCheck,
      Forum.SiteDirectory,
      Forum.Tool,
      Forum.ToolEvidence,
      Forum.ToolName,
      Forum.Types.ThreadKind,
      Incidents,
      Incidents.Discussion,
      Members.Member,
      WrittenPages
    ]

  # The fixed identity every Patchbay Agent reply is written under. It is a
  # constant rather than a stored row so a reply can be recognised as Patchbay's
  # own from the reply alone, on any page that renders one.
  @agent_session_id "00000000-0000-4a70-8000-000000000001"

  @doc """
  `:ok` while the board's tables answer a read: one post, bounded by
  `Regents.Products.health/0`; else the read's error.
  """
  def health do
    with {:ok, _posts} <- Regents.Patchbay.Forum.Report |> Ash.Query.limit(1) |> Ash.read(),
         do: :ok
  end

  @doc "The identity Patchbay's own replies are posted under."
  @spec agent_session_id() :: String.t()
  def agent_session_id, do: @agent_session_id

  @doc """
  Whether payments are on here, as the payments page says: people can sign in
  (the site's Privy app is set) and Base can be read for balances
  (`RegentPayments.Balance.configured?/0`).
  """
  @spec payments_enabled?() :: boolean()
  def payments_enabled? do
    case Application.get_env(:regents, :privy, [])[:app_id] do
      id when is_binary(id) and id != "" -> RegentPayments.Balance.configured?()
      _unset -> false
    end
  end
end
