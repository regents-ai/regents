defmodule Regents.Autolaunch.Pool do
  @moduledoc """
  What a graduated Base token's page shows of its pool, read from the chain at
  one latest block: the pool's id, the owner of each position the launch
  locked and whether that owner is the launch's locker, and the price after
  every trade since the pool opened (`Regents.Autolaunch.PriceHistory`).

  Revstake launches graduate into a REGENT/SUBJECT pool recorded by their
  version's strategy (`distribution(auction)`) and locked in its LP locker;
  Memestock launches graduate into a NEW/STOCK pool recorded by their
  version's launchpad (`launches(id)`) and locked in its locker. Every read
  goes through `Regents.Chain.Rpc`, pinned to the block read first.

  One read makes, in order: `eth_chainId` and `eth_getBlockByNumber`; then a
  Revstake launch's `eth_call` of `distribution(address)` on its strategy, or
  a Memestock launch's `launchIdOfAuction(address)` and `launches(uint256)` on
  its launchpad; one `eth_call` of `ownerOf(uint256)` on Uniswap's position
  manager for each locked position (one for a Revstake launch, one or two for
  a Memestock launch); and one `eth_getLogs` on the PoolManager, read again as
  halves only for a span the node refuses. A failed call ends the read there.

  Nothing here writes or signs, and every figure is the chain's own answer;
  the token pages keep a read 15 seconds (`Regents.Autolaunch.PoolCache`).
  """

  alias Regents.Autolaunch.Chain.{Abi, Lifecycle}
  alias Regents.Autolaunch.{Lab, LabAbi, PriceHistory}
  alias Regents.Autolaunch.Stocks.Lab, as: StocksLab
  alias Regents.Autolaunch.Stocks.LabAbi, as: StocksLabAbi
  alias Regents.Chain.{Address, Rpc}

  @scope "autolaunch pool page"
  @regent_decimals 18

  # `ownerOf(uint256)` on Uniswap's position manager, which the pinned ABIs do
  # not carry.
  @owner_of_selector "0x6352211e"

  @type position :: %{owner: String.t(), locked?: boolean()}
  @type t :: %{
          pool_id: String.t(),
          positions: [position()],
          prices: PriceHistory.history() | nil
        }

  @doc "One graduated auction row's pool, or why it cannot be read."
  @spec read(map()) :: {:ok, t()} | {:error, atom()}
  def read(%{state: state}) when state != :graduated, do: {:error, :not_graduated}

  def read(%{kind: :agent} = auction) do
    with {:ok, config} <- Lab.current(),
         opts = Lab.rpc_opts(config, @scope),
         {:ok, block} <- Rpc.latest_block(opts),
         do: read_agent(auction, config, block, opts)
  end

  def read(%{kind: :stocks} = auction) do
    with {:ok, config} <- StocksLab.current(),
         opts = StocksLab.rpc_opts(config, @scope),
         {:ok, block} <- Rpc.latest_block(opts),
         do: read_stocks(auction, config, block, opts)
  end

  # Revstake

  # The strategy and LP locker are the launch's own version's.
  defp read_agent(auction, config, block, opts) do
    with {:ok, config} <- Lab.contracts(config, auction.contracts_version),
         {:ok, distribution} <- agent_distribution(auction, config, block, opts),
         {:ok, owner} <-
           owner_of(
             Lab.address!(config, :position_manager),
             distribution.lp_token_id,
             block,
             opts
           ),
         {:ok, prices} <-
           PriceHistory.pool(
             %{
               pool_manager: Lab.address!(config, :pool_manager),
               pool_id: distribution.pool_id,
               token_is_currency0?:
                 currency0?(distribution.subject, Lab.address!(config, :regent)),
               currency_decimals: @regent_decimals
             },
             distribution.migration_block,
             block,
             opts
           ) do
      {:ok,
       %{
         pool_id: distribution.pool_id,
         positions: [
           %{owner: owner, locked?: Address.equal?(owner, Lab.address!(config, :lp_locker))}
         ],
         prices: prices
       }}
    end
  end

  # The pool id is read first: until the strategy migrates the launch it is
  # zero, and the subject is read only once the pool exists.
  defp agent_distribution(auction, config, block, opts) do
    data =
      LabAbi.encode(Lab.abi!(config, :strategy), "distribution(address)", [
        auction.auction_address
      ])

    with {:ok, words} <-
           Rpc.call_words(
             Lab.address!(config, :strategy),
             data,
             block,
             LabAbi.distribution_words(),
             opts
           ),
         distribution = LabAbi.distribution(words),
         pool_id when pool_id != 0 <- distribution.pool_id,
         {:ok, subject} <- Abi.word_address(distribution.subject) do
      {:ok,
       %{
         pool_id: bytes32(pool_id),
         subject: subject,
         migration_block: distribution.migration_block,
         lp_token_id: distribution.lp_token_id
       }}
    else
      0 -> {:error, :not_graduated}
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  # Memestock

  # The launchpad and locker are the launch's own version's.
  defp read_stocks(auction, config, block, opts) do
    with {:ok, contracts} <- StocksLab.contracts(config, auction.contracts_version),
         {:ok, launch} <- stocks_launch(auction, contracts, block, opts),
         {:ok, positions} <-
           stocks_positions(
             StocksLab.address!(config, :position_manager),
             contracts.locker,
             launch.token_ids,
             block,
             opts
           ),
         {:ok, prices} <-
           PriceHistory.pool(
             %{
               pool_manager: StocksLab.address!(config, :pool_manager),
               pool_id: launch.pool_id,
               token_is_currency0?: currency0?(launch.new_token, launch.stock),
               currency_decimals: auction.quote_token_decimals
             },
             launch.migration_block,
             block,
             opts
           ) do
      {:ok, %{pool_id: launch.pool_id, positions: positions, prices: prices}}
    end
  end

  # A launch that has not graduated has no pool yet, so its record is read
  # only once its lifecycle says the pool exists.
  defp stocks_launch(auction, contracts, block, opts) do
    with {:ok, launch_id} <-
           Rpc.call_uint(
             contracts.launchpad,
             launchpad_call(contracts, "launchIdOfAuction(address)", [auction.auction_address]),
             block,
             opts
           ),
         {:ok, words} <-
           Rpc.call_words(
             contracts.launchpad,
             launchpad_call(contracts, "launches(uint256)", [launch_id]),
             block,
             contracts.record_words,
             opts
           ),
         record = StocksLabAbi.record(contracts, words),
         true <- Lifecycle.graduated?(record.lifecycle),
         {:ok, new_token} <- Abi.word_address(record.new_token),
         {:ok, stock} <- Abi.word_address(record.stock) do
      {:ok,
       %{
         new_token: new_token,
         stock: stock,
         migration_block: record.migration_block,
         pool_id: bytes32(record.pool_id),
         token_ids: [record.lp_token_id | second_position(contracts.version, record)]
       }}
    else
      false -> {:error, :not_graduated}
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  # Beside the full-range position, the first launchpad keeps a stock-only
  # position and the second and third a new-token-only one above the opening
  # price, each only when the launch made one.
  defp second_position(:v1, %{stock_only_token_id: token_id}) when token_id != 0, do: [token_id]

  defp second_position(version, %{new_only_token_id: token_id})
       when version in [:v2, :v3] and token_id != 0,
       do: [token_id]

  defp second_position(_version, _record), do: []

  # Every position belongs to the launchpad's locker, which never releases it.
  defp stocks_positions(manager, locker, token_ids, block, opts) do
    Enum.reduce_while(token_ids, {:ok, []}, fn token_id, {:ok, found} ->
      case owner_of(manager, token_id, block, opts) do
        {:ok, owner} ->
          {:cont, {:ok, found ++ [%{owner: owner, locked?: Address.equal?(owner, locker)}]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp launchpad_call(contracts, signature, arguments),
    do: LabAbi.encode(contracts.abis["launchpad"], signature, arguments)

  # Helpers

  defp owner_of(position_manager, token_id, block, opts) do
    Rpc.call_address(
      position_manager,
      @owner_of_selector <> (token_id |> Integer.to_string(16) |> String.pad_leading(64, "0")),
      block,
      opts
    )
  end

  defp currency0?(token, currency) do
    {:ok, token_bytes} = Address.decode(token)
    {:ok, currency_bytes} = Address.decode(currency)
    token_bytes < currency_bytes
  end

  defp bytes32(value) when is_integer(value),
    do:
      "0x" <> (value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0"))
end
