defmodule Regents.Autolaunch.Supervisor do
  @moduledoc """
  Autolaunch's place in the site's supervision tree: deployment loading,
  shared caches (stocks list/price, sized images, DexScreener, CCA lists,
  Earn terms, public market listings, share card cache/pictures), background
  readers (`RegentFacts`, `CoveredCalls.Book`, `MarketTicker`,
  `LaunchDiscovery.Count`), and (when serving and not read-only) chain heads
  and covered-call price lines.
  """
  use Supervisor

  import Cachex.Spec, only: [expiration: 1, hook: 1]

  alias Regents.Autolaunch.{
    Chain,
    ChainHead,
    CoveredCalls,
    DexScreener,
    Earn,
    LaunchDiscovery,
    MarketTicker,
    RegentFacts,
    Stocks
  }

  alias Regents.Autolaunch.StoredImage.{Resizer, SizeCache}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    :ok = Regents.Autolaunch.load_deployments!()
    serving? = Keyword.get(opts, :serving?, false)

    children =
      [
        {SizeCache, max_size: 300, gc_memory_check_interval: :timer.seconds(3)},
        Resizer,
        Supervisor.child_spec(
          {Cachex,
           name: DexScreener.cache(),
           expiration: expiration(default: :timer.minutes(1), interval: :timer.seconds(10)),
           hooks: [hook(module: Cachex.Limit.Scheduled, args: {1_000, [], []})]},
          id: DexScreener.cache()
        ),
        Supervisor.child_spec(
          {Cachex,
           name: Chain.CcaLists.cache(),
           expiration: expiration(default: :timer.minutes(30), interval: :timer.minutes(1)),
           hooks: [hook(module: Cachex.Limit.Scheduled, args: {10_000, [], []})]},
          id: Chain.CcaLists.cache()
        ),
        Supervisor.child_spec({Cachex, name: Earn.SharedTerms.cache()},
          id: Earn.SharedTerms.cache()
        ),
        {Task.Supervisor, name: Regents.Autolaunch.TaskSupervisor},
        Stocks.MarketData,
        RegentFacts,
        CoveredCalls.Book,
        MarketTicker,
        Supervisor.child_spec({Cachex, name: Stocks.Assets.cache()},
          id: Stocks.Assets.cache()
        ),
        LaunchDiscovery.Count.children(),
        chain_reader_children(serving?)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp chain_reader_children(true) do
    if not Regents.read_only?(),
      do: ChainHead.children() ++ CoveredCalls.PriceLine.children()
  end

  defp chain_reader_children(false), do: nil
end
