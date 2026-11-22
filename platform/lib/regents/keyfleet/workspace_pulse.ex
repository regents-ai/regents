defmodule Regents.Keyfleet.WorkspacePulse do
  @moduledoc """
  The public outline of work recorded by one fleet: who worked on which
  project, one line per notable change, newest first.

    * "Agent Muse with Key 20³ worked on Lab": an agent, by the name it goes
      by in its Regent pairing (`Regents.Account.Agents.Pairing`).
    * "Agent of Key 20³ worked on Lab": an agent with no name there.
    * "Holder of Key 20³ worked on Lab": a person working from the page.

  The Key is the one the change was made as; the raised number is how many
  of the fleet's Keys that Key's holder has now, left off when no holder of
  it is recorded; the project is told by its title. Each line also gives its
  parts apart (`agent_name`, `key`, `keys_held`, `project_title`, `at`), so
  a page draws the raised number.
  The workspace's own changes, and changes to a deleted project, are left
  out. `next_after` is the newest change read; passed back as `after`, the
  next read holds only the changes made since, oldest thirty first, and
  `has_more` says more follow. No item, its title or any text an item holds leaves this boundary;
  members use the signed workspace reads for those.
  """

  alias Regents.Keyfleet.{Fleets, Graph, Keys, Notebooks, Projects}
  alias Regents.Keyfleet.Fleets.Rules

  @shown 30

  @raised %{
    ?0 => "⁰",
    ?1 => "¹",
    ?2 => "²",
    ?3 => "³",
    ?4 => "⁴",
    ?5 => "⁵",
    ?6 => "⁶",
    ?7 => "⁷",
    ?8 => "⁸",
    ?9 => "⁹"
  }

  @doc """
  The latest thirty notable changes, or with `after` the next thirty made
  after it, newest first either way; or an explicit read failure.
  """
  def read(fleet_id, after_seq) do
    if fleet_id in Fleets.open_fleet_ids() do
      with {:ok, events, more?} <- notable(fleet_id, after_seq),
           {:ok, projects} <- Projects.project_titles(fleet_id) do
        {:ok,
         %{
           fleet_id: fleet_id,
           generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
           notebooks_configured: Notebooks.hub?(fleet_id),
           activity: lines(fleet_id, events, Map.new(projects, &{&1.name, &1.title})),
           next_after: next_after(events, after_seq),
           has_more: more?
         }}
      end
    else
      :unknown
    end
  end

  defp notable(fleet_id, nil) do
    with {:ok, events} <- Graph.notable_before(fleet_id, nil, @shown),
         do: {:ok, events, false}
  end

  defp notable(fleet_id, after_seq) do
    with {:ok, events} <- Graph.notable_after(fleet_id, after_seq, @shown + 1) do
      {shown, rest} = Enum.split(events, @shown)
      {:ok, Enum.reverse(shown), rest != []}
    end
  end

  # The newest change read, so the next read starts after it; with none read,
  # where this one started.
  defp next_after([newest | _older], _after_seq), do: Integer.to_string(newest.seq)
  defp next_after([], after_seq), do: Integer.to_string(after_seq || 0)

  defp lines(fleet_id, events, titles) do
    worked =
      for event <- events,
          {token_id, kind, wallet} <- [Graph.Event.member(event.actor)],
          title = Enum.find_value(event.projects, &titles[&1]),
          do: {event, token_id, kind, wallet, title}

    held = Keys.faces(fleet_id, worked |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
    names = names(for {_event, _key, "agent", wallet, _title} <- worked, uniq: true, do: wallet)

    for {event, token_id, kind, wallet, title} <- worked do
      name = if kind == "agent", do: names[wallet]
      keys_held = held[token_id][:owned]

      %{
        seq: event.seq,
        at: event.timestamp,
        text:
          "#{who(kind, name)} Key #{Rules.grouped(token_id)}#{raised(keys_held)} worked on #{title}",
        agent_name: name,
        key: token_id,
        keys_held: keys_held,
        project_title: title
      }
    end
  end

  defp who("agent", nil), do: "Agent of"
  defp who("agent", name), do: "Agent #{name} with"
  defp who("human", _name), do: "Holder of"

  defp raised(nil), do: ""

  defp raised(count),
    do: count |> Integer.to_string() |> String.to_charlist() |> Enum.map_join(&@raised[&1])

  defp names([]), do: %{}

  defp names(wallets) do
    wallets
    |> Regents.Account.Agents.pairings_by_wallets!(actor: %Regents.Account.Actors.System{})
    |> Map.new(&{&1.wallet, &1.name})
  end
end
