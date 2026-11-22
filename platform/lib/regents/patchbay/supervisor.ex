defmodule Regents.Patchbay.Supervisor do
  @moduledoc """
  Patchbay's domain supervision subtree: payments supervisor, Wallet Bench caches
  and board, hidden sites reading, site scan task supervisor, Assist Finch pool,
  hosted address cache, and boot-time WebMCP catalog sync (disabled in read-only
  mode).
  """
  use Supervisor

  alias Regents.Patchbay.{Agents, Assist, Forum, OperatorWallet, WalletBench}

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    :ok = OperatorWallet.attach()
    serving? = Keyword.get(opts, :serving?, false)
    db_enabled? = Application.get_env(:regents, :database_startup_enabled, false)

    children =
      [
        RegentPayments.Supervisor,
        Agents.HostedAddress,
        WalletBench.RunRecords,
        WalletBench.Board.builds(),
        {Task.Supervisor, name: Forum.SiteScan.tasks()},
        {Finch, name: Assist.Target.finch()},
        if(serving? and db_enabled?, do: WalletBench.Board),
        if(serving? and db_enabled?, do: Forum.HiddenSites),
        site_loader(serving?, db_enabled?)
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp site_loader(true, true) do
    if not Regents.read_only?() do
      {Task,
       fn ->
         Forum.Catalog.sync!()
         Forum.ProgramSites.make!()
       end}
    end
  end

  defp site_loader(_serving?, _db?), do: nil
end
