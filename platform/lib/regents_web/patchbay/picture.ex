defmodule RegentsWeb.Patchbay.Picture do
  @moduledoc """
  How Patchbay's stored pictures are sent: a post's pictures, and the
  pictures Patchbay took of a site's page and of a listed site's home page.
  Only a PNG, JPEG or WebP picture is sent, as its own type; anything else
  is not there (404), so a row written some other way is never served as
  another type. Shared caches keep a picture five minutes, so it does not
  outlive its post's hiding by long. The site's own headers, the reading
  policy, frame and nosniff among them, come with every answer
  (`RegentsWeb.Endpoint`).
  """

  import Plug.Conn

  @formats [:png, :jpeg, :webp]

  @doc "Sends `image` as a picture of `format`; any format but PNG, JPEG or WebP is a 404."
  @spec send_picture(Plug.Conn.t(), atom() | nil, binary()) :: Plug.Conn.t()
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  def send_picture(conn, format, image) when format in @formats do
    conn
    |> put_resp_content_type("image/#{format}", nil)
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(200, image)
  end

  def send_picture(conn, _format, _image), do: missing(conn)

  @doc "The answer for a picture that is not there, or not public."
  @spec missing(Plug.Conn.t()) :: Plug.Conn.t()
  def missing(conn), do: send_resp(conn, 404, "")

  @doc """
  The format of a picture kept without one, read from its first bytes as a
  post's picture's is when it is added; nil for anything else.
  """
  @spec format(binary()) :: :png | :jpeg | :webp | nil
  def format(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: :png
  def format(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: :jpeg
  def format(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>), do: :webp
  def format(_other), do: nil
end
