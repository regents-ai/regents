defmodule Regents.Keyfleet.Access.Check do
  @moduledoc """
  The one policy check for what a fleet shares: whether the actor may read or
  write a component of `Regents.Keyfleet.Access`, in the scope the action names.

      authorize_if {Regents.Keyfleet.Access.Check, read: :rooms, scope: :fleet_id}
      authorize_if {Regents.Keyfleet.Access.Check, write: :key_walls, scope: :fleet_id}

  `scope:` names the argument or attribute that holds the fleet's id. The
  policy names the component, never a class: the class is looked up in the
  table. A request that reads its class once hands it on in its context
  (`Regents.Keyfleet.Access.context/3`), and it is not read again here.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Keyfleet.Access

  @impl true
  def describe(opts) do
    {action, component} = named(opts)
    "actor may #{action} the fleet's #{component}"
  end

  @impl true
  def match?(actor, %{subject: subject}, opts) do
    {action, component} = named(opts)
    scope = Ash.Subject.get_argument_or_attribute(subject, Keyword.fetch!(opts, :scope))

    case subject.context do
      %{shared: %{access: %{actor: ^actor, scope: ^scope, class: class}}} ->
        Access.enough?(class, action, component)

      _context ->
        Access.allowed?(actor, action, component, scope)
    end
  end

  defp named(opts) do
    case {Keyword.fetch(opts, :read), Keyword.fetch(opts, :write)} do
      {{:ok, component}, :error} -> {:read, component}
      {:error, {:ok, component}} -> {:write, component}
    end
  end
end
