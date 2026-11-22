defmodule RegentsWeb.Patchbay.Supervisor do
  @moduledoc """
  Patchbay's web-side ETS/GenServer helpers, started only when the site is
  serving: x402 paid-call test replay table and post-form fix-check rate limit.
  """
  use Supervisor

  alias RegentsWeb.Patchbay.{FixCheckLimit, Plugs}

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Plugs.X402Test.replays(),
      FixCheckLimit
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
