defmodule Regents.Keyfleet.Dms.Validations.TwoKeys do
  @moduledoc """
  The two Keys an action names, as the arguments `from:` and `to:`, are
  different Keys: a Key never messages or blocks itself.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Dms.Errors.SameKeyError

  @impl true
  def validate(changeset, opts, _context) do
    from = Ash.Changeset.get_argument(changeset, Keyword.fetch!(opts, :from))

    if from == Ash.Changeset.get_argument(changeset, Keyword.fetch!(opts, :to)),
      do: {:error, SameKeyError.exception(token_id: from)},
      else: :ok
  end
end
