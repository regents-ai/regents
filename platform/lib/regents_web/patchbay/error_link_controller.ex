defmodule RegentsWeb.Patchbay.ErrorLinkController do
  @moduledoc """
  A lasting link for each of Regents' own errors, `/patchbay/errors/<code>`,
  such as `/patchbay/errors/not_signed_in`. The Regents command line and
  sites print it beside the error, and it leads to the post that explains
  that error and how to clear it. The post may move or be replaced; the
  printed link stays the same.

  Which post each code leads to is the one table, `@links` below: a code and
  a post id per line. A code with no post, or whose post is gone or held out
  of sight, is a missing page that offers a search for the code instead.
  Anything that cannot be a code (lowercase letters, digits and underscores,
  at most 64) is the site's ordinary missing page, which repeats nothing of
  the address.
  """

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum.PostAddress
  alias RegentsWeb.Patchbay.ErrorLinkHTML
  alias RegentsWeb.Patchbay.ErrorLinkMD
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  plug :put_view, html: ErrorLinkHTML, md: ErrorLinkMD

  @links %{
    "not_signed_in" => "bc85f337-9965-4a8c-9a4e-ea875b3a55ce",
    "agent_not_paired" => "54444861-6b25-4918-abb9-dd6f98b76380",
    "person_not_here" => "d6a3cc57-124c-41ff-a8fb-bc7d2b1095cc",
    "no_touch_id" => "f308a148-c8af-47ea-845d-7c402c07c76d",
    "key_helper_not_answering" => "f308a148-c8af-47ea-845d-7c402c07c76d",
    "locked_key_needs_mac" => "f308a148-c8af-47ea-845d-7c402c07c76d",
    "code_sign_in" => "4a53f1bb-e031-4142-b268-cfe32a1619f0"
  }

  def show(conn, %{"code" => code}) do
    unless code =~ ~r/\A[a-z0-9_]{1,64}\z/, do: raise(RegentsWeb.NotFoundError)

    with {:ok, id} <- Map.fetch(@links, code),
         {:ok, post} <- Board.fetch_report(id) do
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: PostAddress.path(post))
    else
      :error ->
        conn
        |> put_status(:not_found)
        |> merge_assigns(PublicDocuments.page(:unknown_error) ++ Layouts.frame(conn, []))
        |> render(:unknown, code: code)

      {:error, failure} ->
        raise failure
    end
  end
end
