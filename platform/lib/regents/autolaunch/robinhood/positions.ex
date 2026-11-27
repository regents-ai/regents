defmodule Regents.Autolaunch.Robinhood.Positions do
  @moduledoc """
  The bids the signed-in wallet holds on Robinhood memestock auctions, read
  from the chain each time they are asked.

  Nothing about these bids is stored: the launchpad names every auction, each
  auction's own `BidSubmitted` logs name the wallet's bids, and `bids(bidId)`
  says where each bid stands now. Everything is read at one latest block, and
  only the wallet the session signed in with is read. Each
  position carries the site's listing of its auction when there is one, and
  once that auction has launched, its listed token: only listed auctions and
  tokens have a page here.

  Where a bid stands follows the auction's own rules. While bidding is open the
  bid is in the auction. Once bidding has ended, the bid waits until the
  launch is finished, since the raise is not final before then. Once the
  launch has failed, an un-exited bid is refundable in full. Once it has
  graduated, an un-exited bid
  still has whatever it did not spend to come back, an amount only the exit
  itself states. An exited bid with tokens filled can claim them from the
  claim block. After a claim clears the stored fill, a positive `TokensClaimed`
  event distinguishes a claimed bid from one returned with nothing filled.
  """

  alias RegentChain.Address
  alias Regents.Account.Actors.System
  alias Regents.Autolaunch.{AuctionBook, LabAbi}
  alias Regents.Autolaunch.Chain.{Abi, CcaSettlement, Multicall, Rpc}
  alias Regents.Autolaunch.Robinhood.{Lab, Launchpad}
  alias Regents.Autolaunch.Stocks.Amounts

  @bid_record_words 7
  @token_decimals 18
  @q96_bits 96

  @type standing ::
          Regents.Autolaunch.AuctionBook.standing()
          | :ended
          | :refundable
          | :graduated
          | :returned
          | :filled
          | :claimable
          | :claimed

  @type position :: %{
          auction: String.t(),
          name: String.t(),
          symbol: String.t(),
          image: String.t() | nil,
          stock_symbol: String.t(),
          bid_id: String.t(),
          wallet: String.t(),
          committed: String.t(),
          max_price: String.t(),
          standing: standing(),
          refundable: String.t() | nil,
          claim_block: non_neg_integer() | nil,
          listing: Regents.Autolaunch.Auction.t() | nil,
          token: Regents.Autolaunch.Token.t() | nil
        }

  @doc """
  Every Robinhood bid the signed-in wallet holds, newest auction first. The
  caller reads the wallet from the verified session.
  """
  @spec read_wallet(String.t()) :: {:ok, [position()]} | {:error, :unavailable}
  def read_wallet(wallet) when is_binary(wallet) do
    with {:ok, positions} <- positions(wallet),
         {:ok, listings} <- listings(positions) do
      {:ok, Enum.map(positions, &Map.merge(&1, Map.fetch!(listings, &1.auction)))}
    else
      _error -> {:error, :unavailable}
    end
  end

  defp positions(wallet) do
    if Lab.configured?(), do: read_positions(wallet), else: {:ok, []}
  end

  # The site's listing of each auction the positions are in, hidden ones
  # included so their bids can still be settled, and its launched token, each
  # nil where the site lists none or the auction is hidden.
  defp listings(positions) do
    positions
    |> Enum.map(& &1.auction)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn auction, {:ok, found} ->
      with {:ok, listing} <-
             Regents.Autolaunch.get_held_robinhood_auction(auction, actor: %System{}),
           {:ok, token} <- listed_token(listing) do
        {:cont, {:ok, Map.put(found, auction, %{listing: listing, token: token})}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp listed_token(%{hidden: true}), do: {:ok, nil}

  defp listed_token(%{state: :graduated, token_address: token}),
    do: Regents.Autolaunch.get_robinhood_token(token, actor: nil)

  defp listed_token(_listing), do: {:ok, nil}

  defp read_positions(wallet) do
    with {:ok, head} <- Launchpad.head(),
         {:ok, auctions} <- Launchpad.auctions(head) do
      pinned_positions(auctions, wallet, Map.put(head, :abi, Lab.abi!(head.config, :auction)))
    end
  end

  # Log ranges use block numbers; refuse a history that moved since the state
  # reads pinned its hash.
  defp pinned_positions(auctions, wallet, venue) do
    with {:ok, positions} <-
           collect(auctions, &wallet_positions(&1, wallet, venue)),
         {:ok, %{"hash" => hash}} <-
           Rpc.request(
             "eth_getBlockByNumber",
             ["0x" <> Integer.to_string(venue.block.number, 16), false],
             venue.opts
           ),
         true <- hash == venue.block.hash do
      {:ok, positions}
    else
      _error -> {:error, :invalid_chain_response}
    end
  end

  defp wallet_positions(auction, wallet, venue) do
    with {:ok, bids} <- wallet_bids(auction.auction, wallet, venue),
         do: bid_positions(bids, auction, wallet, venue)
  end

  # Every list in order, or the first read that failed.
  defp collect(items, read) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, found} ->
      case read.(item) do
        {:ok, positions} -> {:cont, {:ok, found ++ positions}}
        error -> {:halt, error}
      end
    end)
  end

  # Read every bid issued by the auction directly from storage via Multicall3
  # at the pinned block hash instead of scanning `eth_getLogs` from block 0
  # (Robinhood mainnet rejects log spans above 10M blocks and rate-limits
  # multi-chunk scans).
  defp wallet_bids(auction, wallet, venue) do
    with {:ok, next_bid_id} <-
           Rpc.call_uint(
             auction,
             LabAbi.encode(venue.abi, "nextBidId()", []),
             venue.block,
             venue.opts
           ) do
      read_bids(auction, next_bid_id, wallet, venue)
    end
  end

  defp read_bids(_auction, 0, _wallet, _venue), do: {:ok, []}

  defp read_bids(auction, next_bid_id, wallet, venue) do
    reads =
      for bid_id <- 0..(next_bid_id - 1) do
        {auction, LabAbi.encode(venue.abi, "bids(uint256)", [bid_id])}
      end

    with {:ok, raw_bids} <- Multicall.read(reads, venue.block, venue.opts) do
      decode_wallet_bids(raw_bids, wallet)
    end
  end

  defp decode_wallet_bids(raw_bids, wallet) do
    raw_bids
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {raw, bid_id}, {:ok, kept} ->
      keep_wallet_bid(raw, bid_id, wallet, kept)
    end)
    |> case do
      {:ok, bids} -> {:ok, Enum.reverse(bids)}
      error -> error
    end
  end

  defp keep_wallet_bid(raw, bid_id, wallet, kept) do
    case decode_bid_record(raw, bid_id) do
      {:ok, %{owner: owner} = bid} ->
        if Address.equal?(owner, wallet),
          do: {:cont, {:ok, [bid | kept]}},
          else: {:cont, {:ok, kept}}

      error ->
        {:halt, error}
    end
  end

  # `bids(bidId)`: startBlock, startCumulativeMps, exitedBlock, maxPrice, owner,
  # amountQ96, tokensFilled.
  defp decode_bid_record(raw, bid_id)
       when is_binary(raw) and byte_size(raw) == @bid_record_words * 32 do
    [_start, _mps, exited_block, max_price, owner_word, amount_q96, tokens_filled] =
      for <<word::256 <- raw>>, do: word

    case Abi.word_address(owner_word) do
      {:ok, owner} ->
        {:ok,
         %{
           bid_id: bid_id,
           owner: owner,
           max_price_q96: max_price,
           amount: Bitwise.bsr(amount_q96, @q96_bits),
           exited_block: exited_block,
           tokens_filled: tokens_filled
         }}

      :error ->
        {:error, :invalid_chain_response}
    end
  end

  defp decode_bid_record(:reverted, _bid_id), do: {:error, :chain_unavailable}
  defp decode_bid_record(_raw, _bid_id), do: {:error, :invalid_chain_response}

  defp bid_positions(bids, auction, wallet, venue) do
    Enum.reduce_while(bids, {:ok, []}, fn bid, {:ok, found} ->
      case position(bid, auction, wallet, venue) do
        {:ok, position} -> {:cont, {:ok, [position | found]}}
        error -> {:halt, error}
      end
    end)
  end

  defp position(bid, auction, wallet, venue) do
    with {:ok, standing, refundable, claim_block} <- standing(bid, auction, venue) do
      {:ok,
       %{
         auction: auction.auction,
         name: auction.name,
         symbol: auction.symbol,
         image: auction.image,
         stock_symbol: auction.stock.symbol,
         bid_id: Integer.to_string(bid.bid_id),
         wallet: wallet,
         committed: Rpc.format_units(bid.amount, auction.stock.decimals),
         max_price:
           Amounts.format_cca_price(bid.max_price_q96, auction.stock.decimals, @token_decimals),
         standing: standing,
         refundable: refundable && Rpc.format_units(refundable, auction.stock.decimals),
         claim_block: claim_block
       }}
    end
  end

  # The auction's own rules, in order: an un-exited bid is in the auction until
  # the end block, buying, sharing or outbid against the stored clearing price;
  # after it, the raise is only final once the launch is
  # finished, so the bid waits on that; a failed launch refunds it in full and
  # a graduated one owes it whatever it did not spend, which its exit states;
  # an exited bid with fill claims from the claim block.
  defp standing(%{exited_block: 0} = bid, %{state: state} = auction, _venue)
       when state in [:created, :active],
       do:
         {:ok,
          AuctionBook.standing(bid.max_price_q96, %{clearing_q96: auction.clearing_price_q96}),
          nil, nil}

  defp standing(%{exited_block: 0}, %{state: :ended}, _venue), do: {:ok, :ended, nil, nil}

  defp standing(%{exited_block: 0, amount: amount}, %{state: :failed}, _venue),
    do: {:ok, :refundable, amount, nil}

  defp standing(%{exited_block: 0}, %{state: :graduated}, _venue),
    do: {:ok, :graduated, nil, nil}

  defp standing(%{tokens_filled: 0} = bid, auction, venue) do
    with {:ok, claimed?} <- claimed?(bid, auction.auction, venue) do
      {:ok, if(claimed?, do: :claimed, else: :returned), nil, nil}
    end
  end

  defp standing(_bid, auction, venue) do
    with {:ok, claim_block} <-
           Rpc.call_uint(
             auction.auction,
             LabAbi.encode(venue.abi, "claimBlock()", []),
             venue.block,
             venue.opts
           ) do
      if venue.clock >= claim_block,
        do: {:ok, :claimable, nil, claim_block},
        else: {:ok, :filled, nil, claim_block}
    end
  end

  defp claimed?(bid, auction, venue) do
    topics = [
      LabAbi.topic(CcaSettlement.tokens_claimed_signature()),
      "0x" <> String.pad_leading(Integer.to_string(bid.bid_id, 16), 64, "0"),
      "0x" <> String.pad_leading(String.slice(bid.owner, 2..-1//1), 64, "0")
    ]

    case Rpc.logs(auction, topics, 0, venue.block.number, venue.opts) do
      {:ok, logs} -> claimed_in?(logs, bid, auction, venue)
      error -> error
    end
  end

  defp claimed_in?(logs, bid, auction, venue) do
    Enum.reduce_while(logs, {:ok, false}, fn log, {:ok, claimed?} ->
      case claimed_log(log, bid, auction, venue) do
        {:ok, tokens} -> {:cont, {:ok, claimed? or tokens > 0}}
        error -> {:halt, error}
      end
    end)
  end

  # The tokens one claim log delivered, or an invalid response for a log that
  # is removed, outside the pinned range or not this bid's claim.
  defp claimed_log(log, bid, auction, venue) do
    with %{"removed" => false, "blockNumber" => "0x" <> number} <- log,
         {number, ""} <- Integer.parse(number, 16),
         true <- number >= 0 and number <= venue.block.number,
         {:ok, %{tokens_claimed: tokens}} <-
           CcaSettlement.claimed(venue.abi, [log], auction, bid.bid_id, bid.owner) do
      {:ok, tokens}
    else
      _invalid -> {:error, :invalid_chain_response}
    end
  end
end
