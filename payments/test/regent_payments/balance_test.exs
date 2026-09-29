defmodule RegentPayments.BalanceTest do
  @moduledoc """
  A USDC Balance is what the USDC contract reports for the wallet, read with
  one `balanceOf` call to a fake Base. A malformed address never reaches the
  chain, and an answer that is not one 32-byte word never becomes a number.
  """

  use ExUnit.Case, async: false

  import Plug.Conn

  alias RegentPayments.Balance
  alias RegentPayments.USDC

  @wallet "0x" <> String.duplicate("aB", 20)

  setup do
    original = Application.get_env(:regent_payments, :base_rpc_url)
    on_exit(fn -> Application.put_env(:regent_payments, :base_rpc_url, original) end)
    :ok
  end

  test "the wallet's balance is balanceOf on the USDC contract at the latest block" do
    calls = chain(fn -> "0x" <> String.pad_leading(Integer.to_string(2_500_000, 16), 64, "0") end)

    assert {:ok, 2_500_000} = Balance.usdc_balance_atomic(@wallet)

    assert [%{"method" => "eth_call", "params" => [call, "latest"]}] = Agent.get(calls, & &1)
    assert call["to"] == USDC.asset()

    assert call["data"] ==
             "0x70a08231" <> String.pad_leading(String.slice(@wallet, 2..-1//1), 64, "0")
  end

  test "a malformed address is refused unasked and a malformed answer is not a balance" do
    calls = chain(fn -> "0x1234" end)

    for address <- ["", "0x123", "0x" <> String.duplicate("z", 40), String.duplicate("a", 42)] do
      assert {:error, :invalid_address} = Balance.usdc_balance_atomic(address)
    end

    assert Agent.get(calls, & &1) == []
    assert {:error, :rpc_failed} = Balance.usdc_balance_atomic(@wallet)

    Application.put_env(:regent_payments, :base_rpc_url, nil)
    assert {:error, :not_configured} = Balance.usdc_balance_atomic(@wallet)
  end

  # A fake Base answering every eth_call with `result`, keeping each request.
  defp chain(result) do
    calls = start_supervised!({Agent, fn -> [] end})

    server =
      start_supervised!(
        {Bandit,
         plug: fn conn, _opts ->
           {:ok, body, conn} = read_body(conn)
           request = JSON.decode!(body)
           Agent.update(calls, &(&1 ++ [request]))

           conn
           |> put_resp_content_type("application/json")
           |> send_resp(
             200,
             JSON.encode!(%{jsonrpc: "2.0", id: request["id"], result: result.()})
           )
         end,
         ip: {127, 0, 0, 1},
         port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    Application.put_env(:regent_payments, :base_rpc_url, "http://127.0.0.1:#{port}")
    calls
  end
end
