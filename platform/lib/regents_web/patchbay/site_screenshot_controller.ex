defmodule RegentsWeb.Patchbay.SiteScreenshotController do
  @moduledoc "Serves the picture Patchbay took of a site's page for its card."

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.Picture

  # A screenshot keeps no format: it is read from the picture's own bytes, and
  # anything but PNG, JPEG or WebP is not served (`Picture.send_picture/3`).
  def show(conn, %{"site_id" => site_id}) do
    case Forum.get_site_screenshot(site_id, load: [:site]) do
      {:ok, %{site: %{screenshot_path: path}} = screenshot} when is_binary(path) ->
        Picture.send_picture(conn, Picture.format(screenshot.image), screenshot.image)

      _missing_or_forgotten ->
        Picture.missing(conn)
    end
  end
end
