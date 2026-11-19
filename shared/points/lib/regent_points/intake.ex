defmodule RegentPoints.Intake do
  @moduledoc """
  Takes an offer in the person's own action and answers `{:ok, _}` whatever the
  offer holds, so Points never refuses the action it rides in.

  A rule that is off answers `disabled` before anything else is looked at. With the
  rule on, an offer whose four reference fields are not each a string of 1 to 512
  bytes is set aside on its own: it answers `invalid`, queues nothing and logs one
  warning naming the rule, the source app and kind, and each field's size in bytes,
  never the source event key. Any other offer queues only its four reference fields
  in the action's own transaction (`RegentPoints.Enqueue`) and answers `queued`; the
  source's check and the award run later, in that job.

  An offer from the start run (`start_run: true`, `RegentPoints.StartAwards`) is
  queued at a lower Oban priority than a live one, and its award job keeps that
  priority, so a large start run waits behind live awards. An offer of a reference
  already waiting in the queue is that same job (`RegentPoints.IntakeWorker`).
  """
  use Ash.Resource.Actions.Implementation
  require Logger
  alias RegentPoints.{Enqueue, IntakeWorker, Rules}
  @keys ~w(rule_id source_app source_kind source_event_key)
  # Oban runs a lower priority only when no higher one is waiting; 0 is Oban's default.
  @start_priority 1
  @impl true
  def run(%{arguments: %{event: input, start_run: start_run}}, _, _) do
    reference = Map.new(input, fn {key, value} -> {to_string(key), value} end) |> Map.take(@keys)

    cond do
      not Rules.enabled?(reference["rule_id"]) ->
        {:ok, %{status: :disabled}}

      not Enum.all?(@keys, &(is_binary(reference[&1]) and byte_size(reference[&1]) in 1..512)) ->
        set_aside(reference)

      true ->
        priority = if start_run, do: @start_priority, else: 0
        Enqueue.call(IntakeWorker.new(reference, priority: priority))
    end
  end

  # The rule id is an approved one by now; the source app and kind are cut short,
  # since either may be the field out of bounds.
  defp set_aside(reference) do
    sizes = Map.new(@keys, &{&1, size(reference[&1])})

    Logger.warning(
      "Points set aside an offer for #{reference["rule_id"]} from " <>
        "#{short(reference["source_app"])} #{short(reference["source_kind"])}, " <>
        "field sizes in bytes: #{inspect(sizes)}"
    )

    {:ok, %{status: :invalid}}
  end

  defp size(value) when is_binary(value), do: byte_size(value)
  defp size(_value), do: nil

  defp short(value), do: inspect(value, printable_limit: 64, limit: 4)
end
