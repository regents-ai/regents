defmodule Regents.Keyfleet.Polls.Checks.Standing do
  @moduledoc """
  Who may do what in a fleet's polls, by the Key the actor takes part as
  (`Regents.Keyfleet.Polls.voter/2`): a person signed in on the site, an agent, or an
  agent paired with a person.

    * `role: :member`: anyone holding one of the fleet's Keys, or an active
      shard of one, starts polls, votes (a shard's vote while the Key's
      agent voting is on, `Regents.Keyfleet.Polls.Validations.AgentVoting`), and
      once a poll closes reads each Key's vote.
    * `role: :starter`: only the Key that started a poll ends it early.

  Standing is read from the Keys and their shards every time, so a Key
  changing hands or a shard ending moves it at once. While the fleet's Key
  ownership is not fresh, nobody has standing.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Keyfleet.Polls

  @impl true
  def describe(opts), do: "actor's Key is a #{Keyword.fetch!(opts, :role)} of the poll"

  @impl true
  def match?(actor, %{subject: subject}, opts) do
    fleet_id = Ash.Subject.get_argument_or_attribute(subject, :fleet_id)

    with true <- is_binary(fleet_id) and Regents.Keyfleet.Chain.fresh?(fleet_id),
         %{key: key} <- Polls.voter(actor, fleet_id) do
      standing?(Keyword.fetch!(opts, :role), key, fleet_id, subject)
    else
      _no_standing -> false
    end
  end

  defp standing?(:member, _key, _fleet_id, _subject), do: true

  defp standing?(:starter, key, fleet_id, %Ash.Changeset{
         data: %{started_by_key: key, fleet_id: fleet_id}
       }),
       do: true

  defp standing?(:starter, _key, _fleet_id, _subject), do: false
end
