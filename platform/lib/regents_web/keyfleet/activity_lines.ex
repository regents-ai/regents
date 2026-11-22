defmodule RegentsWeb.Keyfleet.ActivityLines do
  @moduledoc """
  Tells an item of a fleet's activity (`Regents.Keyfleet.Activity`) as one plain
  line, in the style of an activity list: a sentence with no closing full
  stop, "Key 68 moved to 0xac95..4315".

  `parts/1` answers the sentence as a list of parts: the site's own words as
  text, and everything a member wrote or chose as one of

    * `{:key, token_id, agent}`: a key, with the name of its agent, or nil;
    * `{:item, id, title}`: an item of the workspace, by its title. An item
      read without its title, because it is no longer there or because the
      reader may not see it (`Regents.Keyfleet.Activity`), is named by its type
      alone, in the site's own words: "a task", "some evidence";
    * `{:room, slug, name}`: a room, by the name it was given if any;
    * `{:agent, name}`: an agent, by the name it gave itself;
    * `{:address, wallet}`: a wallet that acted with no Key or agent to name
      it, or one that Keys moved to;
    * `{:quote, text}`: words a member wrote;
    * `{:proposal, number}`: a proposal.

  Every member's words in the parts have been through
  `RegentsWeb.Keyfleet.DirectoryMD.visible/1`, so none can hide or reverse the
  sentence around them, wherever the sentence is shown. Numbers are written
  the one way every page writes them, "Key 1,234".

  `text/1` joins the parts for a web page, which escapes them itself.
  """

  alias Regents.Keyfleet.Fleets.Rules
  alias RegentsWeb.Keyfleet.DirectoryMD
  alias RegentsWeb.Keyfleet.WorkspacePage

  @created %{
    "goal" => " set a goal",
    "task" => " added a task",
    "finding" => " reported a finding",
    "evidence" => " added evidence",
    "service" => " proposed a service",
    "note" => " wrote a note",
    "dead_end" => " recorded a dead end"
  }

  # An item read without its title, named by its type.
  @untitled %{
    "goal" => "a goal",
    "task" => "a task",
    "finding" => "a finding",
    "evidence" => "some evidence",
    "service" => "a service",
    "note" => "a note",
    "dead_end" => "a dead end",
    "review" => "a review"
  }
  @unknown_type "an item"

  @plural %{
    "goal" => "goals",
    "task" => "tasks",
    "finding" => "findings",
    "evidence" => "pieces of evidence",
    "service" => "services",
    "note" => "notes",
    "dead_end" => "dead ends",
    "review" => "reviews"
  }

  # A run of one change: the words before and after the items' count.
  @changes %{
    archived: {" archived ", ""},
    submitted: {" submitted ", " for review"},
    revised: {" revised ", ""}
  }

  # How a Key reached its first owner.
  @first_owner %{sale: "bought", given: "given"}
  @untitled_words [@unknown_type | Map.values(@untitled)]

  # The Keys a moved line names before counting the rest.
  @listed 3

  @doc "The item as one line for a web page."
  def text(item), do: item |> parts() |> Enum.map_join(&shown/1)

  @doc "The item as a list of parts; see the module documentation."
  def parts(item), do: item |> sentence() |> opening()

  @channels %{
    chat: ~w(post posts room_named)a,
    work:
      ~w(created tasks submitted progress status reviewed revised joined left archived changes linked)a,
    keys: ~w(sale given moved shard_issued shard_ended)a,
    votes: ~w(proposed votes executed)a
  }
  @channel_of for {channel, kinds} <- @channels, kind <- kinds, into: %{}, do: {kind, channel}

  @doc """
  The channel an item of the hall's feed belongs to: `:chat` for what was
  said in the rooms, `:work` for the workspace, `:keys` for Keys and their
  shards, and `:votes` for proposals.
  """
  def channel(%{kind: kind}), do: Map.fetch!(@channel_of, kind)

  # A sentence that opens on an item named by its type opens with a capital.
  defp opening([words | rest]) when words in @untitled_words,
    do: [String.capitalize(words) | rest]

  defp opening(parts), do: parts

  defp sentence(%{kind: :post, facts: f}),
    do: [key(f.by), " in ", room(f.room), ": ", words(f.excerpt)]

  defp sentence(%{kind: :posts, facts: f}) do
    ["#{Rules.grouped(f.count)} posts in ", room(f.room), " from "] ++
      listing(Enum.map(f.keys, &key/1), f.others) ++ [": ", words(f.excerpt)]
  end

  defp sentence(%{kind: :room_named, facts: f}),
    do: [key(f.by), " named a room ", words(f.topic)]

  defp sentence(%{kind: :tasks, facts: f}), do: [who(f.by), " added #{tasks(f.added)}"]

  defp sentence(%{kind: :created, facts: %{by: by, item: item}}) do
    case {Map.fetch(@created, item.type), item.title} do
      {{:ok, did}, nil} -> [who(by), did]
      {{:ok, did}, _title} -> [who(by), did, ": ", item(item) | confidence(item)]
      {:error, _title} -> [who(by), " added ", item(item)]
    end
  end

  defp sentence(%{kind: :submitted, facts: f}),
    do: [who(f.by), " submitted ", item(f.item), " for review"]

  defp sentence(%{kind: :reviewed, facts: %{decision: "accept"} = f}),
    do: [who(f.by), " accepted ", item(f.item)]

  defp sentence(%{kind: :reviewed, facts: %{decision: "dispute"} = f}),
    do: [who(f.by), " disputed ", item(f.item)]

  defp sentence(%{kind: :progress, facts: f}),
    do: [who(f.by), " marked ", item(f.item), " " <> choice("progress", f.progress)]

  defp sentence(%{kind: :status, facts: %{status: "open"} = f}),
    do: [who(f.by), " reopened ", item(f.item)]

  defp sentence(%{kind: :status, facts: f}),
    do: [who(f.by), " marked ", item(f.item), " #{f.status}"]

  defp sentence(%{kind: :revised, facts: f}), do: [who(f.by), " revised ", item(f.item)]
  defp sentence(%{kind: :joined, facts: f}), do: [who(f.by), " joined ", item(f.item)]
  defp sentence(%{kind: :left, facts: f}), do: [who(f.by), " left ", item(f.item)]
  defp sentence(%{kind: :archived, facts: f}), do: [who(f.by), " archived ", item(f.item)]

  defp sentence(%{kind: :changes, facts: f}) do
    {did, rest} = Map.fetch!(@changes, f.change)
    [who(f.by), did, "#{Rules.grouped(f.count)} #{Map.get(@plural, f.type, "items")}#{rest}"]
  end

  defp sentence(%{kind: :linked, facts: %{relation: "supports"} = f}),
    do: [who(f.by), " backed ", item(f.target), " with ", item(f.source)]

  defp sentence(%{kind: :linked, facts: %{relation: "contradicts"} = f}),
    do: [who(f.by), " raised a problem with ", item(f.target), ": ", item(f.source)]

  defp sentence(%{kind: :linked, facts: %{relation: "produces"} = f}),
    do: [item(f.source), " produced ", item(f.target)]

  defp sentence(%{kind: kind, facts: %{token_ids: [token_id]}}) when kind in [:sale, :given],
    do: ["Key #{Rules.grouped(token_id)} was #{@first_owner[kind]}"]

  defp sentence(%{kind: kind, facts: %{token_ids: [first | _] = token_ids}})
       when kind in [:sale, :given] do
    last = List.last(token_ids)

    keys =
      if token_ids == Enum.to_list(first..last),
        do: "Keys #{Rules.grouped(first)}–#{Rules.grouped(last)}",
        else: Rules.keys(length(token_ids))

    ["#{keys} were #{@first_owner[kind]}"]
  end

  # A run of transfers to one wallet (`RegentsWeb.Keyfleet.FeedLines`).
  defp sentence(%{kind: :moved, facts: f}),
    do: moved(f.token_ids) ++ [" moved to ", {:address, f.to}]

  defp sentence(%{kind: :shard_issued, facts: f}),
    do: [
      shard_holder(f),
      " holds a shard of Key #{Rules.grouped(f.token_id)} until " <>
        Calendar.strftime(f.expires_at, "%-d %B %Y")
    ]

  defp sentence(%{kind: :shard_ended, facts: %{stepped_down?: true} = f}),
    do: [shard_holder(f), " stepped down from its shard of Key #{Rules.grouped(f.token_id)}"]

  defp sentence(%{kind: :shard_ended, facts: f}),
    do: [
      "The owner of Key #{Rules.grouped(f.token_id)} ended the shard of ",
      shard_holder(f)
    ]

  defp sentence(%{kind: :proposed, facts: f}),
    do: [holder(f.proposer), " put ", proposal(f), " to a vote"]

  defp sentence(%{kind: :votes, facts: f}) do
    votes =
      [voted(f.yes, :yes), voted(f.no, :no), voted(f.abstain, :abstain)]
      |> Enum.reject(&is_nil/1)
      |> Enum.intersperse([" and "])
      |> List.flatten()

    votes ++ [" on ", proposal(f)]
  end

  defp sentence(%{kind: :executed, facts: f}), do: [proposal(f), " was carried out"]

  # A change the workspace itself made names no key.
  defp who(nil), do: "Keyfleet"
  defp who(by), do: key(by)

  # Someone who wrote as no key, in the People and agents room before posting
  # there needed one: an agent by its name, a person by their wallet.
  defp key(%{token_id: nil, agent: nil, wallet: wallet}), do: {:address, wallet}
  defp key(%{token_id: nil, agent: agent}), do: {:agent, visible(agent)}
  defp key(%{token_id: token_id, agent: nil}), do: {:key, token_id, nil}
  defp key(%{token_id: token_id, agent: agent}), do: {:key, token_id, visible(agent)}

  defp item(%{type: type, title: nil}), do: Map.get(@untitled, type, @unknown_type)

  # A title with nothing left to see once cleaned still names its item.
  defp item(%{id: id, title: title}) do
    case visible(title) do
      "" -> {:item, id, "An item"}
      title -> {:item, id, title}
    end
  end

  defp room(room), do: {:room, room.slug, visible(room.topic || room.name)}

  # A shard's agent by name, or its wallet while no agent has signed in with it.
  defp shard_holder(%{agent: nil, wallet: wallet}), do: {:address, wallet}
  defp shard_holder(%{agent: agent}), do: {:agent, visible(agent.name)}

  defp words(text), do: {:quote, visible(text)}

  defp proposal(%{number: number}), do: {:proposal, number}

  defp visible(text), do: DirectoryMD.visible(text)

  # A choice in the words the workspace page gives it, within a sentence.
  defp choice(field, value), do: field |> WorkspacePage.choice(value) |> String.downcase()

  defp confidence(%{type: "finding", confidence: confidence}) when is_binary(confidence),
    do: [" (#{choice("confidence", confidence)} confidence)"]

  defp confidence(_item), do: []

  defp holder(%{token_id: token_id}) when is_integer(token_id),
    do: "The holder of Key #{Rules.grouped(token_id)}"

  defp holder(%{wallet: wallet}), do: {:address, wallet}

  defp voted(%{count: 0}, _word), do: nil

  defp voted(%{count: count, token_ids: token_ids}, side),
    do: keys(token_ids, count - length(token_ids)) ++ [did(side, count)]

  # "Key 4", "Keys 4, 5 and 8", "Keys 4, 5, 8 and 2 others".
  defp keys(token_ids, others) do
    lead = if length(token_ids) + others == 1, do: "Key ", else: "Keys "
    [lead | listing(Enum.map(token_ids, &Rules.grouped/1), others)]
  end

  # Three Keys or more numbered one after another read as a range: "Keys
  # 4–9"; any others as "Keys 4, 5, 8 and 2 others".
  defp moved([first, _, _ | _] = token_ids) do
    last = List.last(token_ids)

    if token_ids == Enum.to_list(first..last),
      do: ["Keys #{Rules.grouped(first)}–#{Rules.grouped(last)}"],
      else: listed(token_ids)
  end

  defp moved(token_ids), do: listed(token_ids)

  defp listed(token_ids),
    do: keys(Enum.take(token_ids, @listed), max(length(token_ids) - @listed, 0))

  defp tasks(1), do: "a task"
  defp tasks(count), do: "#{Rules.grouped(count)} tasks"

  defp did(:yes, _count), do: " voted yes"
  defp did(:no, _count), do: " voted no"
  defp did(:abstain, _count), do: " abstained"

  # "A", "A and B", "A, B and C", "A, B, C and 2 others".
  defp listing(parts, 0), do: joined(parts)
  defp listing(parts, 1), do: joined(parts ++ ["1 other"])
  defp listing(parts, others), do: joined(parts ++ ["#{Rules.grouped(others)} others"])

  defp joined([only]), do: [only]

  defp joined(parts) do
    {rest, [last]} = Enum.split(parts, -1)
    Enum.intersperse(rest, ", ") ++ [" and ", last]
  end

  @doc ~S|How a key is named on a page: "Key 1,234", or "Ada (Key 1,234)" when an agent wrote as it.|
  def key_name(token_id, nil), do: "Key #{Rules.grouped(token_id)}"
  def key_name(token_id, agent), do: "#{agent} (Key #{Rules.grouped(token_id)})"

  @doc ~S|How a proposal is named on a page: "Proposal 12".|
  def proposal_name(number), do: "Proposal #{Rules.grouped(number)}"

  defp shown(text) when is_binary(text), do: text
  defp shown({:key, token_id, agent}), do: key_name(token_id, agent)
  defp shown({:item, _id, title}), do: "“#{title}”"
  defp shown({:room, _slug, name}), do: name
  defp shown({:agent, name}), do: name
  defp shown({:address, wallet}), do: RegentFormat.short_address(wallet)
  defp shown({:quote, text}), do: "“#{plain(text)}”"
  defp shown({:proposal, number}), do: proposal_name(number)

  @doc """
  A member's quoted words as a web page shows them: Markdown's heading
  hashes, bold and code marks dropped, and a link as its words. Posts are
  written in Markdown and quoted from their start, so a quote can carry marks
  that only mean something in the full post.
  """
  def plain(text) do
    text
    |> String.replace(~r/\[([^\]]+)\]\([^)\s]*\)/u, "\\1")
    |> String.replace(~r/(^|\s)\#{1,6}\s+/u, "\\1")
    |> then(&Regex.replace(~r/`([^`]*)`|\*\*|__|`/u, &1, fn _mark, code -> code end))
    |> String.trim()
  end
end
