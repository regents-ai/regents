defmodule Regents.Keyfleet.Chain.Changes.RecordOnce do
  @moduledoc """
  Makes a record from one chain event exactly once, for an action that
  upserts on the identity named by the attributes in `:identity` and changes
  nothing when it skips. The event is held under that identity until commit,
  and a record already made under it is kept as first saved.

  With `:number`, `:proposal_seq`, `:reveal_seq`, `:ownership_seq` or
  `:shard_seq`, a
  record read again keeps the number it has and a new one takes the fleet's
  next number in the same transaction, from `Regents.Keyfleet.Chain`.
  """
  use Ash.Resource.Change

  import Ecto.Query, only: [from: 2]

  @impl true
  def change(changeset, opts, _context),
    do: Ash.Changeset.before_action(changeset, &hold_and_number(&1, opts))

  defp hold_and_number(changeset, opts) do
    identity =
      Enum.map(Keyword.fetch!(opts, :identity), &{&1, Ash.Changeset.get_attribute(changeset, &1)})

    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!([inspect(changeset.resource) | Keyword.values(identity)])
    ])

    case opts[:number] do
      nil ->
        changeset

      sequence ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :record_seq,
          number(changeset, identity, sequence)
        )
    end
  end

  # Read straight from the table, since a resource may offer no unscoped read.
  defp number(changeset, identity, sequence) do
    recorded =
      Regents.Repo.one(
        from(record in changeset.resource,
          prefix: ^Regents.Keyfleet.schema(),
          where: ^identity,
          select: record.record_seq
        )
      )

    recorded || take(sequence, Ash.Changeset.get_attribute(changeset, :fleet_id))
  end

  defp take(:proposal_seq, fleet_id), do: Regents.Keyfleet.Chain.take_proposal_seq!(fleet_id)
  defp take(:reveal_seq, fleet_id), do: Regents.Keyfleet.Chain.take_reveal_seq!(fleet_id)
  defp take(:ownership_seq, fleet_id), do: Regents.Keyfleet.Chain.take_ownership_seq!(fleet_id)
  defp take(:shard_seq, fleet_id), do: Regents.Keyfleet.Chain.take_shard_seq!(fleet_id)
end
