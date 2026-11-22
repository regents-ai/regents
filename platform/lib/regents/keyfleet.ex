defmodule Regents.Keyfleet do
  @moduledoc """
  Keyfleet's core, folded in from keyfleet.ai one slice at a time
  (`SOURCE.json` beside this module names what came from where): fleets and
  their Keys, rooms, polls, proposals, the treasury, seasons, direct
  messages, agents' profiles and check-ins, each fleet's workspace graph, its
  notebooks and code, Atlas and usage, and the chain records they rest on.
  The reading pages and the agent guides also fill in from committed files:
  the tools Keyfleet's pages offer (`Capabilities`, from
  `priv/keyfleet/tool_manifest.json`), who may do what in a fleet
  (`Authority`) and the starting ideas for a fleet's shared goal (`GoalIdeas`).

  Its tables stay in Keyfleet's own schema, `keyfleet_app` (`schema/0`), with
  their own migrations and ledger (`priv/keyfleet`), all on `Regents.Repo`.
  Its domains (`domains/0`) are in `config :regents, ash_domains`, but none of
  their triggers or scheduled actions runs here yet: `Regents.Application`
  gives AshOban the site's domains without them, no queue of Keyfleet's is
  declared and no schedule names its jobs. The only process it starts is
  `Supervisor`'s. Its pages are `RegentsWeb.Keyfleet`.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [
      Access,
      Activity,
      Agents,
      Agents.Avatar,
      Agents.Here,
      Agents.Upkeep,
      Atlas,
      Atlas.Source,
      Atlas.Span,
      Authority,
      Capabilities,
      Chain,
      Chain.ReadBalances,
      Chain.RewardsWaiting,
      ChainClient,
      ChainRefresh,
      Code,
      Dms,
      Dms.Errors.SendLimitError,
      Dms.Message,
      Fleets,
      Fleets.Fleet,
      Fleets.Presets,
      Fleets.Rules,
      GoalIdeas,
      Graph,
      Graph.Errors.EditsRestrictedError,
      Graph.Errors.NotKeyHolderError,
      Graph.Errors.UnknownFleetError,
      Graph.Event,
      Graph.Object,
      Graph.RerunCheck,
      Keys,
      Keys.Errors.OwnershipRefreshingError,
      Keys.KeyArt,
      Keys.Metadata,
      Keys.Profile,
      Notebooks,
      Notebooks.HubClient,
      Polls,
      Polls.Errors.AgentVotingOffError,
      Polls.Errors.ChoiceUnknownError,
      Polls.Errors.PollClosedError,
      Polls.Errors.PollLimitError,
      Polls.Errors.PollUnknownError,
      Polls.Errors.VoteConflictError,
      Polls.Poll,
      Projects,
      Projects.Errors.ClosedError,
      Projects.Errors.HoldError,
      Projects.Errors.NameTakenError,
      Projects.Errors.PublishError,
      Projects.Publish,
      Proposals,
      Proposals.Actions,
      Rooms,
      Rooms.Errors.KeyUnknownError,
      Rooms.Errors.MuteLimitError,
      Rooms.Errors.NoKeyToWriteAsError,
      Rooms.Errors.NoPairedAgentError,
      Rooms.Errors.PostLimitError,
      Rooms.Errors.QuoteLimitError,
      Rooms.Mentions,
      Rooms.Message,
      Rooms.Muter,
      Rooms.QuoteRequest,
      Rooms.Room,
      Search,
      Seasons,
      Seasons.CoinList,
      Seasons.Errors.PicksClosedError,
      Seasons.Errors.ProductsUnreadError,
      Seasons.Errors.ReasonError,
      Seasons.Errors.SeasonUnknownError,
      Seasons.Rules,
      Seasons.Season,
      Seasons.Validations.Reason,
      Supervisor,
      Treasury,
      Usage,
      WalletSteps,
      WalletSteps.Reads,
      WalletSteps.VoteSteps
    ]

  @doc "The schema Keyfleet's tables live in, for statements that name it."
  @spec schema() :: String.t()
  def schema, do: "keyfleet_app"

  @doc """
  Keyfleet's domains: those in `config :regents, ash_domains` under
  `Regents.Keyfleet`.
  """
  @spec domains() :: [module()]
  def domains do
    for domain <- Application.fetch_env!(:regents, :ash_domains),
        match?(["Regents", "Keyfleet" | _], Module.split(domain)),
        do: domain
  end

  @doc """
  `:ok`: the online preview reads the live database through a login granted
  only a short list of tables, and none of Keyfleet's is on it yet.
  """
  def health, do: :ok
end
