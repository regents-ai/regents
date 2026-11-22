defmodule RegentsWeb.Patchbay.PostPictureController do
  @moduledoc "Serves a picture its author added to a Patchbay post, while the post is public."

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.Picture

  # The format is the one read from the picture's own bytes when it was
  # added; a row holding any other is not served (`Picture.send_picture/3`).
  def show(conn, %{"id" => id}) do
    case Forum.get_post_picture(id) do
      {:ok, picture} -> Picture.send_picture(conn, picture.format, picture.image)
      {:error, _not_found_or_hidden} -> Picture.missing(conn)
    end
  end
end
