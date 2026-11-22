defmodule RegentsWeb.Patchbay.ListedSitePictureController do
  @moduledoc "Serves the picture Patchbay took of a listed site's home page for its row on /patchbay/sites."

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.Picture

  # A listed site's picture keeps no format: it is read from the picture's own
  # bytes, and anything but PNG, JPEG or WebP is not served
  # (`Picture.send_picture/3`).
  def show(conn, %{"domain" => domain}) do
    case Forum.get_listed_site_picture(domain) do
      {:ok, picture} -> Picture.send_picture(conn, Picture.format(picture.image), picture.image)
      {:error, _not_found} -> Picture.missing(conn)
    end
  end
end
