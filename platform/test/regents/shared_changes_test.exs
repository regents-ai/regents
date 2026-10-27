defmodule Regents.SharedChangesTest do
  # Invariant: a Credits balance, a pairing and the staking figures changed on any
  # Regent site, announced through the database, reach this site's open pages, and
  # all three are heard on the site's one listening connection.
  use ExUnit.Case, async: false

  alias Regents.Staking.SnapshotCache

  setup do
    # Another site's announcement: committed on a connection of its own, outside
    # the test sandbox.
    connection = Regents.DatabaseConfig.notifications_config(Regents.Repo.config())
    %{other_site: start_supervised!({Postgrex, connection})}
  end

  test "changes announced through the database reach the pages on one connection", %{
    other_site: other_site
  } do
    person = "did:privy:" <> Ecto.UUID.generate()

    for topic <- [RegentCredits.topic(person), RegentAgents.topic(person), SnapshotCache.topic()],
        do: Phoenix.PubSub.subscribe(Regents.PubSub, topic)

    for {channel, payload} <- [
          {RegentCredits.channel(), person},
          {RegentAgents.channel(), person},
          {SnapshotCache.channel(), "unavailable"}
        ],
        do: Postgrex.query!(other_site, "SELECT pg_notify($1, $2)", [channel, payload])

    assert_receive :credits_changed, 2_000
    assert_receive :agents_changed, 2_000
    assert_receive {:staking_snapshot_unavailable, :unavailable}, 2_000

    %{rows: [[listening]]} =
      Postgrex.query!(
        other_site,
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND application_name = 'regents-listen' AND pid <> pg_backend_pid()",
        []
      )

    assert listening == 1
  end
end
