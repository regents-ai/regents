defmodule RegentIdentity.ConsumerTest do
  use ExUnit.Case, async: false

  setup_all do
    config = Application.fetch_env!(:regent_identity, RegentIdentity.TestRepo)
    Application.put_env(:regent_identity, RegentIdentity.SecondRepo, config)
    start_supervised!(RegentIdentity.SecondRepo)
    Ecto.Adapters.SQL.Sandbox.mode(RegentIdentity.SecondRepo, :manual)
    :ok
  end

  test "independent consumer connections and concurrent sign-ins share one canonical row" do
    subject = "consumer-#{System.unique_integer([:positive])}"

    actor = %RegentPrivy.Session{
      app_id: "shared-app",
      privy_user_id: subject,
      session_id: "site-one",
      wallet_addresses: [],
      issued_at: System.system_time(:second) - 1,
      expires_at: System.system_time(:second) + 3600
    }

    on_exit(fn ->
      Application.put_env(:regent_identity, :repo, RegentIdentity.TestRepo)

      Ecto.Adapters.SQL.Sandbox.unboxed_run(RegentIdentity.TestRepo, fn ->
        Ecto.Adapters.SQL.query!(
          RegentIdentity.TestRepo,
          "DELETE FROM regent_identity.profiles WHERE app_id = $1 AND privy_user_id = $2",
          [actor.app_id, subject]
        )
      end)
    end)

    results =
      1..4
      |> Task.async_stream(
        fn n ->
          Ecto.Adapters.SQL.Sandbox.unboxed_run(RegentIdentity.TestRepo, fn ->
            RegentIdentity.sync(%{actor | session_id: "site-#{n}"})
          end)
        end,
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, {:ok, profile}} -> profile.id end)

    assert length(Enum.uniq(results)) == 1

    Application.put_env(:regent_identity, :repo, RegentIdentity.SecondRepo)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(RegentIdentity.SecondRepo, fn ->
      assert {:ok, profile} =
               RegentIdentity.get_my_profile(actor: %{actor | session_id: "another-consumer"})

      assert profile.id == hd(results)
      assert {:ok, synced} = RegentIdentity.sync(actor)
      assert synced.id == profile.id
    end)

    Application.put_env(:regent_identity, :repo, RegentIdentity.TestRepo)
  end
end
