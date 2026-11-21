defmodule Regents.Keyfleet.Keys.Changes.QueuePicture do
  @moduledoc """
  Queues the drawing of a Key's card (`Regents.Keyfleet.Keys.DrawPicture`) in the
  transaction of the record that gives the Key its card: a dealt Key's first
  ownership record, or a later Key's reveal. A record read again queues it
  again; the job leaves a card that already has its picture as it is. A Key
  with no card yet, one past the deck awaiting its reveal, queues nothing.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.DrawPicture

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, %{fleet_id: fleet_id} = record ->
      case Keys.card_seed(Fleets.get_fleet!(fleet_id), record.token_id) do
        nil ->
          :ok

        seed ->
          Oban.insert!(
            DrawPicture.new(%{fleet_id: fleet_id, token_id: record.token_id, seed: seed})
          )
      end

      {:ok, record}
    end)
  end
end
