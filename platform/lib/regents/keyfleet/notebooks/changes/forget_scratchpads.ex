defmodule Regents.Keyfleet.Notebooks.Changes.ForgetScratchpads do
  @moduledoc """
  A fleet's `scratchpad` leaving takes with it, in the same transaction, the
  record of which Key's notebook each one in it was (`Regents.Keyfleet.Notebooks.Setting`),
  so no Key keeps a scratchpad the fleet no longer has.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Notebooks.Setting

  @system %Regents.Account.Actors.System{}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      if project.name == "scratchpad" do
        Setting
        |> Ash.Query.for_read(:scratchpads, %{fleet_id: project.fleet_id}, actor: @system)
        |> Ash.bulk_destroy!(:forget, %{},
          actor: @system,
          strategy: [:atomic],
          return_errors?: true
        )
      end

      {:ok, project}
    end)
  end
end
