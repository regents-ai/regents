defmodule Regents.Repo.Migrations.KeyfleetDropFastPollSessions do
  @moduledoc """
  Removes the multi-round poll sessions, their seats, rounds, votes and logs,
  and any round-closing job still queued for them. One-question polls take
  their place in the next migration.
  """

  use Ecto.Migration

  def up do
    execute("DELETE FROM keyfleet_app.oban_jobs WHERE worker = 'Keyfleet.Polls.Deadline'")

    drop(table(:poll_votes))
    drop(table(:poll_events))
    drop(table(:poll_rounds))
    drop(table(:poll_seats))
    drop(table(:poll_sessions))

    execute("DROP FUNCTION keyfleet_app.protect_poll_vote()")
    execute("DROP FUNCTION keyfleet_app.protect_poll_round()")
    execute("DROP FUNCTION keyfleet_app.protect_poll_event()")
  end

  def down do
    raise Ecto.MigrationError,
      message: "the multi-round poll sessions were removed and are not brought back"
  end
end
