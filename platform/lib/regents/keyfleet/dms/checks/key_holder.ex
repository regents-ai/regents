defmodule Regents.Keyfleet.Dms.Checks.KeyHolder do
  @moduledoc """
  Whether the actor may read and send as the Keys a direct-message action names,
  right now: the Keys `Regents.Keyfleet.Keys.held_keys/2` gives it in the fleet (its
  holder, an agent with an active shard of it, or an agent paired with its
  holder). Nothing about this is stored: a Key's new holder reads as it at
  once, and sees only messages from when they got it (`Regents.Keyfleet.Dms.Message`'s
  `shown_to`). While the fleet's key ownership is not fresh, nobody holds
  anything.

  `keys:` names the arguments or attributes holding the Keys, each a number or
  a list of numbers. With `match: :all` (the default) the actor must hold every
  Key named; with `match: :any`, one of them, as either side of a conversation
  may change it.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Keyfleet.Keys

  @impl true
  def describe(opts) do
    case Keyword.get(opts, :match, :all) do
      :all -> "actor holds every Key in #{inspect(opts[:keys])} now"
      :any -> "actor holds one of the Keys in #{inspect(opts[:keys])} now"
    end
  end

  @impl true
  def match?(actor, %{subject: subject}, opts) do
    fleet_id = Ash.Subject.get_argument_or_attribute(subject, :fleet_id)

    named =
      opts
      |> Keyword.fetch!(:keys)
      |> Enum.flat_map(&List.wrap(Ash.Subject.get_argument_or_attribute(subject, &1)))

    named != [] and is_binary(fleet_id) and
      held?(named, held(actor, fleet_id), Keyword.get(opts, :match, :all))
  end

  @doc """
  The Keys `actor` may read and send as in the fleet now, as numbers; none
  while the fleet's key ownership is not fresh.
  """
  def held(actor, fleet_id) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: Enum.map(Keys.held_keys(actor, fleet_id), & &1.token_id),
      else: []
  end

  defp held?(named, held, :all), do: Enum.all?(named, &(&1 in held))
  defp held?(named, held, :any), do: Enum.any?(named, &(&1 in held))
end
