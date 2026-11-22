defmodule Regents.Autolaunch.StoredImage do
  @moduledoc """
  The launch images autolaunch.sh stored, named by the address it gave each
  one: `/images/<id>/<digest>` for a Revstake draft's image and
  `/stock-images/<id>/<digest>` for a Memestock draft's, on any host. A
  launch's record keeps that address as autolaunch.sh gave it; this site reads
  the lane, id and digest from it (`key/1`) and serves the image itself.

  Pages show each image at the size they draw it: a square of that width cut
  from the image's centre, never enlarged, made the first time it is asked
  for (one at a time, by `Regents.Autolaunch.StoredImage.Resizer`) and kept in
  memory (`Regents.Autolaunch.StoredImage.SizeCache`). The large pictures offer
  two widths and the browser takes the one the screen needs.
  """

  alias Regents.Autolaunch.StoredImage.{Resizer, SizeCache}

  @lanes ["images", "stock-images"]
  @digest ~r/\A[0-9a-f]{64}\z/
  # Twice the largest size a page draws each kind of picture at: 96 for the
  # list icons (up to 48 pixels), 640 for the cards (up to about 320), and 320
  # for those on a phone, where they are drawn at about 150 to 200.
  @widths [96, 320, 640]

  @type key :: {String.t(), String.t(), String.t()}
  @type width :: 96 | 320 | 640

  @doc "The width a sized copy's file name asks for, as 320 for `320.webp`, or `:error`."
  @spec width(String.t()) :: {:ok, width()} | :error
  def width(name), do: Enum.find_value(@widths, :error, &(name == "#{&1}.webp" && {:ok, &1}))

  @doc "The lane, id and digest an address names, or `:error` for any other address."
  @spec key(String.t()) :: {:ok, key()} | :error
  def key(url) when is_binary(url) do
    with %URI{path: path} when is_binary(path) <- URI.parse(url),
         [lane, id, digest] <- String.split(path, "/", trim: true) do
      key(lane, id, digest)
    else
      _other -> :error
    end
  end

  @doc """
  The key of the image stored in `lane` (`images` or `stock-images`) under
  `id`, a UUID, and `digest`, 64 lowercase hex digits; `:error` for anything
  else.
  """
  @spec key(String.t(), String.t(), String.t()) :: {:ok, key()} | :error
  def key(lane, id, digest) when lane in @lanes do
    with {:ok, id} <- Ecto.UUID.cast(id),
         true <- Regex.match?(@digest, digest) do
      {:ok, {lane, id, digest}}
    else
      _other -> :error
    end
  end

  def key(_lane, _id, _digest), do: :error

  @doc "The image `key` names as stored: its type and bytes, or `:error` when none is."
  @spec original(key()) :: {:ok, %{content_type: String.t(), bytes: binary()}} | :error
  def original({lane, id, digest}) do
    case read(lane, id, digest) do
      {:ok, %{content_type: type, bytes: bytes}} -> {:ok, %{content_type: type, bytes: bytes}}
      _missing -> :error
    end
  end

  @doc "The WebP square `width` pixels wide of the stored image `key` names, or `:error`."
  @spec sized_bytes(key(), width()) :: {:ok, binary()} | :error
  def sized_bytes({_lane, _id, _digest} = key, width) when width in @widths do
    case SizeCache.copy(key, width) do
      nil -> Resizer.webp(key, width, fn -> stored_bytes(key) end)
      webp -> {:ok, webp}
    end
  end

  defp stored_bytes(key) do
    with {:ok, %{bytes: bytes}} <- original(key), do: {:ok, bytes}
  end

  defp read("images", id, digest),
    do: Regents.Autolaunch.get_public_launch_draft_image(id, digest, actor: nil)

  defp read("stock-images", id, digest),
    do: Regents.Autolaunch.get_public_stock_launch_draft_image(id, digest, actor: nil)
end
