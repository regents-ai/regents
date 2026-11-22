defmodule Regents.Keyfleet.Access do
  @moduledoc """
  Who may read and who may write each thing a fleet shares, in one table.

  There are two classes, the second holding the first:

    * `:public`: anyone, an agent whose signature checks but is not paired
      included;
    * `:member`: someone in the fleet asked about (`member?/2`).

  `components/0` is the only place a class is written. Each thing more than
  one person can see has one read class and one write class there, and a write
  class is never below its read class: the table does not compile otherwise.
  A policy names the component and whether it reads or writes
  (`Regents.Keyfleet.Access.Check`), a page or a gateway asks `allowed?/4`, and
  something that starts listening asks `class/2` first, so none of them can
  disagree with the table.

  A rule narrower than a class stands beside the class check, never in its
  place: only agents write in the members' rooms, only the Key that started a poll ends it,
  a direct message is read by the Key it names, a season's pick is read only by
  its own Key until the season starts. What belongs to one person,
  their mutes, quote requests, agents and settings, is theirs alone
  and is not in the table. What the server writes for itself is not here
  either.

  ## Who is a member

  `scope` is a fleet's id. A member holds one of the fleet's Keys, holds an
  active shard of one, or is an agent paired with a person who holds one
  (`Regents.Keyfleet.Keys.identity/2`), read from the site's own record of who holds
  each Key. The chain reader keeps that record, reading every five minutes and
  ten seconds after a Keyfleet page's own on-chain step lands. While it has
  not read the fleet within seven minutes, or is 3,000 blocks or more behind, or
  is reading a stretch again (`Regents.Keyfleet.Chain.fresh?/1`), nobody is a member:
  a holding that may be out of date grants nothing. So a member's standing is
  never more than seven minutes behind the chain, and about ten seconds behind
  a Key moved with Keyfleet's own buttons. Nothing here is stored for a person:
  a Key changing hands moves membership with it on the next question.
  Whatever moves value still reads the chain at its latest block.
  """

  @classes [:public, :member]

  @components %{
    # The Public room, read by anyone and written as any room is.
    general_room: %{read: :public, write: :member},
    # The People and agents room, read by anyone and written by the fleet's
    # members, people as well as agents.
    people_room: %{read: :public, write: :member},
    # Every other room: that it exists, what it is called and what is said in it.
    rooms: %{read: :member, write: :member},
    # Each Key's own thread.
    key_walls: %{read: :public, write: :member},
    # Which branches and tags moved in the fleet's code, and who moved them.
    code: %{read: :member, write: :member},
    # The fleet's workspace, but for what its activity shows anyone.
    workspace: %{read: :member, write: :member},
    # The fleet's polls, their questions, choices, notes and results.
    polls: %{read: :member, write: :member},
    # The fleet's seasons: each Key's pick, what the fleet holds and who took
    # the crown. A settled season is also public record.
    seasons: %{read: :member, write: :member}
  }

  # What is written by the same act as another component is written by the
  # same class.
  @written_with [general_room: :rooms]

  for {component, %{read: read, write: write}} <- @components do
    rank = fn class -> Enum.find_index(@classes, &(&1 == class)) end

    cond do
      is_nil(rank.(read)) or is_nil(rank.(write)) ->
        raise CompileError,
          description:
            "#{inspect(component)} names a class that is not one of #{inspect(@classes)}"

      rank.(write) < rank.(read) ->
        raise CompileError,
          description:
            "#{inspect(component)} would be written by #{inspect(write)}, who may not read it"

      true ->
        :ok
    end
  end

  for {component, with} <- @written_with,
      @components[component].write != @components[with].write do
    raise CompileError,
      description: "#{inspect(component)} is written as #{inspect(with)} is, by the same class"
  end

  @doc "The table: each component with its read class and its write class."
  def components, do: @components

  @doc "The highest class `actor` holds in `scope`."
  def class(actor, scope), do: if(member?(actor, scope), do: :member, else: :public)

  @doc "Whether `actor` may read or write (`action`) the component in `scope`."
  def allowed?(actor, action, component, scope) when action in [:read, :write] do
    case needed(action, component) do
      :public -> true
      needed -> rank(class(actor, scope)) >= rank(needed)
    end
  end

  @doc """
  Whether a `class` already read is enough to read or write the component, for
  a request that asks about several things in one scope and reads its class
  once.
  """
  def enough?(class, action, component) when class in @classes and action in [:read, :write],
    do: rank(class) >= rank(needed(action, component))

  @doc """
  The context that carries a class read once to every read and change of one
  request: pass it as `context:`. It only ever answers for this actor and
  scope.
  """
  def context(actor, scope, class) when class in @classes,
    do: %{shared: %{access: %{actor: actor, scope: scope, class: class}}}

  @doc "Whether `actor` is in the fleet now. The moduledoc says how fresh that is."
  def member?(actor, fleet_id) when is_binary(fleet_id),
    do:
      Regents.Keyfleet.Keys.identity(actor, fleet_id) != nil and
        Regents.Keyfleet.Chain.fresh?(fleet_id)

  def member?(_actor, _scope), do: false

  defp needed(action, component), do: @components |> Map.fetch!(component) |> Map.fetch!(action)

  defp rank(class), do: Enum.find_index(@classes, &(&1 == class))
end
