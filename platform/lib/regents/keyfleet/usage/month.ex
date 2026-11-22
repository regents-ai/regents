defmodule Regents.Keyfleet.Usage.Month do
  @moduledoc """
  One fleet's usage in one calendar month (UTC), the month that starts on
  `month`, as last counted (`counted_at`):

    * `workspace_bytes` and `workspace_items`: how large its workspace
      record stood at the month's end, or now while the month is under way
      (`Regents.Keyfleet.Graph.record_size/2`);
    * `chat_posts` and `chat_bytes`: the posts written in its rooms and on
      its Keys' walls during the month, and their words as stored
      (`Regents.Keyfleet.Rooms.posts_written/3`). Direct messages are not counted;
    * `notebook_seconds`: how long its notebook machines ran during the
      month (`Regents.Keyfleet.Usage.Machine`), as of the fleet's last hub read
      (`Regents.Keyfleet.Usage.ReadHub`). Nil until a read of the fleet's hub counts
      the month, so a fleet without a hub, and a month that ended before its
      hub was first read, show no figure.

  Every figure is counted from the records that hold it, never written in.
  Each count replaces the month's last one. Anyone reads it: the Treasury
  page shows it to anyone.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Usage,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "fleet_usage"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:month, "fleet_usage_month_start", check: "extract(day FROM month) = 1")
    end
  end

  actions do
    defaults [:read]

    # Counts the fleet's usage in the month starting on `month` and keeps it
    # in place of the month's last count.
    create :count do
      accept [:fleet_id, :month]
      upsert? true
      upsert_fields [:workspace_bytes, :workspace_items, :chat_posts, :chat_bytes, :counted_at]

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, &Regents.Keyfleet.Usage.Month.counted/1)
      end
    end

    # Counts the month's notebook hours from the machines read from the
    # fleet's hub, in place of their last count.
    update :count_notebooks do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.before_action(changeset, &Regents.Keyfleet.Usage.Month.notebooks_counted/1)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:count, :count_notebooks]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true

    # The month's first day.
    attribute :month, :date, primary_key?: true, allow_nil?: false, public?: true

    attribute :workspace_bytes, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :workspace_items, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :chat_posts, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :chat_bytes, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    attribute :notebook_seconds, :integer, public?: true, constraints: [min: 0]
    attribute :counted_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  @doc false
  def counted(changeset) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    {from, to} = changeset |> Ash.Changeset.get_attribute(:month) |> bounds()
    workspace = Regents.Keyfleet.Graph.record_size(fleet_id, to)
    chat = Regents.Keyfleet.Rooms.posts_written(fleet_id, from, to)

    Ash.Changeset.force_change_attributes(changeset, %{
      workspace_bytes: workspace.bytes,
      workspace_items: workspace.items,
      chat_posts: chat.posts,
      chat_bytes: chat.bytes,
      counted_at: DateTime.utc_now()
    })
  end

  @doc false
  def notebooks_counted(changeset) do
    require Ash.Expr

    system = [actor: %Regents.Account.Actors.System{}]
    {from, to} = bounds(changeset.data.month)

    %{seconds: seconds} =
      Regents.Keyfleet.Usage.Machine
      |> Ash.Query.for_read(
        :during,
        %{fleet_id: changeset.data.fleet_id, from: from, to: to},
        system
      )
      |> Ash.aggregate!(
        {:seconds, :sum,
         expr:
           Ash.Expr.expr(
             fragment(
               "extract(epoch FROM least(coalesce(?, ?), ?) - greatest(?, ?))::bigint",
               ended_at,
               seen_at,
               ^to,
               started_at,
               ^from
             )
           ),
         expr_type: :integer,
         default: 0},
        system
      )

    Ash.Changeset.force_change_attribute(changeset, :notebook_seconds, seconds)
  end

  defp bounds(month),
    do:
      {DateTime.new!(month, ~T[00:00:00]),
       DateTime.new!(Date.shift(month, month: 1), ~T[00:00:00])}
end
