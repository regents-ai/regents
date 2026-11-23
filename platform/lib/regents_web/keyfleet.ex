defmodule RegentsWeb.Keyfleet do
  @moduledoc """
  Keyfleet's pages, all under `/keyfleet` in one scope of the router with their
  own live session. The scope marks the page `data-product="keyfleet"`, which
  selects Keyfleet's stylesheets (`assets/css/keyfleet`), and every page is read
  under the site's bar inside Keyfleet's frame: its sidebar and its footer
  (`RegentsWeb.Keyfleet.Components.Shell`), drawn by one live page
  (`RegentsWeb.Keyfleet.ShellLive`) that patches between its pages. The agent
  guides it serves (`/keyfleet/skill.md` and the rest) are answered outside the
  page scope, by `RegentsWeb.Keyfleet.AgentFilesController` and
  `RegentsWeb.Keyfleet.PublicPagesController`, and so are its share pictures
  (`/keyfleet/share/...`), by `RegentsWeb.Keyfleet.ShareCardController`.
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Chain, Regents.Keyfleet],
    exports: [
      AgentActivityController,
      AgentAvatarController,
      AgentChainController,
      AgentCheckpointController,
      AgentCodeController,
      AgentDmController,
      AgentDoctorController,
      AgentFilesController,
      AgentGraphController,
      AgentKeyController,
      AgentLinkController,
      AgentMuteController,
      AgentNotebookController,
      AgentPollController,
      AgentProfileController,
      AgentProjectController,
      AgentProposalController,
      AgentPublicationController,
      AgentReceiptController,
      AgentRoomController,
      AgentSeasonController,
      AgentShardController,
      AgentTools,
      DirectoryController,
      FeedController,
      HarbourSeaLive,
      HomeLive,
      HubJwksController,
      Layouts,
      MetadataController,
      NotebookOpenController,
      Plugs.FleetComingSoon,
      PublicDocuments,
      PublicPagesController,
      PublicProposalsController,
      PublicSeasonsController,
      RouteCatalog,
      ShareCardController,
      ShellLive,
      TreasuryController,
      WorkspacePulseController
    ]
end
