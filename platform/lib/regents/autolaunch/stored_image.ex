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
  any other address, such as one on IPFS or another site, as it is.
  """
  @spec sized(String.t(), width()) :: String.t()
  def sized(url, width) when is_binary(url) and width in @widths do
    if stored?(url) do
      uri = URI.parse(url)
      URI.to_string(%URI{uri | path: uri.path <> "/#{width}.webp"})
    else
      url
    end
  end

  @doc """
  The widths a large picture's browser chooses from, as an `<img>`'s
  `srcset`, beside `sized(url, 640)` as its `src`; nil for an address that
  is not a stored image, which is shown as it is.
  """
  @spec choices(String.t()) :: String.t() | nil
  def choices(url) when is_binary(url) do
    if stored?(url), do: Enum.map_join(@choices, ", ", &"#{sized(url, &1)} #{&1}w")
  end

  # Whether an address names a stored image by its lane, id and digest.
  defp stored?(url) do
    with %URI{path: path} when is_binary(path) <- URI.parse(url),
         [lane, id, digest] when lane in ["images", "stock-images"] <-
           String.split(path, "/", trim: true),
         {:ok, _id} <- Ecto.UUID.cast(id) do
      Regex.match?(@digest, digest)
    else
      _other -> false
    end
  end
end
