defmodule Regents.Autolaunch.StoredImage do
  @moduledoc """
  The launch images autolaunch.sh stores, named by the address it gave each
  one: `/images/<id>/<digest>` for a Revstake draft's image and
  `/stock-images/<id>/<digest>` for a Memestock draft's, on the host that
  stored it, which the address names.

  Pages show each image at the size they draw it, from
  `<address>/<width>.webp`: a square of that width cut from the image's
  centre, made and served by that host. The large pictures offer two widths
  and the browser takes the one the screen needs.

  A launch's image is whatever address its record holds. A page draws one
  only from an `https` address with a host; for anything else it shows the
  name's first letter.
  """

  @digest ~r/\A[0-9a-f]{64}\z/
  # Twice the largest size a page draws each kind of picture at: 96 for the
  # list icons (up to 48 pixels), 640 for the cards (up to about 320), and 320
  # for those on a phone, where they are drawn at about 150 to 200.
  @widths [96, 320, 640]
  @choices [320, 640]

  @type width :: 96 | 320 | 640

  @doc """
  Where a page shows the image at `width`: a stored image's sized copy, and
  any other address a page may draw, such as one on another site, as it is.
  Nil for a launch with no image and for an address a page does not draw.
  """
  @spec sized(String.t() | nil, width()) :: String.t() | nil
  def sized(url, width) when width in @widths do
    case drawn(url) do
      nil -> nil
      uri -> if stored?(uri), do: copy(uri, width), else: url
    end
  end

  @doc """
  The widths a large picture's browser chooses from, as an `<img>`'s
  `srcset`, beside `sized(url, 640)` as its `src`; nil for an address that
  is not a stored image.
  """
  @spec choices(String.t() | nil) :: String.t() | nil
  def choices(url) do
    uri = drawn(url)
    if uri && stored?(uri), do: Enum.map_join(@choices, ", ", &"#{copy(uri, &1)} #{&1}w")
  end

  # The address as a page may draw it: `https`, with a host.
  defp drawn(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host} = uri} when is_binary(host) and host != "" -> uri
      _other -> nil
    end
  end

  defp drawn(_url), do: nil

  defp copy(%URI{path: path} = uri, width),
    do: URI.to_string(%{uri | path: path <> "/#{width}.webp"})

  # Whether an address names a stored image by its lane, id and digest, and
  # nothing after them: a query or a fragment would end up inside `srcset`.
  defp stored?(%URI{path: path, query: nil, fragment: nil}) when is_binary(path) do
    with [lane, id, digest] when lane in ["images", "stock-images"] <-
           String.split(path, "/", trim: true),
         {:ok, _id} <- Ecto.UUID.cast(id) do
      Regex.match?(@digest, digest)
    else
      _other -> false
    end
  end

  defp stored?(_uri), do: false
end
