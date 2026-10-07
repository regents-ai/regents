defmodule RegentsWeb.ChainReadBudget do
  @moduledoc """
  One budget per client address for the readings of Base a visitor starts: the
  wallet figures on Stake and the Overview, the Redeem page's figures, and the
  staking position read. Past it, a page keeps the last reading it has. A wallet
  press never draws on it.
  """

  alias Regents.RateLimiter

  @spec admit(String.t()) :: :ok | {:limited, pos_integer()}
  def admit(client_tag) when is_binary(client_tag) do
    budget = Application.fetch_env!(:regents, :chain_read_rate_limit)
    limit = Keyword.fetch!(budget, :limit)
    window = Keyword.fetch!(budget, :window_seconds)

    case RateLimiter.admit({:chain_reads, client_tag}, limit, window) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, budget} -> {:limited, budget.reset}
    end
  end

  @doc "What a page says while it keeps the last reading."
  def notice(seconds),
    do: %{
      budget: :chain_reads,
      tone: :info,
      message:
        "Too many updates this minute. Showing the last figures; try again in #{seconds} s."
    }
end
