defmodule Regents.Autolaunch.StoredImage.SizeCache do
  @moduledoc """
  The sized copies of the stored launch images
  (`Regents.Autolaunch.StoredImage`), kept on this machine under the image's
  lane, id and digest and the copy's width. An image never changes under its
  address, so a copy is kept until the cache is full: every three seconds it
  counts what it keeps, and at 300 or more it drops the older of its two
  generations whole, whatever that holds. A copy asked for again moves to the
  newer one, so the copies the pages show stay.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @doc "The copy of `key` at `width` kept, or nil."
  @spec copy(term(), pos_integer()) :: binary() | nil
  def copy(key, width), do: get!({key, width})

  @doc "Keeps `webp` as the copy of `key` at `width`."
  @spec keep(term(), pos_integer(), binary()) :: :ok
  def keep(key, width, webp), do: put!({key, width}, webp)
end
