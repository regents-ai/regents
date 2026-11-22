defmodule Regents.Keyfleet.Keys.Checks.ActsForPerson do
  @moduledoc """
  Whether the actor speaks for a person's own account settings on this site:
  the person signed in, or an agent paired with a person who has signed in
  here (`Regents.Account.Actors.Agent`'s `pairing`). Such an agent changes what its
  person could change, for its person and every agent of theirs alike.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Account.Actors.{Agent, Human}

  @impl true
  def describe(_opts), do: "actor is a person, or an agent paired with a person here"

  @impl true
  def match?(%Human{}, _context, _opts), do: true
  def match?(%Agent{pairing: %Human{}}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
