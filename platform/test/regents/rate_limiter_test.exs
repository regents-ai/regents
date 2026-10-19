defmodule Regents.RateLimiterTest do
  # The clock is application config, so these tests run alone.
  use ExUnit.Case, async: false

  alias Regents.RateLimiter

  setup do
    previous_clock = Application.fetch_env!(:regents, :rate_limiter_clock)
    clock = :counters.new(1, [])
    Application.put_env(:regents, :rate_limiter_clock, fn -> :counters.get(clock, 1) end)
    on_exit(fn -> Application.put_env(:regents, :rate_limiter_clock, previous_clock) end)
    %{clock: clock, key: make_ref()}
  end

  test "a budget spent in one window holds to its last second and returns at the next", %{
    clock: clock,
    key: key
  } do
    # One second before a 60-second window ends.
    :counters.put(clock, 1, 60 * 1_000 + 59)

    assert {:ok, %{remaining: 1, reset: 1}} = RateLimiter.admit(key, 2, 60)
    assert {:ok, %{remaining: 0, reset: 1}} = RateLimiter.admit(key, 2, 60)
    assert {:error, :rate_limited, %{remaining: 0, reset: 1}} = RateLimiter.admit(key, 2, 60)

    :counters.add(clock, 1, 1)

    assert {:ok, %{remaining: 1, reset: 60}} = RateLimiter.admit(key, 2, 60)
  end
end
