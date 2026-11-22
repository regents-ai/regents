defmodule Regents.Autolaunch.Stocks.ListCache do
  @moduledoc """
  The stocks each chain's launchpad has admitted, as the database last
  answered, kept on this machine for a minute and shared by every page that
  asks (`Regents.Autolaunch.Stocks.Assets`). A failed read is not kept: the
  next reader reads again.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @kept :timer.minutes(1)

  @doc "The stocks kept under `key`, or `read`'s answer, kept a minute when it is `{:ok, stocks}`."
  @spec stocks(term(), (-> {:ok, list()} | {:error, term()})) :: {:ok, list()} | {:error, term()}
  def stocks(key, read), do: fetch_or_store(key, read, ttl: @kept)
end
