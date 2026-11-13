defmodule Regents.SharedReadingTest do
  # Invariants of the figure every reader it admits sees alike, as ash-template's
  # `AshTemplate.SharedReadingTest` states them: a bad reading never replaces a
  # good one, a failed first read is visible, a kind holds no more keys than it
  # says, and every reading offered reports its size against its kind's limit.
  # No producer runs in tests, so the board's key is the test's own.
  use ExUnit.Case, async: false

  alias Regents.Points.Board
  alias Regents.SharedReading

  @limit 65_536

  setup do
    on_exit(fn -> SharedReading.delete(Board.key()) end)
  end

  test "a refused reading keeps the one held" do
    key = Board.key()
    assert :ok = SharedReading.put(key, %{top: [%{points_micro: 41}]})
    assert {:ok, %{at: at}} = SharedReading.fetch(key)

    assert {:error, :too_large} = SharedReading.put(key, String.duplicate("9", @limit + 1))
    assert {:error, :not_plain} = SharedReading.put(key, 1..2)

    assert {:ok, %{reading: %{top: [%{points_micro: 41}]}, at: ^at, degraded?: false}} =
             SharedReading.fetch(key)
  end

  test "every reading offered reports its size against its kind's limit, refused ones too" do
    test = self()

    :telemetry.attach(
      "shared-reading-size-test",
      [:regents, :shared_reading, :size],
      fn _, size, %{kind: kind}, _ -> send(test, {kind, size}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("shared-reading-size-test") end)

    assert :ok = SharedReading.put(Board.key(), 41)

    assert {:error, :too_large} =
             SharedReading.put(Board.key(), String.duplicate("9", @limit + 1))

    assert_received {:points_board, %{bytes: small, limit: @limit}} when small <= @limit
    assert_received {:points_board, %{bytes: large, limit: @limit}} when large > @limit
  end

  test "a first read that fails is marked, and pages hear it" do
    SharedReading.subscribe(Board.key())

    assert :ok = SharedReading.degraded(Board.key())

    assert_receive {:shared_reading, {:points_board, _program}}
    assert {:ok, %{reading: nil, at: nil, degraded?: true}} = SharedReading.fetch(Board.key())
  end

  test "a kind holds no more keys than it says" do
    other = {:points_board, "another-program"}
    on_exit(fn -> SharedReading.delete(other) end)

    assert :ok = SharedReading.put(Board.key(), 1)
    assert {:error, :too_many_keys} = SharedReading.put(other, 1)
    assert :error = SharedReading.fetch(other)
  end
end
