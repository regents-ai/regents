defmodule RegentsWeb.Autolaunch.Supervisor do
  @moduledoc """
  Autolaunch's web-side shared caches, started only when the site is serving:
  share card cache and market pictures, plus the short-lived market API answer
  cache.
  """
  use Supervisor

  import Cachex.Spec, only: [expiration: 1, hook: 1]

  alias RegentsWeb.Autolaunch.{MarketAnswer, ShareCard}

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      ShareCard.Cache,
      ShareCard.MarketPictures,
      Supervisor.child_spec(
        {Cachex,
         name: MarketAnswer.cache(),
         expiration: expiration(default: :timer.seconds(5), interval: :timer.seconds(1)),
         hooks: [hook(module: Cachex.Limit.Scheduled, args: {1_000, [], []})]},
        id: MarketAnswer.cache()
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
