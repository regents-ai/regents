defmodule RegentsWeb.Keyfleet.AgentTools.Projects.Answer do
  @moduledoc """
  What a fleet's projects (`Regents.Keyfleet.Projects`) answer an agent, the same over
  its signed requests (`RegentsWeb.Keyfleet.AgentProjectController`) and as the
  Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Projects`): listing them,
  active ones first, with which one the agent's own Key works on and which
  Key started each; and, as a Key, starting, archiving, taking over and
  deleting one it started, and giving one it holds its one-line description
  and choosing whether its page shows its work to everyone. New work goes
  into any active project, whoever holds it.
  Each answer is `{status, body, nil}`; `params` is the signed request's
  JSON, its body with the names in its address (`fleet_id`, `project`).
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Code, Fleets, Keys, Projects}
  alias Regents.Keyfleet.Graph.Errors.{CheckExpiredError, EditsRestrictedError}
  alias Regents.Keyfleet.Graph.Errors.{NotKeyHolderError, UnknownFleetError}
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects.Errors.{HoldError, NameTakenError, UnknownProjectError}
  alias RegentsWeb.Keyfleet.Refusal

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(:list, %{"fleet_id" => fleet_id}, actor, _waiter) do
    with {:ok, %{}} <- Fleets.get_fleet(fleet_id, actor: %System{}),
         {:ok, projects} <- Projects.by_state(fleet_id, actor: actor) do
      key = your_key(actor, fleet_id)
      yours = Enum.find(projects, &yours?(&1, key))

      {200,
       %{
         your_key: key,
         your_project: yours && yours.name,
         projects: Enum.map(projects, &project(&1, key))
       }, nil}
    else
      {:ok, nil} -> {404, Refusal.body("fleet_unknown"), nil}
      {:error, error} -> refuse(fleet_id, error)
    end
  end

  def answer(:start, %{"fleet_id" => fleet_id, "as_key" => key} = params, actor, _waiter),
    do:
      held(
        fleet_id,
        &Projects.start_project(fleet_id, key, params["name"], params["title"], &1),
        actor
      )

  def answer(:archive, %{"fleet_id" => fleet_id, "as_key" => key}, actor, _waiter),
    do: held(fleet_id, &Projects.archive_project(fleet_id, key, &1), actor)

  def answer(:take_over, %{"fleet_id" => fleet_id, "project" => name, "as_key" => key}, actor, _),
    do: held(fleet_id, &Projects.take_over_project(fleet_id, key, name, &1), actor)

  def answer(:delete, %{"fleet_id" => fleet_id, "project" => name, "as_key" => key}, actor, _),
    do: held(fleet_id, &Projects.delete_project(fleet_id, key, name, &1), actor)

  # null or an empty line takes the description away.
  def answer(:describe, %{"fleet_id" => fleet_id, "project" => name} = params, actor, _waiter),
    do:
      held(
        fleet_id,
        &Projects.describe_project(fleet_id, params["as_key"], name, params["description"], &1),
        actor
      )

  def answer(:show, %{"fleet_id" => fleet_id, "project" => name} = params, actor, _waiter),
    do:
      held(
        fleet_id,
        &Projects.show_project(
          fleet_id,
          params["as_key"],
          name,
          params["shown_to_everyone"],
          &1
        ),
        actor
      )

  defp held(fleet_id, step, actor) do
    case step.(actor: actor) do
      {:ok, project} -> {200, %{project: project(project, your_key(actor, fleet_id))}, nil}
      {:error, error} -> refuse(fleet_id, error)
    end
  end

  # The Key the agent acts as in the fleet, or nil.
  defp your_key(actor, fleet_id),
    do: with(%{token_id: token_id} <- Keys.identity(actor, fleet_id), do: token_id)

  # A Key's own project is the active one it holds; with no Key, none is.
  defp yours?(_project, nil), do: false
  defp yours?(project, key), do: project.state == :active and project.key == key

  defp project(project, key) do
    %{
      name: project.name,
      title: project.title,
      description: project.description,
      key: project.key,
      created_by_key: project.created_by_key,
      state: project.state,
      shown_to_everyone: project.shown_to_everyone,
      yours: yours?(project, key),
      clone_url: Code.agent_clone_url(project.repository)
    }
  end

  defp refuse(fleet_id, %Ash.Error.Forbidden{}) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: {403, Refusal.body("not_a_key_holder"), nil},
      else: {503, Refusal.body("ownership_refreshing"), nil}
  end

  defp refuse(_fleet_id, %{errors: errors}) do
    {status, body} = Enum.find_value(errors, &named/1) || {422, Refusal.body("project_invalid")}
    {status, body, nil}
  end

  defp named(%HoldError{code: code, words: words}) do
    code = "project_#{code}"
    status = if code in ["project_not_holder", "project_not_creator"], do: 403, else: 409
    {status, put_in(Refusal.body(code), [:error, :message], words)}
  end

  defp named(%NameTakenError{} = error),
    do:
      {409,
       put_in(Refusal.body("project_name_taken"), [:error, :message], Exception.message(error))}

  defp named(%UnknownProjectError{}), do: {404, Refusal.body("project_unknown")}
  defp named(%UnknownFleetError{}), do: {404, Refusal.body("fleet_unknown")}
  defp named(%OwnershipRefreshingError{}), do: {503, Refusal.body("ownership_refreshing")}
  defp named(%NotKeyHolderError{}), do: {403, Refusal.body("not_a_key_holder")}
  defp named(%EditsRestrictedError{}), do: {403, Refusal.body("edits_restricted")}
  defp named(%CheckExpiredError{}), do: {503, Refusal.body("graph_unavailable")}
  defp named(_error), do: nil
end
