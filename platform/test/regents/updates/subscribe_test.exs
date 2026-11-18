defmodule Regents.Updates.SubscribeTest do
  # Leaving an email address for updates, through the action the Cloak page calls:
  # - a good address is kept once, in lowercase, with its page and time;
  # - the same address again, in any case, answers the same and keeps one row;
  # - an address that is not one is refused, and nothing is kept;
  # - each network leaves 5 a minute.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Regents.{Repo, Updates}

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
    %{key: Ecto.UUID.generate()}
  end

  test "a good address is kept once, and leaving it again answers the same", %{key: key} do
    assert {:ok, _subscriber} = subscribe(" Ada@Example.com ", key)
    assert {:ok, _subscriber} = subscribe("ada@example.COM", key)

    assert [%{address: "ada@example.com", source: "cloak", inserted_at: %NaiveDateTime{}}] =
             rows()
  end

  test "an address that is not one is refused and nothing is kept", %{key: key} do
    for address <- ["", "ada", "ada@example", "ada @example.com", "@example.com"] do
      assert {:error, %Ash.Error.Invalid{}} = subscribe(address, key)
    end

    assert rows() == []
  end

  test "each network leaves 5 a minute", %{key: key} do
    for n <- 1..5, do: assert({:ok, _subscriber} = subscribe("ada#{n}@example.com", key))

    assert {:error, %Ash.Error.Invalid{}} = subscribe("ada6@example.com", key)
    assert {:ok, _subscriber} = subscribe("ada6@example.com", Ecto.UUID.generate())
    assert length(rows()) == 6
  end

  defp subscribe(address, key),
    do:
      Updates.subscribe_to_updates(%{address: address, source: :cloak},
        context: %{client_key: key}
      )

  defp rows do
    # The list has no read action, so the test reads its table directly.
    Repo.all(
      from(s in "update_subscribers",
        select: %{address: s.address, source: s.source, inserted_at: s.inserted_at}
      )
    )
  end
end
