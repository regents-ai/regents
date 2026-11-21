defmodule Regents.Keyfleet.Rooms.Validations.HasPairedAgent do
  @moduledoc """
  The signed-in person has an agent paired to their account, to send their
  words to (`Regents.Keyfleet.Agents.has_paired_agent?/1`).
  """
  use Ash.Resource.Validation

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Rooms.Errors.NoPairedAgentError

  @impl true
  def validate(_changeset, _opts, %{actor: %Human{} = actor}) do
    if Regents.Keyfleet.Agents.has_paired_agent?(actor),
      do: :ok,
      else: {:error, NoPairedAgentError.exception([])}
  end

  def validate(_changeset, _opts, _context), do: {:error, NoPairedAgentError.exception([])}
end
