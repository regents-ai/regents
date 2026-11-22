defmodule RegentsWeb.Patchbay.PaymentLimit do
  @moduledoc """
  Per-wallet payment rate limit for Patchbay's payment intent endpoints, backed
  by `Regents.RateLimiter`.
  """

  alias Regents.RateLimiter
  alias RegentsWeb.Patchbay.{ApiError, RateLimitHeaders}

  @default_payments_per_minute 10
  @window_seconds 60
  @window :timer.minutes(1)

  @error "Too many payment requests for this wallet. Wait a minute, then try again."
  @hint "Wait retry_after_seconds, then send it again."

  @spec check(String.t()) :: {:ok, non_neg_integer()} | {:wait, pos_integer()}
  def check(wallet) when is_binary(wallet) do
    quota = payments_per_minute()

    case RateLimiter.admit({:patchbay_payments, String.downcase(wallet)}, quota, @window_seconds) do
      {:ok, %{remaining: left}} -> {:ok, left}
      {:error, :rate_limited, %{reset: wait}} -> {:wait, max(wait, 1)}
    end
  end

  @spec add_headers(Plug.Conn.t(), non_neg_integer()) :: Plug.Conn.t()
  def add_headers(conn, left),
    do: RateLimitHeaders.add(conn, "payments", payments_per_minute(), @window, left)

  @spec refusal(pos_integer()) :: %{error: map()}
  def refusal(seconds),
    do: ApiError.body("rate_limited", @error, @hint, %{retry_after_seconds: seconds})

  defp payments_per_minute,
    do: Application.get_env(:regents, :payments_per_minute, @default_payments_per_minute)
end
