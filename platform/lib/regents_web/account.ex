defmodule RegentsWeb.Account do
  @moduledoc """
  The Account pages, controllers, components, plugs and shell features.
  """
  use Boundary,
    deps: [RegentsWeb, RegentsWeb.Chain, Regents.Products],
    exports: [
      AccountLive,
      AgentPictureController,
      AgentReadsController,
      AgentStart,
      AgentStartLive,
      Identity,
      Names,
      NamesLive,
      OwnedClaimsController,
      Pages,
      PairLive,
      PairedAgent,
      Points,
      PointsEntries,
      PointsLive,
      PrivyPair,
      PrivySessionController,
      ProfileOwner,
      PublicRegentController,
      RegentProfileLive,
      VerifiedConnections
    ]
end
