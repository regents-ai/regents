defmodule Regents.Autolaunch.Supervisor do
  @moduledoc """
  Autolaunch's place in the site's supervision tree. It reads the deployment
  descriptions as it starts (`Regents.Autolaunch.load_deployments!/0`), so a
  malformed one stops the site's start, as it stopped autolaunch.sh's, and
  every later read is answered from memory. Its children are the two caches
  behind the dollar figures: each chain's stocks, kept a minute
  (`Stocks.ListCache`), and each stock's feed price, kept ten minutes
  (`Stocks.PriceCache`); older entries leave with the generation each cache's
  collector drops every ten minutes. Then the launch pictures' sized copies
  (`StoredImage.SizeCache`): a check every three seconds that counts 300 or
  more drops the older generation of copies and makes the newer one the older,
  and a copy asked for again moves back to the newer. Last, the one maker of
  them (`StoredImage.Resizer`).
  """
  use Supervisor

  alias Regents.Autolaunch.Stocks.{ListCache, PriceCache}
  alias Regents.Autolaunch.StoredImage.{Resizer, SizeCache}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ok = Regents.Autolaunch.load_deployments!()

    Supervisor.init(
      [
        {ListCache, gc_interval: :timer.minutes(10)},
        {PriceCache, gc_interval: :timer.minutes(10)},
        {SizeCache, max_size: 300, gc_memory_check_interval: :timer.seconds(3)},
        Resizer
      ],
      strategy: :one_for_one
    )
  end
end
