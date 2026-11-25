defmodule RegentsWeb.Keyfleet.Plugs.AgentRequest do
  @moduledoc """
  Validates query strings and JSON request shapes for Keyfleet's signed agent
  routes (`/api/v1/keyfleet/agent/*`, `/api/v1/keyfleet/feed/missed`) after
  SIWA authentication (`RegentsWeb.Account.PairedAgent`).

  Malformed JSON bodies, missing required keys, extra unknown fields, and
  out-of-range numbers are refused cleanly with 422 (`invalid_request` or
  `out_of_range`) instead of raising in controllers or answer modules.
  `check_body/2`, `body_refusal/2`, and `takes/1` are shared with Keyfleet's
  hosted MCP tools (`RegentsWeb.Keyfleet.AgentTools.SignedRequest`).
  """
  @behaviour Plug

  import Plug.Conn

  alias Regents.Keyfleet.Agents.{CheckIn, CheckInStatus}
  alias Regents.Keyfleet.Search
  alias RegentsWeb.Keyfleet.{MentionJSON, Refusal}

  @join_path "/api/v1/keyfleet/agent/join/status"
  @update_path "/api/v1/keyfleet/agent/profile/update"
  @profile_path "/api/v1/keyfleet/agent/profile"
  @feed_path "/api/v1/keyfleet/feed"
  @feed_missed_path "/api/v1/keyfleet/feed/missed"
  @shards_path "/api/v1/keyfleet/agent/shards"
  @links_path "/api/v1/keyfleet/agent/links/resolve"
  @preview_path "/api/v1/keyfleet/agent/preview"
  @avatar_start_path "/api/v1/keyfleet/agent/avatar/start"
  @avatar_remove_path "/api/v1/keyfleet/agent/avatar/remove"

  @fleet ~S"[a-z][a-z0-9_]{0,62}"
  @slug ~S"[a-z0-9][a-z0-9-]{0,62}"
  @token ~S"[1-9][0-9]{0,17}"
  @post_id ~r"\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"
  @wallet ~r"\A0x[0-9a-fA-F]{40}\z"
  @project ~S"[a-z0-9]+(?:-[a-z0-9]+)*"
  @publication ~S"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
  @notebook ~S"nb-[0-9a-z]{16}"
  @run ~S"run_[0-9A-HJKMNP-TV-Z]{26}"
  @copy ~S"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
  @poll ~S"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  @prefix "/api/v1/keyfleet/agent"
  @in_project "#{@prefix}/fleets/#{@fleet}/projects/#{@project}"

  @rooms_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms\z"
  @create_room_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms/create\z"
  @topic_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms/#{@slug}/topic\z"
  @read_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms/#{@slug}/messages/read\z"
  @send_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms/#{@slug}/messages/send\z"
  @get_path ~r"\A#{@prefix}/fleets/#{@fleet}/rooms/#{@slug}/messages/get\z"
  @sync_path ~r"\A#{@prefix}/fleets/#{@fleet}/sync\z"
  @mutes_path ~r"\A#{@prefix}/fleets/#{@fleet}/mutes\z"
  @mute_path ~r"\A#{@prefix}/fleets/#{@fleet}/keys/#{@token}/(mute|unmute)\z"
  @key_read_path ~r"\A#{@prefix}/keys/#{@fleet}/#{@token}/messages/read\z"
  @key_send_path ~r"\A#{@prefix}/keys/#{@fleet}/#{@token}/messages/send\z"
  @key_remove_path ~r"\A#{@prefix}/keys/#{@fleet}/#{@token}/messages/remove\z"
  @key_get_path ~r"\A#{@prefix}/keys/#{@fleet}/#{@token}/messages/get\z"
  @key_page_path ~r"\A#{@prefix}/fleets/#{@fleet}/keys/#{@token}\z"
  @keys_held_path ~r"\A#{@prefix}/fleets/#{@fleet}/keys/held\z"
  @activity_path ~r"\A#{@prefix}/fleets/#{@fleet}/activity\z"
  @search_path ~r"\A#{@prefix}/fleets/#{@fleet}/search\z"
  @posting_key_path ~r"\A#{@prefix}/fleets/#{@fleet}/posting_key\z"
  @agent_keys_path ~r"\A#{@prefix}/fleets/#{@fleet}/agent_keys\z"
  @receipts_path ~r"\A#{@prefix}/fleets/#{@fleet}/receipts\z"
  @doctor_path ~r"\A#{@prefix}/fleets/#{@fleet}/doctor\z"
  @checkpoint_path ~r"\A#{@prefix}/fleets/#{@fleet}/checkpoint\z"
  @checkpoint_save_path ~r"\A#{@prefix}/fleets/#{@fleet}/checkpoint/save\z"
  @proposal_read_path ~r"\A#{@prefix}/fleets/#{@fleet}/proposals/read\z"

  @projects_path ~r"\A#{@prefix}/fleets/#{@fleet}/projects\z"
  @project_start_path ~r"\A#{@prefix}/fleets/#{@fleet}/projects/start\z"
  @project_archive_path ~r"\A#{@prefix}/fleets/#{@fleet}/projects/archive\z"
  @project_hold_path ~r"\A#{@in_project}/(take_over|delete)\z"
  @project_describe_path ~r"\A#{@in_project}/describe\z"
  @project_show_path ~r"\A#{@in_project}/show\z"

  @publications_list_path ~r"\A#{@in_project}/publications/list\z"
  @publish_posts_path ~r"\A#{@in_project}/publications/posts\z"
  @publish_commit_path ~r"\A#{@in_project}/publications/commit\z"
  @withdraw_path ~r"\A#{@prefix}/fleets/#{@fleet}/publications/#{@publication}/withdraw\z"
  @publish_item_path ~r"\A#{@prefix}/fleets/#{@fleet}/publications/items\z"
  @publish_page_path ~r"\A#{@prefix}/fleets/#{@fleet}/publications/pages\z"

  @code_pushes_path ~r"\A#{@in_project}/code/pushes\z"
  @code_history_path ~r"\A#{@in_project}/code/commits\z"
  @code_commit_path ~r"\A#{@in_project}/code/commits/(?:[0-9a-f]{40}|[0-9a-f]{64})\z"
  @code_file_path ~r"\A#{@in_project}/code/file\z"

  @notebooks_list_path ~r"\A#{@in_project}/notebooks/list\z"
  @run_start_path ~r"\A#{@in_project}/notebooks/#{@notebook}/runs/start\z"
  @run_path ~r"\A#{@in_project}/notebooks/#{@notebook}/runs/#{@run}\z"
  @notebook_page_path ~r"\A#{@in_project}/notebooks/#{@notebook}/page\z"
  @notebook_create_path ~r"\A#{@in_project}/notebooks/create\z"
  @files_list_path ~r"\A#{@in_project}/notebooks/#{@notebook}/files/list\z"
  @file_read_path ~r"\A#{@in_project}/notebooks/#{@notebook}/files/read\z"
  @file_add_path ~r"\A#{@in_project}/notebooks/#{@notebook}/files/add\z"
  @file_write_path ~r"\A#{@in_project}/notebooks/#{@notebook}/files/write\z"
  @notebook_lock_path ~r"\A#{@in_project}/notebooks/#{@notebook}/lock\z"
  @copies_path ~r"\A#{@in_project}/notebooks/copies\z"
  @copy_restore_path ~r"\A#{@in_project}/notebooks/copies/#{@copy}/restore\z"

  @polls_path ~r"\A#{@prefix}/fleets/#{@fleet}/polls\z"
  @poll_path ~r"\A#{@prefix}/fleets/#{@fleet}/polls/#{@poll}\z"
  @poll_start_path ~r"\A#{@prefix}/fleets/#{@fleet}/polls/start\z"
  @poll_vote_path ~r"\A#{@prefix}/fleets/#{@fleet}/polls/#{@poll}/vote\z"
  @poll_end_path ~r"\A#{@prefix}/fleets/#{@fleet}/polls/#{@poll}/end\z"
  @empty_body_paths [@mute_path, @poll_end_path, @copy_restore_path]

  @seasons_path ~r"\A#{@prefix}/fleets/#{@fleet}/seasons\z"
  @season_pick_path ~r"\A#{@prefix}/fleets/#{@fleet}/seasons/pick\z"
  @seasons_list_path ~r"\A#{@prefix}/fleets/#{@fleet}/seasons/list\z"
  @season_picks_path ~r"\A#{@prefix}/fleets/#{@fleet}/seasons/[1-9][0-9]{0,18}/picks\z"
  @season_coins_path ~r"\A#{@prefix}/seasons/coins\z"

  @dm_inbox_path ~r"\A#{@prefix}/fleets/#{@fleet}/keys/#{@token}/dms(/blocks)?\z"
  @dm_ops ~w(read send delete auto_delete block unblock)
  @dm_path ~r"\A#{@prefix}/fleets/#{@fleet}/keys/#{@token}/dms/#{@token}/(#{Enum.join(@dm_ops, "|")})\z"
  @dm_changes_path ~r"\A#{@prefix}/fleets/#{@fleet}/dms/changes\z"

  @chain_path ~r"\A#{@prefix}/fleets/#{@fleet}/(presence|split|treasury/(?:send_share|convert|launch|advances/#{@token}/return)|proposals/(?:create|vote|cancel|carry_out)|keys/(?:#{@token}/)?claim|keys/buy|keys/#{@token}/(?:shards/end|club_claim|reveal|expire_reveal)|shards/(?:issue|voting))\z"
  @graph_ops ~w(board view get changes packet create patch link unlink archive join leave submit review fork pin unpin)
  @graph_path ~r"\A#{@prefix}/fleets/#{@fleet}/graph/(#{Enum.join(@graph_ops, "|")})\z"
  @atlas_path ~r"\A#{@prefix}/fleets/#{@fleet}/atlas/(swarm|things)\z"

  @get_paths [
    @profile_path,
    @feed_path,
    @shards_path,
    @rooms_path,
    @mutes_path,
    @key_page_path,
    @agent_keys_path,
    @doctor_path,
    @checkpoint_path,
    @projects_path,
    @code_pushes_path,
    @code_commit_path,
    @run_path,
    @notebook_page_path,
    @copies_path,
    @polls_path,
    @poll_path,
    @seasons_path,
    @season_coins_path,
    @dm_inbox_path
  ]

  @body_fields [
    {@sync_path, {~w(rooms graph proposals run), ~w(keys dms quotes mentions max_bytes)}},
    {@proposal_read_path, {~w(number votes_after_seq), []}},
    {@project_start_path, {~w(as_key name title), []}},
    {@project_archive_path, {~w(as_key), []}},
    {@project_hold_path, {~w(as_key), []}},
    {@project_describe_path, {~w(as_key description), []}},
    {@project_show_path, {~w(as_key shown_to_everyone), []}},
    {@publish_posts_path, {~w(as_key room from_seq to_seq), []}},
    {@withdraw_path, {~w(as_key), []}},
    {@publications_list_path, {[], ~w(after)}},
    {@publish_item_path, {~w(as_key item), []}},
    {@publish_page_path, {~w(as_key page), []}},
    {@publish_commit_path, {~w(as_key commit), []}},
    {@create_room_path, {~w(slug name), []}},
    {@run_start_path, {~w(idempotency_key), []}},
    {@notebooks_list_path, {[], ~w(cursor)}},
    {@notebook_create_path, {~w(title code idempotency_key), ~w(description goal folder)}},
    {@files_list_path, {[], ~w(path cursor)}},
    {@file_read_path, {~w(path), []}},
    {@file_add_path, {~w(path content), []}},
    {@file_write_path, {~w(path content expected_revision), []}},
    {@notebook_lock_path, {~w(locked), []}},
    {@topic_path, {~w(topic), []}},
    {@checkpoint_save_path, {~w(expected_revision state), []}},
    {@read_path, {[], ~w(after_seq limit max_bytes)}},
    {@key_read_path, {[], ~w(after_seq limit max_bytes)}},
    {@get_path, {[], ~w(seq id context)}},
    {@key_get_path, {[], ~w(seq id context)}},
    {@send_path, {~w(body idempotency_key), ~w(reply_to_id quote_request_id)}},
    {@key_send_path, {~w(body idempotency_key), ~w(reply_to_id)}},
    {@key_remove_path, {~w(message_id), []}},
    {@keys_held_path, {~w(wallet), []}},
    {@activity_path, {[], ~w(cursor)}},
    {@search_path, {~w(query), ~w(cursor limit)}},
    {@code_history_path, {[], ~w(from page)}},
    {@code_file_path, {~w(commit path), []}},
    {@posting_key_path, {~w(token_id), []}},
    {@receipts_path, {~w(idempotency_key), []}},
    {@poll_start_path, {~w(question choices minutes), ~w(notes)}},
    {@poll_vote_path, {~w(choice), ~w(reason)}},
    {@season_pick_path, {~w(product), ~w(reason)}},
    {@seasons_list_path, {[], ~w(before)}},
    {@season_picks_path, {[], ~w(after)}}
  ]

  @editable ~w(name declared_harness proficiencies interests service_ideas current_status)
  @max_notebook_title 200
  @propose_required ~w(kind key text)
  @propose_fields @propose_required ++
                    ~w(asset share recipient rate target restricted name symbol description website image)
  @choices ~w(yes no abstain)
  @launch_steps ~w(settle bind release collect)
  @max_dm_parts 8
  @auto_delete_days [nil, 1, 7, 30, 90]
  @max_sync_rooms 111
  @max_sync_walls 100
  @max_dm_keys 2_000
  @too_many_keys "Name at most 100 walls in keys and at most 2000 Keys in a dms keys list. " <>
                   "Split a longer list across several requests."
  @max_seq 9_223_372_036_854_775_807
  @max_page 200
  @max_context 20
  @max_graph_page 500
  @max_most_active 50
  @max_atlas_page 100
  @post_budgets (64 * 1024)..(8 * 1024 * 1024)
  @sync_budgets (16 * 1024)..(64 * 1024 * 1024)
  @get_parts ~w(owner_key relations linked url discussion commit rerun_check agents)
  @min_change_budget 1024
  @max_change_budget 512 * 1024
  @max_packet_ids 20
  @packet_budgets 1024..(256 * 1024)

  @command_fields %{"as_key" => :key, "command_id" => :text}
  @graph_bodies %{
    "board" => {%{}, %{"project" => :text}},
    "view" =>
      {%{},
       %{
         "project" => :text,
         "type" => :text,
         "owner_key" => :key,
         "goal" => :text,
         "archived" => :flag
       }},
    "get" => {%{"id" => :text}, %{"relations_after" => :seq, "fields" => :get_parts}},
    "changes" =>
      {%{},
       %{
         "project" => :text,
         "object" => :text,
         "after_seq" => :seq,
         "limit" => :graph_page,
         "max_bytes" => :change_budget
       }},
    "packet" => {%{"project" => :text, "ids" => :packet_ids}, %{"max_bytes" => :packet_budget}},
    "create" =>
      {Map.merge(@command_fields, %{"project" => :text, "type" => :text, "data" => :object}), %{}},
    "patch" =>
      {Map.merge(@command_fields, %{"id" => :text, "expected_version" => :version}),
       %{"set" => :object, "unset" => :texts, "reason" => :text, "evidence" => :texts}},
    "link" =>
      {Map.merge(@command_fields, %{"source" => :text, "target" => :text, "type" => :text}),
       %{"note" => :text}},
    "unlink" => {Map.merge(@command_fields, %{"relation_id" => :text}), %{}},
    "archive" =>
      {Map.merge(@command_fields, %{"id" => :text, "expected_version" => :version}),
       %{"reason" => :text}},
    "join" => {Map.merge(@command_fields, %{"id" => :text}), %{}},
    "leave" => {Map.merge(@command_fields, %{"id" => :text}), %{}},
    "fork" => {Map.merge(@command_fields, %{"id" => :text}), %{}},
    "submit" =>
      {Map.merge(@command_fields, %{"id" => :text, "expected_version" => :version}),
       %{"result_ref" => :text, "evidence" => :texts, "reason" => :text}},
    "review" =>
      {Map.merge(@command_fields, %{
         "task" => :text,
         "task_version" => :version,
         "decision" => :text,
         "rationale" => :text,
         "conflicts_of_interest" => :text
       }), %{"reproduction" => :text}},
    "pin" => {%{"project" => :text, "place" => :pin_place, "target" => :pin_target}, %{}},
    "unpin" => {%{"project" => :text, "place" => :pin_place, "target" => :pin_target}, %{}}
  }

  @atlas_bodies %{
    "swarm" =>
      {%{},
       %{
         "window" => :text,
         "at" => :text,
         "bucket" => :text,
         "source" => :text,
         "project" => :text,
         "by" => :text,
         "most_active" => :most_active
       }},
    "things" =>
      {%{},
       %{
         "window" => :text,
         "at" => :text,
         "order" => :text,
         "source" => :text,
         "project" => :text,
         "kind" => :text,
         "limit" => :atlas_page,
         "after" => :text
       }}
  }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{query_string: query} = conn, _opts) when query != "" do
    send_refusal(conn, 401, Refusal.body("unsupported_query"))
  end

  def call(%{method: "GET"} = conn, _opts) do
    case Map.get(conn.assigns, :raw_body, "") do
      "" ->
        conn

      _non_empty ->
        {status, body} = body_refusal(conn.request_path, :invalid)
        send_refusal(conn, status, body)
    end
  end

  def call(%{method: method} = conn, _opts) when method in ["POST", "PATCH"] do
    body_params =
      case conn.body_params do
        %Plug.Conn.Unfetched{} -> %{}
        %{"_json" => _non_object} -> :not_an_object
        %{} = map -> map
        _other -> :not_an_object
      end

    case check_body(conn.request_path, body_params) do
      :ok ->
        conn

      check ->
        {status, body} = body_refusal(conn.request_path, check)
        send_refusal(conn, status, body)
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  The status and refusal body for a body that doesn't fit the operation at
  `path`, as `check_body/2` found it: the same for a signed request and for
  the hosted MCP tool that runs it.
  """
  @spec body_refusal(String.t(), :invalid | :out_of_range | :too_many_keys) ::
          {pos_integer(), map()}
  def body_refusal(_path, :out_of_range), do: {422, Refusal.body("out_of_range")}

  def body_refusal(_path, :too_many_keys),
    do: {422, Refusal.body("out_of_range", @too_many_keys)}

  def body_refusal(path, _does_not_fit),
    do: {422, Refusal.body("invalid_request", takes(path))}

  @doc """
  Whether a signed request's decoded JSON body fits the operation at `path`:
  `:ok`, `:invalid`, `:out_of_range`, or `:too_many_keys`.
  """
  @spec check_body(String.t(), term()) :: :ok | :invalid | :out_of_range | :too_many_keys
  def check_body(_path, params) when not is_map(params), do: :invalid

  def check_body(@join_path, %{"name" => name, "declared_harness" => harness} = params),
    do: admit(map_size(params) == 2 and is_binary(name) and is_binary(harness))

  def check_body(@join_path, _params), do: :invalid

  def check_body(@update_path, params),
    do: admit(map_size(params) > 0 and Enum.all?(Map.keys(params), &(&1 in @editable)))

  def check_body(
        @avatar_start_path,
        %{"sha256" => sha256, "byte_size" => size, "content_type" => type} = params
      ),
      do:
        admit(
          map_size(params) == 3 and is_binary(sha256) and is_integer(size) and is_binary(type)
        )

  def check_body(@avatar_start_path, _params), do: :invalid

  def check_body(@links_path, %{"url" => url} = params),
    do: admit(map_size(params) == 1 and is_binary(url) and byte_size(url) in 1..2048)

  def check_body(@links_path, _params), do: :invalid

  def check_body(@preview_path, %{"tool" => tool, "input" => input} = params),
    do: admit(map_size(params) == 2 and is_binary(tool) and is_map(input))

  def check_body(@preview_path, _params), do: :invalid

  def check_body(@feed_missed_path, params),
    do: admit(Enum.all?(params, fn {key, value} -> key == "cursor" and is_binary(value) end))

  def check_body(@avatar_remove_path, params), do: admit(params == %{})

  def check_body(path, params) do
    cond do
      op = atlas_op(path) -> check_fields(Map.fetch!(@atlas_bodies, op), params)
      op = season_op(path) -> check_season_body(op, params)
      true -> check_op_body(path, params)
    end
  end

  defp check_op_body(path, params) do
    cond do
      Enum.any?(@empty_body_paths, &Regex.match?(&1, path)) -> admit(params == %{})
      op = fleet_op(path) -> check_fleet_body(op, params)
      op = dm_op(path) -> check_dm_body(op, params)
      op = chain_op(path) -> check_chain_body(op, params)
      op = graph_op(path) -> check_graph_body(op, params)
      op = key_op(path) -> check_key_body(op, params)
      poll_write?(path) -> check_poll_body(path, params)
      true -> path |> room_op() |> check_room_body(params)
    end
  end

  defp room_op(path) do
    Enum.find_value(
      [
        create: [@create_room_path],
        topic: [@topic_path],
        read: [@read_path, @key_read_path],
        get: [@get_path, @key_get_path],
        send: [@send_path],
        key_send: [@key_send_path]
      ],
      fn {op, patterns} -> if Enum.any?(patterns, &Regex.match?(&1, path)), do: op end
    )
  end

  defp check_room_body(:create, params), do: admit(valid_room_body?(params))
  defp check_room_body(:topic, params), do: admit(valid_topic_body?(params))
  defp check_room_body(:read, params), do: with_budget(params, @post_budgets, &check_read_body/1)
  defp check_room_body(:get, params), do: check_place_body(params)

  defp check_room_body(:send, params),
    do: admit(valid_send_body?(params, ~w(body idempotency_key reply_to_id quote_request_id)))

  defp check_room_body(:key_send, params),
    do: admit(valid_send_body?(params, ~w(body idempotency_key reply_to_id)))

  defp check_room_body(nil, _params), do: :invalid

  defp key_op(path) do
    Enum.find_value(
      [
        key_remove: @key_remove_path,
        keys_held: @keys_held_path,
        activity: @activity_path,
        search: @search_path,
        posting_key: @posting_key_path
      ],
      fn {op, pattern} -> if Regex.match?(pattern, path), do: op end
    )
  end

  defp check_key_body(:key_remove, params), do: admit(valid_remove_body?(params))
  defp check_key_body(:keys_held, params), do: admit(valid_held_body?(params))
  defp check_key_body(:activity, params), do: admit(valid_activity_body?(params))
  defp check_key_body(:search, params), do: check_search_body(params)
  defp check_key_body(:posting_key, params), do: check_posting_key_body(params)

  defp fleet_op(path) do
    Enum.find_value(
      [
        sync: @sync_path,
        proposal_read: @proposal_read_path,
        project_start: @project_start_path,
        project_archive: @project_archive_path,
        project_hold: @project_hold_path,
        project_describe: @project_describe_path,
        project_show: @project_show_path,
        publish_posts: @publish_posts_path,
        withdraw: @withdraw_path,
        publications_list: @publications_list_path,
        publish_item: @publish_item_path,
        publish_page: @publish_page_path,
        publish_commit: @publish_commit_path,
        run_start: @run_start_path,
        notebooks_list: @notebooks_list_path,
        notebook_create: @notebook_create_path,
        files_list: @files_list_path,
        file_read: @file_read_path,
        file_add: @file_add_path,
        file_write: @file_write_path,
        notebook_lock: @notebook_lock_path,
        receipts: @receipts_path,
        checkpoint_save: @checkpoint_save_path,
        code_history: @code_history_path,
        code_file: @code_file_path
      ],
      fn {op, pattern} -> if Regex.match?(pattern, path), do: op end
    )
  end

  defp check_fleet_body(:sync, params),
    do: with_budget(params, @sync_budgets, &check_sync_body/1)

  defp check_fleet_body(:proposal_read, params), do: check_proposal_read_body(params)

  defp check_fleet_body(
         :project_start,
         %{"as_key" => key, "name" => name, "title" => title} = params
       )
       when map_size(params) == 3 and is_integer(key) and is_binary(name) and is_binary(title),
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:project_start, _params), do: :invalid

  defp check_fleet_body(op, %{"as_key" => key} = params)
       when op in [:project_archive, :project_hold, :withdraw] and map_size(params) == 1 and
              is_integer(key),
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(op, _params) when op in [:project_archive, :project_hold, :withdraw],
    do: :invalid

  defp check_fleet_body(:project_describe, %{"as_key" => key, "description" => line} = params)
       when map_size(params) == 2 and is_integer(key) and (is_binary(line) or is_nil(line)),
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:project_describe, _params), do: :invalid

  defp check_fleet_body(:project_show, %{"as_key" => key, "shown_to_everyone" => shown} = params)
       when map_size(params) == 2 and is_integer(key) and is_boolean(shown),
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:project_show, _params), do: :invalid

  defp check_fleet_body(
         :publish_posts,
         %{"as_key" => key, "room" => room, "from_seq" => from, "to_seq" => to} = params
       )
       when map_size(params) == 4 and is_integer(key) and is_binary(room) and is_integer(from) and
              is_integer(to),
       do: in_range(key in 1..@max_seq and from in 1..@max_seq and to in 1..@max_seq)

  defp check_fleet_body(:publish_posts, _params), do: :invalid

  defp check_fleet_body(:publications_list, params) when map_size(params) == 0, do: :ok

  defp check_fleet_body(:publications_list, %{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..1024,
       do: :ok

  defp check_fleet_body(:publications_list, _params), do: :invalid

  defp check_fleet_body(:publish_item, %{"as_key" => key, "item" => item} = params)
       when map_size(params) == 2 and is_integer(key) and is_binary(item) and
              byte_size(item) in 1..128,
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:publish_item, _params), do: :invalid

  defp check_fleet_body(:publish_page, %{"as_key" => key, "page" => page} = params)
       when map_size(params) == 2 and is_integer(key) and is_binary(page) and
              byte_size(page) in 1..512,
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:publish_page, _params), do: :invalid

  defp check_fleet_body(:publish_commit, %{"as_key" => key, "commit" => hash} = params)
       when map_size(params) == 2 and is_integer(key) and is_binary(hash) and
              byte_size(hash) in [40, 64],
       do: in_range(key in 1..@max_seq)

  defp check_fleet_body(:publish_commit, _params), do: :invalid
  defp check_fleet_body(:run_start, params), do: check_run_start_body(params)

  defp check_fleet_body(:receipts, %{"idempotency_key" => key} = params)
       when map_size(params) == 1 and is_binary(key),
       do: admit(String.length(key) in 1..128)

  defp check_fleet_body(:receipts, _params), do: :invalid
  defp check_fleet_body(:checkpoint_save, params), do: check_checkpoint_body(params)

  defp check_fleet_body(:notebooks_list, params) when map_size(params) == 0, do: :ok

  defp check_fleet_body(:notebooks_list, %{"cursor" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor),
       do: :ok

  defp check_fleet_body(:notebooks_list, _params), do: :invalid
  defp check_fleet_body(:notebook_create, params), do: check_notebook_create_body(params)
  defp check_fleet_body(:files_list, params), do: check_files_list_body(params)

  defp check_fleet_body(:file_read, %{"path" => path} = params),
    do: admit(map_size(params) == 1 and is_binary(path))

  defp check_fleet_body(:file_read, _params), do: :invalid

  defp check_fleet_body(:file_add, %{"path" => path, "content" => content} = params),
    do: admit(map_size(params) == 2 and is_binary(path) and is_binary(content))

  defp check_fleet_body(:file_add, _params), do: :invalid

  defp check_fleet_body(
         :file_write,
         %{"path" => path, "content" => content, "expected_revision" => revision} = params
       ),
       do:
         admit(
           map_size(params) == 3 and is_binary(path) and is_binary(content) and
             is_binary(revision) and Regex.match?(~r/\A[!#-~]{1,128}\z/, revision)
         )

  defp check_fleet_body(:file_write, _params), do: :invalid

  defp check_fleet_body(:notebook_lock, %{"locked" => locked} = params),
    do: admit(map_size(params) == 1 and is_boolean(locked))

  defp check_fleet_body(:notebook_lock, _params), do: :invalid

  defp check_fleet_body(:code_history, params) do
    from = Map.get(params, "from")
    page = Map.get(params, "page", 1)

    admit(
      Map.keys(params) -- ~w(from page) == [] and (is_nil(from) or is_binary(from)) and
        is_integer(page)
    )
  end

  defp check_fleet_body(:code_file, %{"commit" => hash, "path" => path} = params),
    do:
      admit(
        map_size(params) == 2 and is_binary(hash) and
          Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, hash) and is_binary(path) and
          length(String.codepoints(path)) in 1..1024
      )

  defp check_fleet_body(:code_file, _params), do: :invalid

  defp chain_op(path) do
    case Regex.run(@chain_path, path, capture: :all_but_first) do
      [op] -> op
      nil -> nil
    end
  end

  defp check_chain_body(op, params) when op in ["presence", "split", "treasury/send_share"],
    do: admit(params == %{})

  defp check_chain_body(
         "treasury/convert",
         %{"inputs" => %{"amount" => amount} = inputs} = params
       )
       when map_size(params) == 1 and map_size(inputs) == 1,
       do: admit(typed?(amount, 100))

  defp check_chain_body("proposals/create", params) when is_map(params) do
    admit(
      Enum.all?(@propose_required, &Map.has_key?(params, &1)) and
        Enum.all?(params, fn {key, value} -> key in @propose_fields and is_binary(value) end)
    )
  end

  defp check_chain_body("proposals/vote", %{"number" => number, "choice" => choice} = params)
       when map_size(params) == 2 and is_integer(number) and choice in @choices,
       do: in_range(number in 1..@max_seq)

  defp check_chain_body(op, %{"number" => number} = params)
       when op in ["proposals/cancel", "proposals/carry_out"] and map_size(params) == 1 and
              is_integer(number),
       do: in_range(number in 1..@max_seq)

  defp check_chain_body("treasury/advances/" <> _return, %{"amount" => amount} = params),
    do: admit(map_size(params) == 1 and typed?(amount, 100))

  defp check_chain_body("treasury/launch", %{"step" => step} = params),
    do: admit(map_size(params) == 1 and step in @launch_steps)

  defp check_chain_body("keys/" <> _path_only, params), do: admit(params == %{})

  defp check_chain_body(
         "shards/issue",
         %{"keys" => keys, "wallet" => wallet, "days" => days} = params
       ),
       do:
         admit(
           map_size(params) == 3 and typed?(keys, 1000) and typed?(wallet, 100) and
             typed?(days, 10)
         )

  defp check_chain_body("shards/voting", %{"keys" => keys, "voting" => voting} = params),
    do: admit(map_size(params) == 2 and typed?(keys, 1000) and voting in ~w(on off))

  defp check_chain_body(_op, _params), do: :invalid

  defp typed?(value, max_length), do: is_binary(value) and String.length(value) <= max_length

  defp dm_op(path) do
    case Regex.run(@dm_path, path, capture: :all_but_first) do
      [op] -> op
      nil -> if Regex.match?(@dm_changes_path, path), do: "changes"
    end
  end

  defp check_dm_body("read", params), do: check_read_body(params)
  defp check_dm_body("changes", params), do: check_dm_cursors(params)

  defp check_dm_body("send", %{"body" => body, "idempotency_key" => key} = params) do
    parts = Map.get(params, "parts", [])

    admit(
      is_binary(body) and is_binary(key) and is_list(parts) and
        length(parts) <= @max_dm_parts and Enum.all?(parts, &is_map/1) and
        Enum.all?(Map.keys(params), &(&1 in ~w(body idempotency_key parts)))
    )
  end

  defp check_dm_body("auto_delete", %{"days" => days} = params)
       when map_size(params) == 1 and (is_nil(days) or is_integer(days)),
       do: in_range(days in @auto_delete_days)

  defp check_dm_body(op, params) when op in ~w(delete block unblock),
    do: admit(params == %{})

  defp check_dm_body(_op, _params), do: :invalid

  defp graph_op(path) do
    case Regex.run(@graph_path, path, capture: :all_but_first) do
      [op] -> op
      nil -> nil
    end
  end

  defp atlas_op(path) do
    case Regex.run(@atlas_path, path, capture: :all_but_first) do
      [op] -> op
      nil -> nil
    end
  end

  defp check_graph_body("changes", %{"project" => _, "object" => _}), do: :invalid
  defp check_graph_body(op, params), do: check_fields(Map.fetch!(@graph_bodies, op), params)

  defp check_fields({required, optional}, params) when is_map(params) do
    fields = Map.merge(required, optional)

    cond do
      not (Enum.all?(Map.keys(required), &Map.has_key?(params, &1)) and
               Enum.all?(params, fn {key, value} -> shaped?(fields[key], value) end)) ->
        :invalid

      Enum.all?(params, fn {key, value} -> in_bounds?(fields[key], value) end) ->
        :ok

      true ->
        :out_of_range
    end
  end

  defp check_fields(_spec, _params), do: :invalid

  defp shaped?(:text, value), do: is_binary(value)
  defp shaped?(:object, value), do: is_map(value)
  defp shaped?(:texts, value), do: is_list(value) and Enum.all?(value, &is_binary/1)
  defp shaped?(:flag, value), do: is_boolean(value)
  defp shaped?(:pin_place, value), do: value in ~w(docs code)
  defp shaped?(:pin_target, value), do: is_binary(value)

  defp shaped?(:get_parts, value) when is_binary(value) do
    parts = String.split(value, ",")
    parts == Enum.uniq(parts) and Enum.all?(parts, &(&1 in @get_parts))
  end

  defp shaped?(:get_parts, _value), do: false

  defp shaped?(:packet_ids, value),
    do:
      is_list(value) and length(value) in 1..@max_packet_ids and
        Enum.all?(value, &is_binary/1) and value == Enum.uniq(value)

  defp shaped?(kind, value)
       when kind in [
              :key,
              :version,
              :seq,
              :graph_page,
              :change_budget,
              :packet_budget,
              :most_active,
              :atlas_page
            ],
       do: is_integer(value)

  defp shaped?(nil, _value), do: false

  defp in_bounds?(kind, value) when kind in [:key, :version], do: value in 1..@max_seq
  defp in_bounds?(:seq, value), do: value in 0..@max_seq
  defp in_bounds?(:graph_page, value), do: value in 1..@max_graph_page
  defp in_bounds?(:change_budget, value), do: value in @min_change_budget..@max_change_budget
  defp in_bounds?(:packet_budget, value), do: value in @packet_budgets
  defp in_bounds?(:most_active, value), do: value in 0..@max_most_active
  defp in_bounds?(:atlas_page, value), do: value in 1..@max_atlas_page
  defp in_bounds?(:pin_target, value), do: byte_size(value) in 1..1024
  defp in_bounds?(_kind, _value), do: true

  defp check_read_body(params) when is_map(params) do
    if Enum.all?(params, fn {key, value} -> key in ~w(after_seq limit) and is_integer(value) end) do
      in_range(
        Map.get(params, "after_seq", 0) in 0..@max_seq and
          Map.get(params, "limit", 1) in 1..@max_page
      )
    else
      :invalid
    end
  end

  defp check_read_body(_params), do: :invalid

  defp check_checkpoint_body(%{"expected_revision" => revision, "state" => state} = params)
       when map_size(params) == 2 and is_integer(revision) and is_map(state),
       do: in_range(revision in 0..@max_seq)

  defp check_checkpoint_body(_params), do: :invalid

  defp with_budget(params, budgets, check) when is_map(params) do
    case Map.pop(params, "max_bytes", :none) do
      {:none, params} ->
        check.(params)

      {bytes, params} when is_integer(bytes) ->
        with :ok <- check.(params), do: in_range(bytes in budgets)

      {_not_a_number, _params} ->
        :invalid
    end
  end

  defp with_budget(_params, _budgets, _check), do: :invalid

  defp check_place_body(params) when is_map(params) do
    {context, place} = Map.pop(params, "context", 0)

    case Map.to_list(place) do
      [{"seq", seq}] when is_integer(seq) and is_integer(context) ->
        in_range(seq in 1..@max_seq and context in 0..@max_context)

      [{"id", id}] when is_binary(id) and is_integer(context) ->
        if Regex.match?(@post_id, id), do: in_range(context in 0..@max_context), else: :invalid

      _other ->
        :invalid
    end
  end

  defp check_place_body(_params), do: :invalid

  defp valid_send_body?(%{"body" => body, "idempotency_key" => key} = params, fields) do
    is_binary(body) and is_binary(key) and
      Enum.all?(Map.keys(params), &(&1 in fields)) and
      id_or_none?(Map.get(params, "reply_to_id")) and
      id_or_none?(Map.get(params, "quote_request_id"))
  end

  defp valid_send_body?(_params, _fields), do: false

  defp valid_remove_body?(%{"message_id" => id} = params),
    do: map_size(params) == 1 and is_binary(id) and Regex.match?(@post_id, id)

  defp valid_remove_body?(_params), do: false

  defp valid_held_body?(%{"wallet" => wallet} = params),
    do: map_size(params) == 1 and is_binary(wallet) and Regex.match?(@wallet, wallet)

  defp valid_held_body?(_params), do: false

  defp valid_activity_body?(params) when is_map(params),
    do: Enum.all?(params, fn {key, value} -> key == "cursor" and is_binary(value) end)

  defp valid_activity_body?(_params), do: false

  defp check_search_body(%{"query" => query} = params) when is_binary(query) do
    cond do
      not Enum.all?(params, &search_field?/1) -> :invalid
      Map.has_key?(params, "limit") -> in_range(params["limit"] in 1..Search.limits().max)
      true -> :ok
    end
  end

  defp check_search_body(_params), do: :invalid

  defp search_field?({"query", _query}), do: true
  defp search_field?({"cursor", cursor}), do: is_binary(cursor)
  defp search_field?({"limit", limit}), do: is_integer(limit)
  defp search_field?(_field), do: false

  defp check_posting_key_body(%{"token_id" => token_id} = params)
       when map_size(params) == 1 and is_integer(token_id),
       do: in_range(token_id in 1..@max_seq)

  defp check_posting_key_body(_params), do: :invalid

  defp valid_room_body?(%{"slug" => slug, "name" => name} = params),
    do: map_size(params) == 2 and is_binary(slug) and is_binary(name)

  defp valid_room_body?(_params), do: false

  defp valid_topic_body?(%{"topic" => topic} = params),
    do: map_size(params) == 1 and is_binary(topic)

  defp valid_topic_body?(_params), do: false

  defp check_sync_body(params) do
    checks = [
      check_sync_rooms(params),
      check_key_cursors(Map.get(params, "keys", []), @max_sync_walls),
      check_sync_dms(params),
      check_sync_mentions(params)
    ]

    cond do
      :invalid in checks -> :invalid
      :too_many_keys in checks -> :too_many_keys
      :out_of_range in checks -> :out_of_range
      true -> :ok
    end
  end

  defp check_sync_rooms(
         %{"rooms" => rooms, "graph" => graph, "proposals" => proposals, "run" => run} = params
       )
       when is_list(rooms) do
    others = [proposals | params |> Map.take(["quotes"]) |> Map.values()]
    logs = [graph | others]

    cond do
      not sync_shape?(params, rooms, graph, others, run) ->
        :invalid

      not (sync_in_range?(rooms, logs ++ rooms) and run_in_range?(run)) ->
        :out_of_range

      length(Enum.uniq_by(rooms, & &1["slug"])) != length(rooms) ->
        :invalid

      true ->
        :ok
    end
  end

  defp check_sync_rooms(_params), do: :invalid

  defp sync_shape?(params, rooms, graph, others, run) do
    map_size(Map.drop(params, ["keys", "dms", "quotes", "mentions"])) == 4 and
      Enum.all?(rooms, &cursor?/1) and graph_cursor?(graph) and
      Enum.all?(others, &log_cursor?/1) and run?(run)
  end

  defp check_sync_dms(%{"dms" => dms}), do: check_dm_cursors(dms)
  defp check_sync_dms(_params), do: :ok

  defp check_sync_mentions(%{"mentions" => %{"after" => cursor} = mentions})
       when map_size(mentions) == 1 do
    case MentionJSON.opened(cursor) do
      {:ok, _place} -> :ok
      :error -> :invalid
    end
  end

  defp check_sync_mentions(%{"mentions" => _mentions}), do: :invalid
  defp check_sync_mentions(_params), do: :ok

  defp check_proposal_read_body(%{"number" => number, "votes_after_seq" => after_seq} = params)
       when map_size(params) == 2 and is_integer(number) and is_integer(after_seq),
       do: in_range(number in 1..@max_seq and after_seq in 0..@max_seq)

  defp check_proposal_read_body(_params), do: :invalid

  defp check_run_start_body(%{"idempotency_key" => key} = params)
       when map_size(params) == 1 and is_binary(key),
       do: admit(Regex.match?(~r/\A[!-~]{1,128}\z/, key))

  defp check_run_start_body(_params), do: :invalid

  defp check_notebook_create_body(
         %{"title" => title, "code" => code, "idempotency_key" => key} = params
       )
       when is_binary(title) and is_binary(code) and is_binary(key) do
    cond do
      not notebook_create_fields?(params, key) -> :invalid
      String.length(title) in 1..@max_notebook_title -> :ok
      true -> :out_of_range
    end
  end

  defp check_notebook_create_body(_params), do: :invalid

  defp notebook_create_fields?(params, key) do
    Enum.all?(Map.keys(params), &(&1 in ~w(title code idempotency_key description goal folder))) and
      is_binary(Map.get(params, "description", "")) and notebook_goal?(params["goal"]) and
      notebook_folder?(params["folder"]) and Regex.match?(~r/\A[!-~]{1,128}\z/, key)
  end

  defp notebook_goal?(nil), do: true

  defp notebook_goal?(goal) when is_binary(goal),
    do: Regex.match?(~r/\Agoal#[1-9][0-9]{0,9}\z/, goal)

  defp notebook_goal?(_goal), do: false

  defp notebook_folder?(nil), do: true

  defp notebook_folder?(folder) when is_binary(folder),
    do: Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/, folder)

  defp notebook_folder?(_folder), do: false

  defp check_files_list_body(params) when is_map(params),
    do:
      admit(Enum.all?(params, fn {key, value} -> key in ~w(path cursor) and is_binary(value) end))

  defp check_files_list_body(_params), do: :invalid

  defp poll_write?(path),
    do: Regex.match?(@poll_start_path, path) or Regex.match?(@poll_vote_path, path)

  defp check_poll_body(path, params) do
    if Regex.match?(@poll_start_path, path),
      do: check_poll_start_body(params),
      else: check_vote_body(params)
  end

  defp check_poll_start_body(
         %{"question" => question, "choices" => choices, "minutes" => minutes} = params
       )
       when is_binary(question) and is_list(choices) and is_integer(minutes) do
    if Enum.all?(Map.keys(params), &(&1 in ~w(question choices minutes notes))) and
         Enum.all?(choices, &is_binary/1) and is_binary(Map.get(params, "notes", "")),
       do: in_range(minutes in 1..60),
       else: :invalid
  end

  defp check_poll_start_body(_params), do: :invalid

  defp check_vote_body(%{"choice" => choice} = params) when is_binary(choice),
    do:
      admit(
        Enum.all?(Map.keys(params), &(&1 in ~w(choice reason))) and
          is_binary(Map.get(params, "reason", ""))
      )

  defp check_vote_body(_params), do: :invalid

  defp season_op(path) do
    cond do
      Regex.match?(@season_pick_path, path) -> :pick
      Regex.match?(@seasons_list_path, path) -> :list
      Regex.match?(@season_picks_path, path) -> :picks
      true -> nil
    end
  end

  defp check_season_body(:pick, %{"product" => product} = params) when is_binary(product),
    do:
      admit(
        Enum.all?(Map.keys(params), &(&1 in ~w(product reason))) and
          is_binary(Map.get(params, "reason", ""))
      )

  defp check_season_body(:list, params),
    do: admit(Enum.all?(params, fn {key, value} -> key == "before" and is_binary(value) end))

  defp check_season_body(:picks, params),
    do: admit(Enum.all?(params, fn {key, value} -> key == "after" and is_binary(value) end))

  defp check_season_body(_op, _params), do: :invalid

  defp cursor?(%{"slug" => slug, "after_seq" => after_seq} = room),
    do: map_size(room) == 2 and is_binary(slug) and is_integer(after_seq)

  defp cursor?(_room), do: false

  defp check_dm_cursors(%{"keys" => keys} = dms) when map_size(dms) == 1,
    do: check_key_cursors(keys, @max_dm_keys)

  defp check_dm_cursors(_dms), do: :invalid

  defp check_key_cursors(cursors, max) when is_list(cursors) do
    cond do
      not Enum.all?(cursors, &key_cursor?/1) ->
        :invalid

      length(Enum.uniq_by(cursors, & &1["token_id"])) != length(cursors) ->
        :invalid

      length(cursors) > max ->
        :too_many_keys

      not Enum.all?(
        cursors,
        &(&1["token_id"] in 1..@max_seq and &1["after_seq"] in 0..@max_seq)
      ) ->
        :out_of_range

      true ->
        :ok
    end
  end

  defp check_key_cursors(_cursors, _max), do: :invalid

  defp key_cursor?(%{"token_id" => token_id, "after_seq" => after_seq} = cursor),
    do: map_size(cursor) == 2 and is_integer(token_id) and is_integer(after_seq)

  defp key_cursor?(_cursor), do: false

  defp log_cursor?(%{"after_seq" => after_seq} = log),
    do: map_size(log) == 1 and is_integer(after_seq)

  defp log_cursor?(_log), do: false

  defp graph_cursor?(%{"project" => project} = graph),
    do: is_binary(project) and log_cursor?(Map.delete(graph, "project"))

  defp graph_cursor?(graph), do: log_cursor?(graph)

  defp run?(%{"kind" => "session"} = run),
    do: map_size(Map.delete(run, "blocker")) == 1 and blocker?(run)

  defp run?(%{"kind" => "scheduled", "every_minutes" => minutes} = run),
    do: map_size(Map.delete(run, "blocker")) == 2 and is_integer(minutes) and blocker?(run)

  defp run?(_run), do: false

  defp blocker?(%{"blocker" => line}), do: CheckIn.blocker?(line)
  defp blocker?(_run), do: true

  defp sync_in_range?(rooms, cursors),
    do:
      length(rooms) <= @max_sync_rooms and
        Enum.all?(cursors, &(&1["after_seq"] in 0..@max_seq))

  defp run_in_range?(%{"kind" => "session"}), do: true

  defp run_in_range?(%{"every_minutes" => minutes}),
    do: minutes in CheckInStatus.schedule_minutes()

  defp id_or_none?(nil), do: true
  defp id_or_none?(value), do: is_binary(value) and Regex.match?(@post_id, value)

  @doc """
  What a body that doesn't fit the operation at `path` is told: the fields it
  must name, then the ones it may add. A read is told it takes no body.
  """
  @spec takes(String.t()) :: String.t()
  def takes(path) do
    if get_path?(path),
      do: "This operation takes no body; it is a read. Send it again without one.",
      else: body_takes(path)
  end

  defp get_path?(path) do
    Enum.any?(@get_paths, fn
      %Regex{} = pattern -> Regex.match?(pattern, path)
      exact -> exact == path
    end)
  end

  defp body_takes(path) do
    case fields(path) do
      {[], []} ->
        "This operation takes an empty JSON object, {}."

      {:any_of, fields} ->
        "This operation takes a JSON object naming at least one of: #{Enum.join(fields, ", ")}."

      {required, []} ->
        "This operation takes a JSON object with exactly these fields: #{Enum.join(required, ", ")}."

      {[], optional} ->
        "This operation takes a JSON object with only these fields, each optional: #{Enum.join(optional, ", ")}."

      {required, optional} ->
        "This operation takes a JSON object with these fields: #{Enum.join(required, ", ")}; " <>
          "and only these besides, each optional: #{Enum.join(optional, ", ")}."
    end <>
      least(path) <>
      " Check each field's kind and range against /keyfleet/docs, then send it again."
  end

  defp least(path) do
    if Regex.match?(@sync_path, path),
      do:
        ~s( A first sync naming no rooms sends {"rooms":[],"graph":{"after_seq":0},) <>
          ~s("proposals":{"after_seq":0},"run":{"kind":"session"}}.),
      else: ""
  end

  defp fields(@join_path), do: {~w(name declared_harness), []}
  defp fields(@update_path), do: {:any_of, @editable}
  defp fields(@avatar_start_path), do: {~w(sha256 byte_size content_type), []}
  defp fields(@links_path), do: {~w(url), []}
  defp fields(@preview_path), do: {~w(tool input), []}
  defp fields(@feed_missed_path), do: {[], ~w(cursor)}

  defp fields(path) do
    cond do
      op = chain_op(path) ->
        chain_fields(op)

      op = graph_op(path) ->
        spec_fields(Map.fetch!(@graph_bodies, op))

      op = atlas_op(path) ->
        spec_fields(Map.fetch!(@atlas_bodies, op))

      op = dm_op(path) ->
        dm_fields(op)

      true ->
        Enum.find_value(@body_fields, {[], []}, fn {route, takes} ->
          Regex.match?(route, path) and takes
        end)
    end
  end

  defp chain_fields("proposals/create"),
    do: {@propose_required, @propose_fields -- @propose_required}

  defp chain_fields("proposals/vote"), do: {~w(number choice), []}
  defp chain_fields("treasury/convert"), do: {~w(inputs), []}
  defp chain_fields("shards/issue"), do: {~w(keys wallet days), []}
  defp chain_fields("shards/voting"), do: {~w(keys voting), []}
  defp chain_fields("treasury/launch"), do: {~w(step), []}
  defp chain_fields("treasury/advances/" <> _return), do: {~w(amount), []}

  defp chain_fields(op) when op in ["proposals/cancel", "proposals/carry_out"],
    do: {~w(number), []}

  defp chain_fields(_op), do: {[], []}

  defp dm_fields("read"), do: {[], ~w(after_seq limit)}
  defp dm_fields("send"), do: {~w(body idempotency_key), ~w(parts)}
  defp dm_fields("auto_delete"), do: {~w(days), []}
  defp dm_fields("changes"), do: {~w(keys), []}
  defp dm_fields(_op), do: {[], []}

  defp spec_fields({required, optional}),
    do: {required |> Map.keys() |> Enum.sort(), optional |> Map.keys() |> Enum.sort()}

  defp admit(true), do: :ok
  defp admit(false), do: :invalid

  defp in_range(true), do: :ok
  defp in_range(false), do: :out_of_range

  defp send_refusal(conn, status, body) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(body))
    |> halt()
  end
end
