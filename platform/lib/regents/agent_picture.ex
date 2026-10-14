defmodule Regents.AgentPicture do
  @moduledoc """
  Turns a picture an owner uploads for their agent into the one kept for it: a
  256 × 256 WebP cut from the middle of the upload, carrying nothing else the
  file held (place, camera, colour notes). The shared agents library keeps it
  and takes a WebP of up to 64 KB only.
  """

  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  @side 256
  @max_upload 5_000_000
  @max_kept 65_536
  # A small file can still open into a huge picture; this bound is well above
  # any camera's.
  @max_pixels 100_000_000

  @doc "The largest upload taken, in bytes."
  def max_upload, do: @max_upload

  @doc """
  The picture kept for the upload `bytes`: `{:ok, webp}`, or `{:error, reason}`
  where reason is `:not_a_picture` (not a whole PNG, JPEG or WebP), `:too_big`
  (over 5 MB or 100 million pixels) or `:too_detailed` (still over 64 KB once
  made).
  """
  def make(bytes) when byte_size(bytes) > @max_upload, do: {:error, :too_big}

  def make(bytes) do
    with :ok <- known_kind(bytes),
         {:ok, picture} <- open(bytes),
         :ok <- within_pixels(picture),
         {:ok, square} <- square(bytes),
         {:ok, webp} <- Image.write_to_buffer(square, ".webp[Q=75,keep=none]") do
      kept(webp)
    end
  end

  # Read from the file's first bytes, so nothing else reaches the decoder.
  defp known_kind(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: :ok
  defp known_kind(<<0xFF, 0xD8, 0xFF, _::binary>>), do: :ok
  defp known_kind(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: :ok
  defp known_kind(_bytes), do: {:error, :not_a_picture}

  # Opening reads only the header, so the size is known before any decoding.
  defp open(bytes) do
    case Image.new_from_buffer(bytes) do
      {:ok, picture} -> {:ok, picture}
      {:error, _reason} -> {:error, :not_a_picture}
    end
  end

  defp within_pixels(picture) do
    if Image.width(picture) * Image.height(picture) <= @max_pixels,
      do: :ok,
      else: {:error, :too_big}
  end

  # Shrinks while decoding, so a large photo is never held whole. A file cut
  # off part-way is turned away rather than kept half grey.
  defp square(bytes) do
    case Operation.thumbnail_buffer(bytes, @side,
           height: @side,
           crop: :VIPS_INTERESTING_CENTRE,
           "option-string": "fail_on=truncated"
         ) do
      {:ok, square} -> {:ok, square}
      {:error, _reason} -> {:error, :not_a_picture}
    end
  end

  defp kept(webp) when byte_size(webp) <= @max_kept, do: {:ok, webp}
  defp kept(_webp), do: {:error, :too_detailed}
end
