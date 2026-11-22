defmodule RegentsWeb.Keyfleet.SharePictures do
  @moduledoc """
  The share pictures last drawn (`RegentsWeb.Keyfleet.ShareCard`), kept on this
  machine under `{fleet id, name, version}`: a fleet's own picture under the
  name `:fleet`, a project's under its name, and the version of what the
  picture shows. A new version is a new key, so a picture is drawn once for
  each version however often it is asked for, and one whose version has moved
  on is never read again and goes when the cache is swept. One picture is
  drawn by one request at a time, under the cache's own lock on its key
  (`transaction/2`): those asking for it meanwhile wait and take what that
  drawing kept.

  A picture is kept for an hour. A draw that failed, such as a Key's card that
  couldn't be read, is kept for a minute, so while the card's host doesn't
  answer each picture is asked for again at most once a minute however often
  a link preview requests it. How many are kept, and how often the expired
  ones are swept, is set in `config/config.exs`.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @kept :timer.hours(1)
  @failure_kept :timer.minutes(1)

  @type place :: {fleet_id :: String.t(), name :: :fleet | String.t(), version :: String.t()}
  @type drawing :: {:ok, binary()} | {:error, term()}

  @doc """
  The picture kept under `key`, or `draw`'s answer, kept: `{:ok, png}` or
  `{:error, reason}`.
  """
  @spec drawn(place(), (-> drawing())) :: drawing()
  def drawn(key, draw) do
    case get!(key) do
      nil -> drawn_once(key, draw)
      drawn -> drawn
    end
  end

  # Under the lock on `key`, which a request asking meanwhile waits on for as
  # long as the drawing takes, the picture is drawn only if it is still not
  # kept.
  defp drawn_once(key, draw) do
    {:ok, drawn} =
      transaction(fn -> get!(key) || draw_and_keep(key, draw) end,
        keys: [key],
        retries: :infinity
      )

    drawn
  end

  defp draw_and_keep(key, draw) do
    drawn = draw.()
    put!(key, drawn, ttl: kept(drawn))
    drawn
  end

  defp kept({:ok, _png}), do: @kept
  defp kept({:error, _reason}), do: @failure_kept
end
