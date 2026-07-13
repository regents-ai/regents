defmodule AshPlatform.TestLocalAcceptanceDatabaseAdapter do
  @moduledoc false

  def child_spec(initial) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [initial]}}
  end

  def start_link(initial \\ []), do: Agent.start_link(fn -> initial end, name: __MODULE__)
  def stop, do: Agent.stop(__MODULE__)
  def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)

  def create(config), do: record({:create, config}, :ok)
  def prepare(config, run_id), do: record({:prepare, config, run_id}, :ok)
  def exists?(config), do: record({:exists?, config}, calls() |> database_present?())
  def verify_owned!(config, run_id), do: record({:verify_owned!, config, run_id}, :ok)
  def drop(config), do: record({:drop, config}, :ok)

  defp database_present?(calls) do
    Enum.count(calls, &match?({:create, _}, &1)) > Enum.count(calls, &match?({:drop, _}, &1))
  end

  defp record(call, result) do
    Agent.update(__MODULE__, &[call | &1])
    result
  end
end
