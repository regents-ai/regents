defmodule RegentsWeb.Keyfleet.AgentGraphController do
  use RegentsWeb, :controller

  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.Errors.WriteLimitError
  alias RegentsWeb.Keyfleet.{AgentReply, AgentTools, WorkspaceRefusal}
  alias RegentsWeb.Keyfleet.AgentTools.Workspace.Answer

  @command ~w(as_key command_id)

  # The workspace's reads answer what the same tool at the Claude connector's
  # address does (`RegentsWeb.Keyfleet.AgentTools.Workspace`).
  def view(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.workspace_view(
          fleet_id,
          Map.take(params, ~w(project type owner_key goal archived)),
          actor: conn.assigns.actor
        )
      )

  def get_object(conn, %{"fleet_id" => fleet_id, "id" => id} = params),
    do:
      answer_read(
        conn,
        AgentTools.workspace_show(
          fleet_id,
          id,
          Map.take(params, ~w(relations_after fields)),
          actor: conn.assigns.actor
        )
      )

  def changes(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.workspace_changes(
          fleet_id,
          Map.take(params, ~w(after_seq limit project object max_bytes)),
          actor: conn.assigns.actor
        )
      )

  def packet(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.workspace_packet(
          fleet_id,
          Map.take(params, ~w(project ids max_bytes)),
          actor: conn.assigns.actor
        )
      )

  def board(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.workspace_board(fleet_id, Map.take(params, ~w(project)),
          actor: conn.assigns.actor
        )
      )

  def atlas_swarm(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.atlas_swarm(
          fleet_id,
          Map.take(params, ~w(window at bucket source project by most_active)),
          actor: conn.assigns.actor
        )
      )

  def atlas_things(conn, %{"fleet_id" => fleet_id} = params),
    do:
      answer_read(
        conn,
        AgentTools.atlas_things(
          fleet_id,
          Map.take(params, ~w(window at order source project kind limit after)),
          actor: conn.assigns.actor
        )
      )

  def create(conn, params),
    do: write(conn, &Graph.create_object/3, params, ~w(project type data))

  def patch(conn, params),
    do:
      write(
        conn,
        &Graph.patch_object/3,
        params,
        ~w(id expected_version set unset reason evidence)
      )

  def link(conn, params),
    do: write(conn, &Graph.link_objects/3, params, ~w(source target type note))

  def unlink(conn, params), do: write(conn, &Graph.unlink_relation/3, params, ~w(relation_id))

  def archive(conn, params),
    do: write(conn, &Graph.archive_object/3, params, ~w(id expected_version reason))

  def join(conn, params), do: write(conn, &Graph.join/3, params, ~w(id))

  def leave(conn, params), do: write(conn, &Graph.leave/3, params, ~w(id))

  def fork(conn, params), do: write(conn, &Graph.fork_task/3, params, ~w(id))

  def submit(conn, params),
    do:
      write(
        conn,
        &Graph.submit_task/3,
        params,
        ~w(id expected_version result_ref evidence reason)
      )

  def review(conn, params),
    do:
      write(
        conn,
        &Graph.review_task/3,
        params,
        ~w(task task_version decision rationale conflicts_of_interest reproduction)
      )

  # Pinning and unpinning answer what the same tools at the Claude
  # connector's address do (`RegentsWeb.Keyfleet.AgentTools.Workspace.Answer`).
  def pin(conn, params), do: reply(conn, :pin, params)
  def unpin(conn, params), do: reply(conn, :unpin, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))

  defp answer_read(conn, {:ok, answer}), do: json(conn, answer)
  defp answer_read(conn, {:error, error}), do: refuse(conn, error)

  # A write past its wallet's allowance in the fleet
  # (`Regents.Keyfleet.Graph.Validations.WriteAllowance`) says when to try again.
  defp write(conn, action, %{"fleet_id" => fleet_id} = params, fields) do
    input = Map.take(params, @command ++ fields)

    case action.(fleet_id, input, actor: conn.assigns.actor) do
      {:ok, written} -> json(conn, written)
      {:error, error} -> conn |> retry_after(error) |> refuse(error)
    end
  end

  defp retry_after(conn, %{errors: errors}) do
    case Enum.find(errors, &match?(%WriteLimitError{}, &1)) do
      %WriteLimitError{retry_after: seconds} ->
        put_resp_header(conn, "retry-after", Integer.to_string(seconds))

      nil ->
        conn
    end
  end

  defp refuse(conn, error) do
    {status, body} = WorkspaceRefusal.for_action_error(error)
    conn |> put_status(status) |> json(body)
  end
end
