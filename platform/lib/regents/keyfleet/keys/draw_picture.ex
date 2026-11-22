defmodule Regents.Keyfleet.Keys.DrawPicture do
  @moduledoc """
  Draws a Key's card, keeps it on IPFS through Lighthouse, then records its
  address against the Key and the card's seed, so the Key's metadata shows it.
  Queued in the same transaction as the record that gives the Key its card: a
  dealt Key's first ownership record, or a later Key's reveal
  (`Regents.Keyfleet.Keys.Changes.QueuePicture`), so a record rolled back draws nothing.

  The same seed always gives the same picture, and the same picture the same
  address, so running twice is safe; a card that already has its picture is
  left as it is, and one that is no longer the Key's card, because an operator
  has removed its reveal since, is not drawn.
  """
  use Oban.Worker,
    queue: :keyfleet_key_art,
    max_attempts: 20,
    unique: [keys: [:fleet_id, :token_id, :seed], period: :infinity, states: :incomplete]

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.KeyArt
  alias Regents.Keyfleet.Lighthouse

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"fleet_id" => fleet_id, "token_id" => token_id, "seed" => seed}
      }) do
    fleet = Fleets.get_fleet!(fleet_id)

    cond do
      Keys.card_seed(fleet, token_id) != seed -> :ok
      Keys.get_picture!(fleet_id, token_id, seed) -> :ok
      true -> draw(fleet, token_id, seed)
    end
  end

  defp draw(%{id: fleet_id, trait_table_hash: hash}, token_id, seed) do
    filename = "#{Fleets.slot(fleet_id)}-#{token_id}.png"

    with {:ok, png} <- KeyArt.draw(seed, Fleets.key_name(fleet_id, token_id), hash),
         {:ok, cid} <- Lighthouse.add(png, filename, "image/png") do
      Keys.record_picture!(
        %{fleet_id: fleet_id, token_id: token_id, seed: seed, cid: cid},
        actor: %Regents.Account.Actors.System{}
      )

      :ok
    end
  end
end
