defmodule Regents.Autolaunch.StoredImage.Resizer do
  @moduledoc """
  Makes the sized copies of stored images one at a time. A large image can
  take over a hundred megabytes to decode, so however many copies are asked
  for at once, only one is being made. Each request carries the moment its
  caller stops waiting and the read of the stored image; a request whose turn
  comes after that moment is skipped. At its turn a copy another request in
  the line has made is answered from `Regents.Autolaunch.StoredImage.SizeCache`,
  so no copy is made twice; only then is the image read, so the requests
  waiting hold no image. Each copy made is kept there. A second after its last
  request the maker hibernates, which lets go of the images it read.
  """

  use GenServer

  alias Regents.Autolaunch.StoredImage.SizeCache
  alias Vix.Vips.Operation

  @quality 80
  @timeout :timer.seconds(10)

  def start_link(_options) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__, hibernate_after: :timer.seconds(1))
  end

  @doc """
  The copy of `key` at `width`: a WebP square `width` pixels wide cut from the
  centre of the image `read` answers, never enlarged, keeping only the colour
  profile; `:error` when `read` finds none or the copy cannot be made within
  ten seconds.
  """
  @spec webp(term(), pos_integer(), (-> {:ok, binary()} | :error)) :: {:ok, binary()} | :error
  def webp(key, width, read) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    GenServer.call(__MODULE__, {:webp, key, width, read, deadline}, @timeout)
  catch
    # A call that waits past its timeout exits its caller; the copy was not made in time.
    :exit, _reason -> :error
  end

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call({:webp, key, width, read, deadline}, _from, state) do
    if System.monotonic_time(:millisecond) < deadline do
      {:reply, kept_or_made(key, width, read), state}
    else
      {:reply, :error, state}
    end
  end

  defp kept_or_made(key, width, read) do
    case SizeCache.copy(key, width) do
      nil -> made(key, width, read)
      webp -> {:ok, webp}
    end
  end

  defp made(key, width, read) do
    with {:ok, bytes} <- read.(),
         {:ok, image} <-
           Operation.thumbnail_buffer(bytes, width,
             height: width,
             crop: :VIPS_INTERESTING_CENTRE,
             size: :VIPS_SIZE_DOWN
           ),
         {:ok, webp} <-
           Operation.webpsave_buffer(image, Q: @quality, keep: [:VIPS_FOREIGN_KEEP_ICC]) do
      :ok = SizeCache.keep(key, width, webp)
      {:ok, webp}
    else
      _failed -> :error
    end
  end
end
