defmodule Regents.Chain.Refresh do
  @moduledoc """
  Unified chain-refresh coordinator shared across Regents, Keyfleet, and Autolaunch.

  Each product keeps its own `:readers` list under
  `config :regents, Regents.Chain.Refresh, readers: %{...}` so a confirmed
  on-chain press or Refresh click in one product wakes only that product's
  chain readers and never fans out Alchemy/RPC calls to inactive products.

  Every reader implements `refresh/1` and enforces at least `gap_s/0` (10s)
  between requested reads so bursts coalesce into one read.
  """

  @doc "Reads the chain again soon, or at once."
  @callback refresh(chain_id :: pos_integer()) :: :ok | {:error, term()}

  @doc "The fewest seconds between two reads that were asked for."
  def gap_s, do: 10

  @doc """
  Asks every reader belonging to `product` (`:regents`, `:keyfleet`, or
  `:autolaunch`) for `chain_id` to read it again. Answers the first reader's
  refusal after every reader in that product has been asked.
  """
  @spec request(atom(), pos_integer()) :: :ok | {:error, term()}
  def request(product \\ :regents, chain_id)
      when is_atom(product) and is_integer(chain_id) and chain_id > 0 do
    readers_for(product)
    |> Enum.map(& &1.refresh(chain_id))
    |> Enum.find(:ok, &(&1 != :ok))
  end

  defp readers_for(product) do
    case Application.fetch_env!(:regents, __MODULE__)[:readers] do
      readers when is_map(readers) -> Map.get(readers, product, [])
      readers when is_list(readers) -> readers
    end
  end
end
