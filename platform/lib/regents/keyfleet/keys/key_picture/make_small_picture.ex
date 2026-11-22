defmodule Regents.Keyfleet.Keys.KeyPicture.MakeSmallPicture do
  @moduledoc """
  Makes one of a card picture's small pictures before the row is written,
  its close-up (`kind: :close_up`) or its small card (`kind: :small_card`):
  reads the card back from where it is shown, makes the small picture
  (`Regents.Keyfleet.Keys.KeyArt`) and keeps it on IPFS through Lighthouse, outside
  any transaction. A failed read, cut or upload fails the action, so the job
  retries with backoff.
  """

  use Ash.Resource.Change

  alias Ash.Error.Unknown.UnknownError
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys.KeyArt
  alias Regents.Keyfleet.Lighthouse

  # Each kind's attribute, how it is made from the card, and its file name.
  @kinds %{
    close_up: {:close_up_cid, &KeyArt.close_up/1, "close-up"},
    small_card: {:small_card_cid, &KeyArt.small_card/1, "small-card"}
  }

  @impl true
  def init(opts) do
    if Map.has_key?(@kinds, opts[:kind]),
      do: {:ok, opts},
      else: {:error, "kind must be one of #{inspect(Map.keys(@kinds))}"}
  end

  @impl true
  def change(changeset, opts, _context) do
    {attribute, make, name} = Map.fetch!(@kinds, opts[:kind])

    Ash.Changeset.before_action(changeset, fn changeset ->
      %{fleet_id: fleet_id, token_id: token_id, cid: cid} = changeset.data
      filename = "#{Fleets.slot(fleet_id)}-#{token_id}-#{name}.webp"

      with {:ok, png} <- KeyArt.kept(cid),
           {:ok, webp} <- make.(png),
           {:ok, small_cid} <- Lighthouse.add(webp, filename, "image/webp") do
        Ash.Changeset.force_change_attribute(changeset, attribute, small_cid)
      else
        # A fault of the site's or of a service it calls, never of anyone's
        # input, so it is kept with the site's saved errors.
        {:error, reason} ->
          Ash.Changeset.add_error(
            changeset,
            UnknownError.exception(error: "#{name} not made: #{inspect(reason)}")
          )
      end
    end)
  end
end
