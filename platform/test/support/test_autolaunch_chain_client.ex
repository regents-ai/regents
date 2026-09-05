defmodule AshPlatform.TestAutolaunchIndexerChainClient do
  @moduledoc """
  A fake Base JSON-RPC endpoint for the Autolaunch log ledger.

  It answers from a scripted chain and keeps every request body it was handed,
  so a test can quote the exact call the indexer made rather than trust that it
  made one. Faults are scripted the same way, which is how a transport failure
  is proven to redact its endpoint without any provider being contacted, and how
  a provider that misbehaves — a bad status, an RPC error body, a foreign
  response id, an address filter it ignores — is put in front of the indexer.
  """

  use Agent

  @spec start_link(map()) :: Agent.on_start()
  def start_link(chain),
    do: Agent.start_link(fn -> %{chain: chain, requests: [], watcher: nil} end, name: __MODULE__)

  @doc "Announces every request to the caller, so a test waits on a call rather than a clock."
  @spec watch() :: :ok
  def watch do
    watcher = self()
    Agent.update(__MODULE__, &%{&1 | watcher: watcher})
  end

  @doc "Replaces the chain the endpoint answers from."
  @spec script(map()) :: :ok
  def script(chain), do: Agent.update(__MODULE__, &%{&1 | chain: chain})

  @doc "Forgets every request recorded so far."
  @spec forget() :: :ok
  def forget, do: Agent.update(__MODULE__, &%{&1 | requests: []})

  @doc "Every request body received so far, oldest first."
  @spec requests() :: [map()]
  def requests, do: __MODULE__ |> Agent.get(& &1.requests) |> Enum.reverse()

  @doc "Every request body for one JSON-RPC method, oldest first."
  @spec requests(String.t()) :: [map()]
  def requests(method), do: Enum.filter(requests(), &(&1.method == method))

  @spec post(String.t(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def post(_url, options) do
    request = Keyword.fetch!(options, :json)

    __MODULE__
    |> Agent.get_and_update(&{{&1.chain, &1.watcher}, %{&1 | requests: [request | &1.requests]}})
    |> announced(request)
    |> respond(request)
  end

  defp announced({chain, nil}, _request), do: chain

  defp announced({chain, watcher}, request) do
    send(watcher, {:rpc, request.method})
    chain
  end

  defp respond(chain, request) do
    case fault(chain.fault, request) do
      :none -> envelope(1, %{"result" => answer(chain, request)})
      response -> response
    end
  end

  defp fault({:raise, message}, _request), do: raise(message)
  defp fault({:status, status}, _request), do: {:ok, %{status: status, body: %{}}}
  defp fault(:rpc_error, _request), do: envelope(1, %{"error" => %{"code" => -32_000}})
  defp fault(:foreign_id, _request), do: envelope(99, %{"result" => nil})

  defp fault({:unavailable, height}, %{method: "eth_getBlockByNumber", params: [block, false]}),
    do: unavailable(block == hex(height))

  defp fault(_none, _request), do: :none

  defp unavailable(true), do: {:ok, %{status: 503, body: %{}}}
  defp unavailable(false), do: :none

  defp answer(chain, %{method: "eth_chainId"}), do: chain.chain_id

  defp answer(chain, %{method: "eth_getBlockByNumber", params: ["safe", false]}),
    do: tagged(header(chain, chain.safe), chain.safe_hash)

  defp answer(chain, %{method: "eth_getBlockByNumber", params: ["finalized", false]}),
    do: header(chain, chain.finalized)

  defp answer(chain, %{method: "eth_getBlockByNumber", params: ["0x" <> height, false]}),
    do: header(chain, String.to_integer(height, 16))

  defp answer(chain, %{
         method: "eth_getLogs",
         params: [%{"fromBlock" => from, "toBlock" => to, "address" => addresses}]
       }) do
    chain.blocks
    |> Enum.filter(&(&1.number in quantity(from)..quantity(to)//1))
    |> Enum.flat_map(& &1.logs)
    |> Enum.filter(&emitted?(chain.filter_addresses, &1, addresses))
  end

  defp emitted?(false, _log, _addresses), do: true
  defp emitted?(true, log, addresses), do: log["address"] in addresses

  defp header(chain, number) do
    case Enum.find(chain.blocks, &(&1.number == number)) do
      nil ->
        nil

      block ->
        %{"number" => hex(block.number), "hash" => block.hash, "parentHash" => block.parent}
    end
  end

  # A safe tag that names a hash the range's own headers do not carry is how a
  # provider answering from two chains at once is put in front of the indexer.
  defp tagged(header, nil), do: header
  defp tagged(header, hash), do: %{header | "hash" => hash}

  defp envelope(id, body),
    do: {:ok, %{status: 200, body: Map.merge(%{"jsonrpc" => "2.0", "id" => id}, body)}}

  defp hex(number), do: "0x" <> String.downcase(Integer.to_string(number, 16))
  defp quantity("0x" <> digits), do: String.to_integer(digits, 16)
end

defmodule AshPlatform.TestAutolaunchBidChainClient do
  @moduledoc """
  A fixture-bound Base client for the Autolaunch bidder.

  It is exactly what the plan permits and no more: an exact predecessor tick and
  a scripted allowance, balance and per-step outcome, so the product flow that
  follows a snapshot can be proved while the production client stays closed. It
  is never installed outside a test, and nothing it answers is reviewed evidence.
  """

  @behaviour AshPlatform.Autolaunch.ChainClient

  @key :autolaunch_bid_fixture

  @doc "Installs this fixture for the duration of the calling test."
  @spec install(map()) :: :ok
  def install(fixture) do
    previous_client = Application.get_env(:ash_platform, :autolaunch_bid_chain_client)
    Application.put_env(:ash_platform, :autolaunch_bid_chain_client, __MODULE__)
    put(fixture)

    ExUnit.Callbacks.on_exit(fn ->
      Application.delete_env(:ash_platform, @key)
      restore(:autolaunch_bid_chain_client, previous_client)
    end)
  end

  @doc "Replaces part of the scripted chain, so a later read can answer differently."
  @spec put(map()) :: :ok
  def put(changes),
    do: Application.put_env(:ash_platform, @key, Map.merge(state(), changes))

  @spec state() :: map()
  def state, do: Application.get_env(:ash_platform, @key, %{})

  @impl true
  def snapshot(%{max_price_q96: max_price_q96}) do
    case state() do
      %{unavailable: reason} ->
        {:error, reason}

      fixture ->
        {:ok,
         %{
           currency: fixture.currency,
           regent_balance: fixture.regent_balance,
           token_allowance: fixture.token_allowance,
           permit2_amount: fixture.permit2_amount,
           permit2_expiration: fixture.permit2_expiration,
           predecessor_source: fixture.predecessor_source,
           prev_tick_price_q96: predecessor(max_price_q96, fixture)
         }}
    end
  end

  @impl true
  def verify(_envelope, step, hash) do
    put(%{read_in_transaction?: AshPlatform.Repo.in_transaction?()})
    raced()

    case state() |> Map.get(:outcomes, %{}) |> Map.get(step, %{outcome: :pending}) do
      {:error, reason} -> {:error, reason}
      outcome -> {:ok, Map.put_new(outcome, :hash, hash)}
    end
  end

  # Moves the operation between the read and the lease transaction, which is the
  # exact race a settlement has to survive.
  defp raced do
    case state()[:raced] do
      nil -> :ok
      move -> move.()
    end
  end

  # No predecessor is asked for by the wallet position read, and none is invented.
  defp predecessor(nil, _fixture), do: nil
  defp predecessor(_max_price_q96, fixture), do: fixture.prev_tick_price_q96

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end

defmodule AshPlatform.BidFixture do
  @moduledoc """
  The one bidder fixture: an account holding a wallet, a live lease, an auction
  raising the bound REGENT, and a scripted chain to review against.

  Every value here is fixture-bound. Nothing it produces is reviewed evidence,
  and no test that uses it may claim the production client prepares anything.
  """

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.TestAutolaunchBidChainClient
  alias AshPlatform.WalletActions.Abi

  @wallet "0x1111111111111111111111111111111111111111"
  @auction_address "0x3333333333333333333333333333333333333333"
  @q96 79_228_162_514_264_337_593_543_950_336

  def wallet, do: @wallet
  def auction_address, do: @auction_address
  def regent, do: String.downcase(Abi.stake_token_address())
  def system, do: %System{}

  @doc "An account holding the bidder wallet, its current lease, and a live auction."
  def bidder(_context \\ %{}) do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!("did:privy:bidder-#{unique}", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, :bind, claim} = SessionAuthority.sign_in(SessionAuthority.bootstrap(), account.id)
    actor = %Human{human_account_id: account.id}

    {:ok,
     account: account,
     actor: actor,
     wallet: @wallet,
     regent: regent(),
     auction: auction!("Bidder auction #{unique}"),
     opts: [
       actor: actor,
       context: %{session_lease: %{lineage: claim.lineage, account_id: account.id}}
     ]}
  end

  @doc "A live auction whose stored terms name the bound REGENT."
  def auction!(title) do
    title
    |> Autolaunch.import_auction!(nil, false, :active, ~U[2026-08-20 11:00:00Z], actor: %System{})
    |> Autolaunch.set_auction_bid_terms!(@auction_address, regent(), "REGENT", 18, "2.5",
      actor: %System{}
    )
  end

  @doc "The scripted chain a review is derived from, with any part replaced."
  def fixture(overrides \\ []) do
    %{
      currency: regent(),
      regent_balance: 100 * Integer.pow(10, 18),
      token_allowance: 0,
      permit2_amount: 0,
      permit2_expiration: 0,
      predecessor_source: "fixture",
      prev_tick_price_q96: 2 * @q96,
      outcomes: %{}
    }
    |> Map.merge(Map.new(overrides))
  end

  @doc "Installs that scripted chain for the calling test."
  def install(overrides \\ []),
    do: overrides |> fixture() |> TestAutolaunchBidChainClient.install()

  @doc "The exact refusal an Ash action carried out, whatever its error class."
  def refusal(%{errors: errors}), do: Enum.find_value(errors, :unmatched, &unavailable/1)
  def refusal(reason), do: reason

  defp unavailable(%Ash.Error.Invalid.Unavailable{reason: reason}), do: reason
  defp unavailable(_other), do: nil
end
