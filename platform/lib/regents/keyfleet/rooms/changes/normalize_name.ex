defmodule Regents.Keyfleet.Rooms.Changes.NormalizeName do
  @moduledoc """
  Puts a room's name or topic in Unicode NFKC form before it is checked and
  stored. Setting the attribute again trims it, as every string attribute is
  trimmed, so spaces that NFKC turns ordinary are trimmed too.

  Full-width letters, ligatures and other compatibility forms become the plain
  characters they stand for, so a name that only looks different in its
  encoding is the same name when rooms' names are compared. Letters of other
  alphabets that merely look alike stay as they are. A name that is empty once
  trimmed is refused as missing.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.fetch!(opts, :attribute)

    case Ash.Changeset.get_attribute(changeset, attribute) do
      value when is_binary(value) ->
        Ash.Changeset.change_attribute(changeset, attribute, String.normalize(value, :nfkc))

      _absent ->
        changeset
    end
  end
end
