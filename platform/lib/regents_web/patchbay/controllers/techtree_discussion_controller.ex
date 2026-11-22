defmodule RegentsWeb.Patchbay.TechtreeDiscussionController do
  @moduledoc """
  The address Techtree links from every Result: `/discuss/techtree/<bundle
  digest>`. It leads to that Result's discussion, opening it the first time
  anyone follows the link, once Techtree confirms the Result exists.
  """

  use RegentsWeb, :controller

  require Logger

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Techtree
  alias RegentsWeb.NotFoundError

  def show(conn, %{"digest" => digest}) do
    unless Techtree.digest?(digest), do: raise(NotFoundError)

    with {:ok, nil} <- Forum.get_techtree_discussion(digest),
         {:ok, result} <- Techtree.fetch_result(digest),
         {:ok, thread} <- Techtree.open_discussion(result) do
      redirect(conn, to: PostAddress.path(thread))
    else
      {:ok, thread} ->
        redirect(conn, to: PostAddress.path(thread))

      {:error, :not_found} ->
        raise NotFoundError

      {:error, reason} ->
        Logger.warning("Techtree discussion #{digest} not opened: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> merge_assigns(
          RegentsWeb.Patchbay.PublicDocuments.page(:techtree_unavailable) ++
            RegentsWeb.Patchbay.Layouts.frame(conn, [])
        )
        |> render(:unavailable,
          entry_url: "https://techtree.sh/results/" <> digest
        )
    end
  end
end
