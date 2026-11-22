defmodule RegentsWeb.Keyfleet.AgentChainJSON do
  @moduledoc """
  What `RegentsWeb.Keyfleet.AgentChainController` answers: the chain the fleet is on,
  a line saying what the transactions do (null when there is nothing to
  say), the transactions in the order to send them, and the figures they were
  built from. Amounts and wei are decimal strings; times are ISO 8601 in UTC.
  """

  alias RegentsWeb.Keyfleet.WalletWords

  @doc "The answer for `flow`, built as `Regents.Keyfleet.WalletSteps.Build` describes."
  def answer(flow, fleet, %{review: review, figures: figures} = built) do
    %{
      chain_id: fleet.chain_id,
      says: WalletWords.line(flow, built, review.inputs),
      transactions: Enum.map(review.steps, &transaction(&1, figures.blocked))
    }
    |> Map.merge(figures(flow, figures))
  end

  defp transaction(step, blocked) do
    %{
      name: step.step,
      title: WalletWords.title(%{name: step.step}),
      to: step.to,
      data: step.data,
      value:
        step.value |> String.trim_leading("0x") |> String.to_integer(16) |> Integer.to_string(),
      blocked: blocked |> Map.get(step.step) |> why()
    }
  end

  defp why(nil), do: nil
  defp why(reason), do: WalletWords.blocked(reason)

  defp figures(:present, %{keys: keys}) do
    %{keys: Enum.map(keys, &%{token_id: &1.token_id, present_until: &1.until})}
  end

  defp figures(:propose, figures) do
    Map.take(figures, [:kind, :key, :hours, :closes_at, :content_hash])
  end

  defp figures(:ballot, %{keys: keys, status: status}), do: %{keys: keys, status: status}
  defp figures(flow, %{status: status}) when flow in [:cancel, :carry_out], do: %{status: status}

  defp figures(:run_split, figures) do
    %{
      rate_bps: figures.rate_bps,
      keys_sold: figures.keys,
      last_run_at: figures.last_run_at,
      opens_at: figures.opens_at,
      assets:
        Enum.map(
          figures.assets,
          &%{
            asset: &1.asset,
            symbol: &1.symbol,
            decimals: &1.decimals,
            balance: Integer.to_string(&1.balance),
            least_to_split: Integer.to_string(&1.threshold),
            per_key: Integer.to_string(&1.per_key)
          }
        )
    }
  end

  defp figures(:send_share, %{owed: owed}), do: %{owed: Integer.to_string(owed)}

  defp figures(:convert, %{
         amount: amount,
         waiting: waiting,
         in_line: in_line,
         opens_at: opens_at
       }),
       do: %{
         amount: Integer.to_string(amount),
         waiting: Integer.to_string(waiting),
         in_line: in_line,
         opens_at: opens_at
       }

  defp figures(:claim, %{token_id: token_id, holder: holder, waiting: waiting}),
    do: %{token_id: token_id, paid_to: holder, waiting: Enum.map(waiting, &waiting/1)}

  defp figures(:issue_shard, figures), do: Map.take(figures, [:keys, :wallet, :days])

  defp figures(:end_shard, %{token_id: token_id, wallets: wallets, renew_days: days}),
    do: %{token_id: token_id, wallets: wallets, renew_days: days}

  defp figures(:agent_voting, %{keys: keys, voting: voting}),
    do: %{keys: keys, voting_on: voting}

  defp figures(:buy, %{token_id: token_id, price: price, max_price: max_price, approve?: approve?}),
       do: %{
         token_id: token_id,
         price: Integer.to_string(price),
         max_price: Integer.to_string(max_price),
         approve_first: approve?
       }

  defp figures(flow, %{token_id: token_id}) when flow in [:club_claim, :reveal],
    do: %{token_id: token_id}

  defp figures(:return_advance, figures) do
    %{
      advance_id: figures.advance_id,
      operator: figures.operator,
      asset: figures.asset.address,
      symbol: figures.asset.symbol,
      decimals: figures.asset.decimals,
      outstanding: Integer.to_string(figures.outstanding),
      amount: Integer.to_string(figures.amount)
    }
  end

  defp figures(:launch_upkeep, figures) do
    %{
      launch_id: figures.launch_id,
      token: figures.token,
      lifecycle: figures.lifecycle,
      added_to_split: figures.bound?
    }
  end

  defp figures(:claim_all, %{keys: keys, waiting: waiting}),
    do: %{token_ids: keys, waiting: Enum.map(waiting, &waiting/1)}

  defp waiting(entry) do
    %{
      asset: entry.asset,
      symbol: entry.symbol,
      decimals: entry.decimals,
      amount: Integer.to_string(entry.amount)
    }
  end
end
