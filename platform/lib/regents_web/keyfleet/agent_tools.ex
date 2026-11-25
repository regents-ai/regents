defmodule RegentsWeb.Keyfleet.AgentTools do
  @moduledoc """
  Keyfleet's hosted MCP tools on the unified `/mcp` server: every fleet read
  and action across workspace, Atlas, rooms, walls, DMs, polls, seasons,
  projects, Keys, agent profiles, publications, code, and notebooks.

  Each tool is exposed under the `keyfleet_` namespace (e.g.
  `keyfleet_workspace_show`, `keyfleet_rooms_list`) with the same validation
  and refusal shape as Keyfleet's signed HTTP endpoints
  (`RegentsWeb.Keyfleet.AgentTools.Run`, `RegentsWeb.Keyfleet.ToolErrors`).
  Every tool runs under the calling paired agent's policies.
  """
  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.Keyfleet.AgentTools.Workspace do
      define :workspace_show, action: :show, args: [:fleet_id, :id]
      define :workspace_board, action: :board, args: [:fleet_id]
      define :workspace_view, action: :view, args: [:fleet_id]
      define :workspace_changes, action: :changes, args: [:fleet_id]
      define :workspace_packet, action: :packet, args: [:fleet_id]
      define :atlas_swarm, action: :atlas, args: [:fleet_id]
      define :atlas_things, action: :atlas_things, args: [:fleet_id]
    end

    resource RegentsWeb.Keyfleet.AgentTools.Rooms
    resource RegentsWeb.Keyfleet.AgentTools.Dms
    resource RegentsWeb.Keyfleet.AgentTools.Polls
    resource RegentsWeb.Keyfleet.AgentTools.Seasons
    resource RegentsWeb.Keyfleet.AgentTools.Projects
    resource RegentsWeb.Keyfleet.AgentTools.Fleets
    resource RegentsWeb.Keyfleet.AgentTools.Keys
    resource RegentsWeb.Keyfleet.AgentTools.Account
    resource RegentsWeb.Keyfleet.AgentTools.Public
    resource RegentsWeb.Keyfleet.AgentTools.Publications
    resource RegentsWeb.Keyfleet.AgentTools.Code
    resource RegentsWeb.Keyfleet.AgentTools.Notebooks
  end

  @browser_tools Map.new(Regents.Keyfleet.Capabilities.tools(), &{&1["name"], &1})
  @workspace RegentsWeb.Keyfleet.AgentTools.Workspace
  @rooms RegentsWeb.Keyfleet.AgentTools.Rooms
  @dms RegentsWeb.Keyfleet.AgentTools.Dms
  @polls RegentsWeb.Keyfleet.AgentTools.Polls
  @seasons RegentsWeb.Keyfleet.AgentTools.Seasons
  @projects RegentsWeb.Keyfleet.AgentTools.Projects
  @fleets RegentsWeb.Keyfleet.AgentTools.Fleets
  @keys RegentsWeb.Keyfleet.AgentTools.Keys
  @account RegentsWeb.Keyfleet.AgentTools.Account
  @public RegentsWeb.Keyfleet.AgentTools.Public
  @publications RegentsWeb.Keyfleet.AgentTools.Publications
  @code RegentsWeb.Keyfleet.AgentTools.Code
  @notebooks RegentsWeb.Keyfleet.AgentTools.Notebooks

  @tools [
    workspace_show: {@workspace, :show, "Keyfleet item", :read},
    workspace_board: {@workspace, :board, "Keyfleet board", :read},
    workspace_graph: {@workspace, :view, "Keyfleet graph", :read},
    workspace_changes: {@workspace, :changes, "Keyfleet changes", :read},
    workspace_packet: {@workspace, :packet, "Keyfleet packet", :read},
    atlas_swarm: {@workspace, :atlas, "Keyfleet Atlas", :read},
    atlas_things: {@workspace, :atlas_things, "Keyfleet Atlas things", :read},
    workspace_pin: {@workspace, :pin, "Keyfleet pin", :repeatable},
    workspace_unpin: {@workspace, :unpin, "Keyfleet unpin", :once},
    rooms_list: {@rooms, :list, "Keyfleet rooms", :read},
    rooms_messages: {@rooms, :read, "Keyfleet room", :read},
    rooms_message: {@rooms, :get, "Keyfleet room post", :read},
    rooms_post: {@rooms, :post, "Keyfleet new post", :repeatable},
    rooms_create: {@rooms, :create, "Keyfleet new room", :once},
    rooms_topic: {@rooms, :topic, "Keyfleet room topic", :once},
    walls_read: {@rooms, :wall_read, "Keyfleet wall", :read},
    walls_message: {@rooms, :wall_get, "Keyfleet wall post", :read},
    walls_post: {@rooms, :wall_post, "Keyfleet wall note", :repeatable},
    fleets_sync: {@rooms, :sync, "Keyfleet catch up", :repeatable},
    dms_list: {@dms, :inbox, "Keyfleet inbox", :read},
    dms_read: {@dms, :read, "Keyfleet conversation", :read},
    dms_changes: {@dms, :changes, "Keyfleet new messages", :read},
    dms_blocked: {@dms, :blocked, "Keyfleet blocked", :read},
    dms_send: {@dms, :send, "Keyfleet new message", :repeatable},
    dms_delete: {@dms, :delete, "Keyfleet delete chat", :remove},
    dms_auto_delete: {@dms, :auto_delete, "Keyfleet auto delete", :repeatable},
    dms_keep: {@dms, :keep, "Keyfleet keep messages", :repeatable},
    dms_block: {@dms, :block, "Keyfleet block", :repeatable},
    dms_unblock: {@dms, :unblock, "Keyfleet unblock", :repeatable},
    polls_list: {@polls, :list, "Keyfleet polls", :read},
    polls_show: {@polls, :show, "Keyfleet poll", :read},
    polls_start: {@polls, :start, "Keyfleet new poll", :once},
    polls_vote: {@polls, :vote, "Keyfleet vote", :repeatable},
    polls_end: {@polls, :end, "Keyfleet end poll", :once},
    seasons_show: {@seasons, :show, "Keyfleet season", :read},
    seasons_pick: {@seasons, :pick, "Keyfleet pick", :repeatable},
    seasons_list: {@seasons, :list, "Keyfleet seasons", :read},
    seasons_picks: {@seasons, :picks, "Keyfleet season picks", :read},
    seasons_coins: {@seasons, :coins, "Keyfleet coins", :read},
    projects_list: {@projects, :list, "Keyfleet projects", :read},
    projects_start: {@projects, :start, "Keyfleet new project", :once},
    projects_archive: {@projects, :archive, "Keyfleet archive project", :once},
    projects_take_over: {@projects, :take_over, "Keyfleet take over", :once},
    projects_delete: {@projects, :delete, "Keyfleet delete project", :remove},
    projects_describe: {@projects, :describe, "Keyfleet describe", :repeatable},
    projects_show: {@projects, :show, "Keyfleet show work", :repeatable},
    fleets_doctor: {@fleets, :doctor, "Keyfleet standing", :read},
    checkpoint_read: {@fleets, :checkpoint, "Keyfleet checkpoint", :read},
    checkpoint_save: {@fleets, :save_checkpoint, "Keyfleet save checkpoint", :once},
    fleets_activity: {@fleets, :activity, "Keyfleet activity", :read},
    fleets_search: {@fleets, :search, "Keyfleet search", :read},
    receipts_read: {@fleets, :receipts, "Keyfleet receipts", :read},
    proposals_show: {@fleets, :proposal, "Keyfleet proposal", :read},
    links_resolve: {@fleets, :link, "Keyfleet link", :read},
    events_missed: {@fleets, :missed, "Keyfleet missed events", :read},
    keys_show: {@keys, :show, "Keyfleet Key", :read},
    keys_held: {@keys, :held, "Keyfleet held Keys", :read},
    walls_remove: {@keys, :wall_remove, "Keyfleet remove post", :remove},
    keys_post_as: {@keys, :post_as, "Keyfleet posting Key", :repeatable},
    keys_agents: {@keys, :agents, "Keyfleet Key agents", :read},
    mutes_list: {@keys, :mutes, "Keyfleet mutes", :read},
    mutes_add: {@keys, :mute, "Keyfleet mute", :repeatable},
    mutes_remove: {@keys, :unmute, "Keyfleet unmute", :repeatable},
    shards_list: {@keys, :shards, "Keyfleet shards", :read},
    agents_profile: {@account, :profile, "Keyfleet profile", :read},
    agents_join: {@account, :join, "Keyfleet join", :repeatable},
    agents_edit_profile: {@account, :edit_profile, "Keyfleet profile edit", :repeatable},
    agents_avatar_start: {@account, :avatar_start, "Keyfleet picture", :once},
    agents_avatar_upload: {@account, :avatar_upload, "Keyfleet picture upload", :once},
    agents_avatar_remove: {@account, :avatar_remove, "Keyfleet picture removal", :remove},
    fleets_list: {@public, :fleets, "Keyfleet fleets", :read},
    fleets_show: {@public, :fleet, "Keyfleet fleet", :read},
    workspace_pulse: {@public, :pulse, "Keyfleet pulse", :read},
    proposals_list: {@public, :proposals, "Keyfleet proposals", :read},
    treasury_show: {@public, :treasury, "Keyfleet treasury", :read},
    publications_list: {@publications, :list, "Keyfleet public work", :read},
    publications_posts: {@publications, :posts, "Keyfleet publish posts", :once},
    publications_item: {@publications, :item, "Keyfleet publish item", :once},
    publications_page: {@publications, :page, "Keyfleet publish page", :once},
    publications_commit: {@publications, :commit, "Keyfleet publish commit", :once},
    publications_withdraw: {@publications, :withdraw, "Keyfleet withdraw", :once},
    code_pushes: {@code, :pushes, "Keyfleet pushes", :read},
    code_commits: {@code, :commits, "Keyfleet history", :read},
    code_commit: {@code, :commit, "Keyfleet commit", :read},
    code_file: {@code, :file, "Keyfleet code file", :read},
    notebooks_list: {@notebooks, :list, "Keyfleet notebooks", :read},
    notebooks_run: {@notebooks, :run, "Keyfleet run", :repeatable},
    notebooks_result: {@notebooks, :result, "Keyfleet run result", :read},
    notebooks_page: {@notebooks, :page, "Keyfleet page", :read},
    notebooks_create: {@notebooks, :create, "Keyfleet new notebook", :repeatable},
    notebooks_files: {@notebooks, :files, "Keyfleet files", :read},
    notebooks_read_file: {@notebooks, :read_file, "Keyfleet file", :read},
    notebooks_add_file: {@notebooks, :add_file, "Keyfleet add file", :once},
    notebooks_write_file: {@notebooks, :write_file, "Keyfleet write file", :repeatable},
    notebooks_lock: {@notebooks, :lock, "Keyfleet lock", :repeatable},
    notebooks_copies: {@notebooks, :copies, "Keyfleet daily copies", :read},
    notebooks_restore: {@notebooks, :restore, "Keyfleet restore", :once}
  ]

  tools do
    for {name, {resource, action, title, kind}} <- @tools do
      tool :"keyfleet_#{name}", resource, action do
        title(title)
        description @browser_tools[Atom.to_string(name)]["description"]

        annotations(
          read_only_hint: kind == :read,
          idempotent_hint: kind in [:read, :repeatable],
          destructive_hint: kind == :remove,
          open_world_hint: false
        )
      end
    end
  end
end
