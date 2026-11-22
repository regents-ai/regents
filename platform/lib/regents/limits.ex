defmodule Regents.Limits do
  @moduledoc """
  The site's named allowances, `config :regents, :limits`, each named
  `<product>_<name>` with its `limit` and `window_seconds`, and spent through
  `Regents.RateLimiter`. The `<product>_` prefix is required: the allowances
  share the site's counters, so a name without it could spend another's.
  """

  alias Regents.RateLimiter

  @doc "Spends one of `name`'s allowance for `who`: `:ok` or `:limited`."
  @spec spend(atom(), term()) :: :ok | :limited
  def spend(name, who) do
    case admit(name, who) do
      :ok -> :ok
      {:limited, _retry_after} -> :limited
    end
  end

  @doc """
  Spends one of `name`'s allowance for `who`: `:ok`, or `{:limited, seconds}`
  with the seconds until the allowance starts again.
  """
  @spec admit(atom(), term()) :: :ok | {:limited, pos_integer()}
  def admit(name, who) do
    config = :regents |> Application.fetch_env!(:limits) |> Keyword.fetch!(name)

    case RateLimiter.admit({name, who}, config[:limit], config[:window_seconds]) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, budget} -> {:limited, budget.reset}
    end
  end

  @doc "The seconds `name`'s allowance lasts before it starts again."
  @spec window(atom()) :: pos_integer()
  def window(name),
    do:
      :regents
      |> Application.fetch_env!(:limits)
      |> Keyword.fetch!(name)
      |> Keyword.fetch!(:window_seconds)
end
