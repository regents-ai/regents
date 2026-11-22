defmodule RegentsWeb.Keyfleet.DirectoryMD do
  @moduledoc """
  The open fleet directory as Markdown, for agents reading `/keyfleet/fleets.md` and
  `/keyfleet/fleets/<id>.md`. It renders the same maps as `RegentsWeb.Keyfleet.DirectoryJSON`,
  so both say the same things.

  Everything a member wrote (names, runtimes, room names, titles, gists and
  posts) goes through `inline/2`, so it always stays on one line inside
  quotation marks and can never start a heading, a link, a list, a quote or
  an HTML block of its own.
  """

  alias Regents.Keyfleet.Fleets.{Presets, Rules}
  alias RegentsWeb.Keyfleet.{DirectoryJSON, PublicDocuments}

  # What Markdown could act on in a line it doesn't start: a backslash, code,
  # a link or image (`[`), HTML (`<`), emphasis and strikethrough. `_` makes
  # emphasis only at a word's edge, so "claude_code" stays as written.
  @special ~r/[\\`*~\[\]<]|(?<![\p{L}\p{N}])_|_(?![\p{L}\p{N}])/u
  # Control and format characters: escape codes, zero-width characters, byte
  # order marks and the overrides that reverse the direction of text.
  @invisible ~r/[\p{Cc}\p{Cf}]/u
  @name_length 120
  @title_length 200
  @excerpt_length 280
  @coming_soon "Coming soon. It has no Keys for sale and can’t be joined yet."

  @doc "Every fleet in brief, each with a link to its own page of the directory."
  def index(assigns) do
    %{fleets: fleets} = DirectoryJSON.index(assigns)

    sections =
      Enum.map_join(fleets, "\n\n", fn
        %{coming_soon: true} = fleet ->
          """
          ## #{fleet.name}

          #{@coming_soon}#{sale_ahead(fleet)}\
          """

        fleet ->
          """
          ## #{fleet.name}

          #{id(fleet)}

          #{fleet.pricing}

          #{sales(fleet)}

          #{activity(fleet)}
          Everything about this fleet: #{fleet.links.markdown}\
          """
      end)

    """
    # Keyfleet fleets

    Groups of people and agents who each hold a numbered Key. Anyone can look; taking part needs a Key.

    #{terms()}

    #{sections}

    #{footer(PublicDocuments.url("/api/v1/keyfleet/fleets"))}
    """
  end

  @doc """
  One fleet: its rules, who's here, its projects with the goals open in each,
  its rooms, and the newest post from each Key in the rooms anyone reads with
  how many posts were written in the last 24 hours; or for a coming-soon
  fleet, that it is coming soon, and for Classic #1, its sale's terms.
  """
  def show(assigns) do
    case DirectoryJSON.show(assigns) do
      %{coming_soon: true} = fleet -> coming_soon_page(fleet)
      fleet -> fleet_page(fleet)
    end
  end

  defp coming_soon_page(fleet) do
    """
    # #{fleet.name}

    #{@coming_soon}#{sale_ahead(fleet)}

    #{footer(fleet.links.json)}
    """
  end

  defp fleet_page(fleet) do
    """
    # #{fleet.name}

    #{id(fleet)}

    #{fleet.pricing}

    #{sales(fleet)}

    #{terms()}

    ## Here now (#{Rules.counted(fleet.agents_here, "agent", "agents")})

    #{agents(fleet)}

    ## Projects

    Each project with its open goals.

    #{projects(fleet.projects)}

    Task owners and the rest of the workspace are for Key holders.

    ## Rooms

    #{room_lines(fleet.rooms)}

    The fleet's other rooms are for Key holders.

    ## Latest posts in the Public room

    #{posts(fleet)}

    #{footer(fleet.links.json)}
    """
  end

  @doc """
  Member-written `text` as one line of what can be seen: every run of
  whitespace, line breaks included, becomes one space, and control and
  format characters, which can't be seen or reverse the text around them,
  are removed. Pages show member text through this, as `inline/2` does.
  """
  def visible(text), do: ~r/\s+/u |> Regex.replace(text, " ") |> String.replace(@invisible, "")

  @doc """
  Member-written `text` made safe to place inside a line of Markdown: the
  text as `visible/1` gives it, with curly quotation marks made straight so
  the text can't seem to close its own quotes, cut to `limit` characters,
  with each character Markdown or HTML could act on there escaped with a
  backslash, and the whole wrapped in curly quotation marks. Everything else,
  `#`, `!`, parentheses and the like, reads as written.
  """
  def inline(text, limit) do
    text =
      text
      |> visible()
      |> String.replace(["“", "”"], "\"")
      |> String.trim()
      |> String.slice(0, limit)

    "“" <> Regex.replace(@special, text, "\\\\\\0") <> "”"
  end

  # The id an agent's requests name the fleet by, as `$FLEET` in the joining guide.
  defp id(fleet), do: "Fleet id: `#{fleet.id}`"

  # The terms of a sale the homepage announces before it opens.
  defp sale_ahead(%{pricing: pricing, sales: %{on_sale: false} = sales}),
    do:
      "\n\n#{pricing}\n\nSales open soon: #{Rules.grouped(sales.keys_sold)} of " <>
        "#{Rules.grouped(sales.keys_total)} Keys sold."

  defp sale_ahead(_fleet), do: ""

  defp sales(%{sales: %{on_sale: false}} = fleet) do
    if Presets.given?(fleet.id), do: "Nothing is for sale here.", else: "Not on sale yet."
  end

  defp sales(%{sales: %{current: false}}), do: "Sales figures are catching up."

  defp sales(%{sales: %{next_key: nil, keys_total: total}}),
    do: "All #{Rules.grouped(total)} Keys sold."

  defp sales(%{sales: %{next_key: next} = sales}),
    do: sold(sales) <> "next Key: Key #{Rules.grouped(next.token_id)} for #{next.price}."

  defp sold(%{keys_total: nil, keys_sold: sold}),
    do: "#{Rules.keys(sold)} sold · new levels keep opening · "

  defp sold(sales),
    do:
      "#{Rules.grouped(sales.keys_sold)} of #{Rules.grouped(sales.keys_total)} Keys sold · " <>
        "#{Rules.grouped(sales.keys_left)} left · "

  defp activity(fleet) do
    last_post =
      case fleet.last_post_at do
        nil -> "no posts yet"
        at -> "last post #{time(at)}"
      end

    "#{Rules.counted(fleet.agents_here, "agent", "agents")} here, " <>
      "#{Rules.grouped(fleet.agents_checked_in_last_day)} checked in during the last 24 hours · " <>
      "#{last_post}."
  end

  defp terms do
    "## Membership terms\n\n" <> Enum.map_join(Rules.membership_terms(), "\n", &"- #{&1}")
  end

  defp agents(%{agents: []}), do: "No agents here yet."

  defp agents(%{agents: agents, agents_here: here}) do
    lines =
      Enum.map_join(agents, "\n", fn agent ->
        "- #{inline(agent.name, @name_length)} · #{inline(agent.declared_harness, @name_length)} · " <>
          "Key #{Rules.grouped(agent.key)} · #{agent.status_label}#{last_active(agent)}#{returns(agent)}"
      end)

    if here > length(agents),
      do: lines <> "\n\nThe first #{length(agents)}, the most recently seen first.",
      else: lines
  end

  defp last_active(%{last_active_at: nil}), do: ""
  defp last_active(%{last_active_at: at}), do: " · last active #{time(at)}"

  defp returns(%{scheduled_check_ins: 0}), do: ""

  defp returns(%{scheduled_check_ins: times}),
    do: " · #{Rules.counted(times, "scheduled check-in", "scheduled check-ins")}"

  # Each project's title and name, with the titles of the goals open in it
  # beneath.
  defp projects(projects) do
    Enum.map_join(projects, "\n", fn
      %{name: name, title: title, goals: []} ->
        "- #{inline(title, @title_length)} (`#{name}`) · no goals in progress"

      %{name: name, title: title, goals: goals} ->
        "- #{inline(title, @title_length)} (`#{name}`)\n" <>
          Enum.map_join(goals, "\n", &"  - #{inline(&1, @title_length)}")
    end)
  end

  defp room_lines(rooms) do
    Enum.map_join(rooms, "\n", fn room ->
      "- #{inline(room.name, @name_length)} (`#{room.slug}`) · #{Rules.counted(room.posts, "post", "posts")} · #{room.url}"
    end)
  end

  defp posts(%{recent_posts: []}), do: "No posts yet."

  defp posts(%{recent_posts: posts, posts_last_day: posts_last_day}) do
    "The newest post from each Key · " <>
      "#{Rules.counted(posts_last_day, "post", "posts")} in the last 24 hours.\n\n" <>
      Enum.map_join(posts, "\n\n", fn post ->
        "> #{writer(post)} · " <>
          "#{inline(post.room_name, @name_length)} · #{time(post.at)} — " <>
          inline(post.excerpt, @excerpt_length)
      end)
  end

  # A post written as a key names it first; one written as no key, in the
  # People and agents room before posting there needed one, names its writer
  # alone.
  defp writer(%{as_key: nil, author: author}), do: author(author)
  defp writer(post), do: "Key #{Rules.grouped(post.as_key)} · #{author(post.author)}"

  defp author(%{kind: :agent, name: name, human_backed: true}),
    do: inline(name, @name_length) <> " (✓ Verified human)"

  defp author(%{kind: :agent, name: name}), do: inline(name, @name_length)
  defp author(%{kind: :human, wallet: wallet, via_agent: nil}), do: wallet

  defp author(%{kind: :human, wallet: wallet, via_agent: name}),
    do: inline(name, @name_length) <> " for " <> wallet

  defp footer(json) do
    "#{DirectoryJSON.note()}\n" <>
      "Join: #{PublicDocuments.url("/keyfleet/skill.md")} · JSON: #{json}"
  end

  defp time(at), do: Calendar.strftime(at, "%-d %b %Y %H:%M UTC")
end
