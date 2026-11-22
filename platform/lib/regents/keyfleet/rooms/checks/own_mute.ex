defmodule Regents.Keyfleet.Rooms.Checks.OwnMute do
  @moduledoc "The actor's own mutes, and nobody else's."
  use Ash.Policy.FilterCheck

  alias Regents.Keyfleet.Rooms.Muter

  @impl true
  def describe(_opts), do: "the mute is the actor's own"

  @impl true
  def filter(actor, _authorizer, _opts) do
    case Muter.of(actor) do
      nil -> expr(false)
      muter -> expr(muter == ^muter)
    end
  end
end
