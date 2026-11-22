defmodule RegentsWeb.Techtree.ProjectPackageController do
  @moduledoc """
  A delivered project's package, the exact bytes the team uploaded
  (`Regents.Techtree.Projects.Project`), as a file to save, at
  `/techtree/account/projects/:id/package`.

  It goes to the project's owner, signed in; a signed-out visitor is sent to the
  project's page, which offers the site's sign-in. A project that is someone
  else's, was withdrawn or never was is not found. When the database can't be
  read (`RegentsWeb.Techtree.Outage`) it answers 503 with the project page's
  words, never an error page. A paired agent downloads its person's through
  `RegentsWeb.Techtree.AgentAccountController`, sent the same way
  (`send_package/2`).
  """

  use RegentsWeb, :controller

  alias Regents.Account.Actors.Human
  alias Regents.Techtree.Projects
  alias RegentsWeb.Techtree.Outage

  def show(%{assigns: %{current_human_account: nil}} = conn, %{"id" => id}),
    do: redirect(conn, to: ~p"/techtree/account/projects/#{id}")

  def show(conn, %{"id" => id}) do
    actor = Human.for_account(conn.assigns.current_human_account)

    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %{} = project} <-
           Outage.read(fn -> Projects.get_my_package!(id, actor: actor) end) do
      send_package(conn, project)
    else
      :database_down ->
        conn
        |> put_resp_content_type("text/plain", "utf-8")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(503, "This project couldn’t be read. Refresh the page to try again.\n")

      _missing ->
        raise RegentsWeb.NotFoundError, "no project of yours has that id"
    end
  end

  @doc """
  Sends a project's package as a gzip file to save, never shown and never
  kept on the way (`no-store`, nosniff), under a name made of the title's
  plain letters and digits and the project's id (`file_name/1`).
  """
  # sobelow_skip ["XSS.SendResp"]
  @spec send_package(Plug.Conn.t(), Ash.Resource.record()) :: Plug.Conn.t()
  def send_package(conn, project) do
    conn
    |> put_resp_content_type("application/gzip", nil)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{file_name(project)}"))
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, project.package)
  end

  @doc "The name a project's package is saved under, such as `skill-uplift-1a2b3c4d.tar.gz`."
  @spec file_name(%{title: String.t(), id: String.t()}) :: String.t()
  def file_name(%{title: title, id: id}) do
    words =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.slice(0, 60)
      |> String.trim("-")

    [words, binary_part(id, 0, 8)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("-")
    |> Kernel.<>(".tar.gz")
  end
end
