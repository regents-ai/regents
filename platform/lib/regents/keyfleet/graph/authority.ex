defmodule Regents.Keyfleet.Graph.Authority do
  @moduledoc """
  The rules that decide a graph write's authority at its turn, each by a fixed
  name. There is one today, the workspace command rule:
  `{:workspace_command, actor, as_key, command_id}`, where `actor` names who
  the write is for (`Regents.Keyfleet.Graph.ActorRef`). It reads that actor's standing
  on the Key it acts as (`Regents.Keyfleet.Graph.Checks.KeyActor.command/5`) and the
  state of each of the fleet's projects then.

  A rule travels to the graph machine as data (`encode/1`, `parse/1`), and
  the writer runs it by matching its name (`command/3`): nothing the site sends
  names code, and the actor is rebuilt from the database.
  """

  require Logger

  alias Regents.Keyfleet.Graph.ActorRef
  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Graph.Errors.EditsRestrictedError
  alias Regents.Keyfleet.Graph.Errors.NotKeyHolderError
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects

  @bigint 9_223_372_036_854_775_807

  @type t :: {:workspace_command, ActorRef.t(), pos_integer(), String.t()}

  @doc "The workspace command rule for a write by `actor` as the Key `as_key`."
  @spec workspace_command(struct(), pos_integer(), String.t()) :: t()
  def workspace_command(actor, as_key, command_id),
    do: {:workspace_command, ActorRef.from_actor(actor), as_key, command_id}

  @doc "The rule as JSON carries it."
  @spec encode(t()) :: map()
  def encode({:workspace_command, actor, as_key, command_id}) do
    %{
      "rule" => "workspace_command",
      "actor" => actor,
      "as_key" => as_key,
      "command_id" => command_id
    }
  end

  @doc "The rule `encode/1` made, or `:error` for anything else."
  @spec parse(term()) :: {:ok, t()} | :error
  def parse(
        %{
          "rule" => "workspace_command",
          "actor" => actor,
          "as_key" => as_key,
          "command_id" => command_id
        } = rule
      )
      when map_size(rule) == 4 and is_integer(as_key) and as_key in 1..@bigint and
             is_binary(command_id) do
    if ActorRef.valid?(actor),
      do: {:ok, {:workspace_command, actor, as_key, command_id}},
      else: :error
  end

  def parse(_term), do: :error

  @doc """
  The command a write carries, read now, the actor and its standing within
  `within` milliseconds and the fleet's projects then under the database's
  usual time limit: `{:ok, command}`, its `:id`, `:principal`, `:auth` and
  the fleet's `:projects`, each project that is not deleted by name with its
  state, `active` or `archived`; the actor's standing refused, as
  `Regents.Keyfleet.Graph.Errors.NotKeyHolderError`, `EditsRestrictedError` or
  `Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError`; or `{:error,
  :unavailable}` when that standing could not be read, which is logged.
  """
  @spec command(t(), String.t(), pos_integer()) ::
          {:ok, map()} | {:error, Exception.t() | :unavailable}
  def command({:workspace_command, ref, as_key, command_id}, fleet_id, within) do
    deadline = System.monotonic_time(:millisecond) + within

    with {:ok, actor} <- ActorRef.actor(ref, context: %{data_layer: %{timeout: within}}),
         left = deadline - System.monotonic_time(:millisecond),
         {:ok, command} <- KeyActor.command(actor, fleet_id, as_key, command_id, left),
         {:ok, projects} <- Projects.projects(fleet_id, actor: %Regents.Account.Actors.System{}) do
      {:ok, Map.put(command, :projects, Map.new(projects, &{&1.name, &1.state}))}
    else
      {:error, %NotKeyHolderError{}} = refused -> refused
      {:error, %EditsRestrictedError{}} = refused -> refused
      {:error, %OwnershipRefreshingError{}} = refused -> refused
      {:error, error} -> unreadable(fleet_id, error)
    end
  end

  defp unreadable(fleet_id, error) do
    Logger.warning(
      "graph write for #{fleet_id} not sent: its ownership check failed: " <> reason(error)
    )

    {:error, :unavailable}
  end

  # What went wrong, on one line: an error that gathers others, as Ash's do,
  # by each error it holds, and each error by the first line of its message,
  # which names its kind, without the trail of where it was passed along.
  defp reason(%{errors: [_ | _] = errors}), do: Enum.map_join(errors, "; ", &reason/1)
  defp reason(%{bread_crumbs: [_ | _]} = error), do: reason(%{error | bread_crumbs: []})
  defp reason(error), do: error |> Exception.message() |> String.split("\n", parts: 2) |> hd()
end
