defmodule Regents.Keyfleet.Graph.Validations.WriteAllowance do
  @moduledoc """
  Each agent wallet's allowance of workspace writes in each fleet
  (`Regents.Limits`, `:keyfleet_graph_writes`), spent before the write takes the
  fleet's one writer, whichever way the agent called: its own signed request
  or the Claude connector. It is spent before the write is authorized, so a
  write refused for the Key it names spends it too, and nobody probes Keys
  for free. A connector tool's input checked before the tool runs
  (`RegentsWeb.Keyfleet.ToolErrors.check_input/3`, `input_check` in its context)
  spends nothing: the run that follows spends it. Nor does a preview of a
  write, which runs the action with `input_check` and writes nothing
  (`RegentsWeb.Keyfleet.Preview`). It is kept by wallet, not
  by the Key a write names: that Key is checked only later, so anyone could
  spend another Key's allowance by naming it.
  """
  use Ash.Resource.Validation

  alias Regents.Account.Actors.Agent
  alias Regents.Keyfleet.Graph.Errors.WriteLimitError

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(%{context: %{input_check: true}}, _opts, _context), do: :ok

  def validate(input, _opts, %{actor: %Agent{wallet_address: wallet}}) do
    fleet_id = Ash.ActionInput.get_argument(input, :fleet_id)

    case Regents.Limits.admit(:keyfleet_graph_writes, {fleet_id, wallet}) do
      :ok ->
        :ok

      {:limited, seconds} ->
        {:error, WriteLimitError.exception(fleet_id: fleet_id, retry_after: seconds)}
    end
  end

  def validate(_input, _opts, _context), do: :ok
end
