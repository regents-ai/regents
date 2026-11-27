defmodule RegentsWeb.Techtree.AgentAccountController do
  @moduledoc """
  The current paired agent's reads of the projects Techtree's team delivered to
  its person, as their Projects pages show them
  (`RegentsWeb.Techtree.ProjectsLive`), with where to download each package:
  `/api/v1/techtree/account/projects`, `/:id` and `/:id/package`, behind the
  site's paired-agent check (`RegentsWeb.Account.PairedAgent`), which refuses
  as it does on every agent address. When the database can't be read
  (`RegentsWeb.Techtree.Outage`) each answers 503 `unavailable`.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.Projects
  alias RegentsWeb.Techtree.{ExactResponse, Outage, ProjectPackageController, ProjectsLive}

  # The person's projects, newest first.
  def projects(conn, _params) do
    case Outage.read(fn -> Projects.list_my_projects!(actor: conn.assigns.actor) end) do
      {:ok, projects} -> private_json(conn, %{projects: Enum.map(projects, &listed/1)})
      :database_down -> unavailable(conn)
    end
  end

  # One of the person's projects, with all its page shows.
  def project(conn, %{"id" => id}),
    do: own(conn, id, &Projects.get_my_project!/2, &private_json(&1, whole(&2)))

  # One of the person's projects' package, as the page's Download sends it.
  def package(conn, %{"id" => id}),
    do:
      own(
        conn,
        id,
        &ProjectPackageController.read_package/2,
        &ProjectPackageController.send_package/2
      )

  # The address's id is read only as a UUID; anything else is no project.
  defp own(conn, id, read, answer) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %{} = project} <- Outage.read(fn -> read.(id, actor: conn.assigns.actor) end) do
      answer.(conn, project)
    else
      :database_down -> unavailable(conn)
      _missing -> project_not_found(conn)
    end
  end

  @doc "Canonical summary projection of a delivered Techtree project."
  @spec listed(map()) :: map()
  def listed(project) do
    %{
      id: project.id,
      title: project.title,
      service: project.line,
      verdict: project.verdict,
      verdict_name: ProjectsLive.verdict_name(project.verdict),
      delivered_at: project.delivered_at,
      url: url(~p"/techtree/account/projects/#{project.id}")
    }
  end

  @doc "Canonical full projection of a delivered Techtree project (`uplift-package/1` and `/2`)."
  @spec whole(map()) :: map()
  def whole(project) do
    manifest = project.manifest || %{}

    project
    |> listed()
    |> Map.merge(%{
      schema: manifest["schema"],
      success: manifest["success"],
      summary: manifest["summary"] && Map.delete(manifest["summary"], "cost_cents"),
      cases: manifest["cases"],
      selection: manifest["selection"],
      setup: manifest["setup"],
      rerun_test: manifest["rerun_test"],
      files: manifest["files"],
      report_md: project.report_md,
      package: %{
        size_bytes: project.package_size,
        sha256: project.package_sha256,
        url: url(~p"/api/v1/techtree/account/projects/#{project.id}/package")
      }
    })
  end

  defp project_not_found(conn),
    do:
      ExactResponse.send_error(
        conn,
        404,
        :project_not_found,
        "Your person has no project with that id.",
        "List their projects at #{url(~p"/api/v1/techtree/account/projects")}."
      )

  defp private_json(conn, answer),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(answer)

  defp unavailable(conn),
    do:
      ExactResponse.send_error(
        conn,
        503,
        :unavailable,
        "That could not be reached right now.",
        "Try again in a moment."
      )
end
