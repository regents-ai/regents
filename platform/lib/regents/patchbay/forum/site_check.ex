defmodule Regents.Patchbay.Forum.SiteCheck do
  @moduledoc """
  What a site offers agents, as Patchbay last found it: one row per
  registrable domain, whether or not the site has a board.

  `requested_at` is when a check was last asked for and `checked_at` when the
  last one finished. What it found is the one source of a site's tool count:
  the directory, the board and the JSON at `/sites` all read it.

  A finished check is to be told to open pages on `topic/1`. The table and
  its rows as patchbay.help keeps them. Patchbay's pages read them and listen
  on that topic; nothing here writes them or tells it yet: asking for a check
  and the check itself come with Patchbay's background work.
  """

  alias Regents.Patchbay.Forum.Origin

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("site_checks")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :domain, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: Origin.max_host_length())
    end

    # The last findings; nil before the first check. Failures keep previous findings.
    attribute(:findings, :map, allow_nil?: true, public?: true)

    attribute(:requested_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:checked_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    # The front page the last finished check read; empty when it read none.
    attribute :page_url, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: Origin.max_address_length())
    end

    # When the last check read that page whole, every script on the site's
    # own domain included; empty when it read it in part or not at all, and
    # after a check that could not be done.
    attribute(:page_read_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    timestamps()
  end

  calculations do
    # The directory pages the last check read in full, with their tool lists.
    calculate(
      :read_directory_pages,
      {:array, :string},
      expr(
        fragment(
          "array(select key from jsonb_each(? -> 'directory') where jsonb_typeof(value -> 'tools') = 'array')",
          findings
        )
      )
    )

    # Whether the last finished check found a WebMCP tool on the front page or
    # on any page the directory lists: the rule `tools/1` counts by.
    calculate(
      :found_tools?,
      :boolean,
      expr(
        fragment(
          "coalesce(jsonb_path_exists(?, '$.webmcp[*]') or jsonb_path_exists(?, '$.directory.*.tools[*]'), false)",
          findings,
          findings
        )
      )
    )
  end

  identities do
    identity(:unique_domain, [:domain])
  end

  actions do
    defaults([:read])

    read :without_tools do
      description("""
      Checks that found no WebMCP tool, on the front page or on any directory
      page they read, each with the pages it read: the directory leaves out
      the sites whose every page is among them.
      """)

      filter(
        expr(fragment("jsonb_typeof(? -> 'directory') = 'object'", findings) and not found_tools?)
      )

      prepare(build(select: [:domain], load: [:read_directory_pages]))
    end
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # Findings are public.
    policy action_type(:read) do
      authorize_if(always())
    end
  end

  @doc "The topic a finished check of `domain` is told on."
  @spec topic(String.t()) :: String.t()
  def topic(domain), do: "patchbay:site_check:" <> domain

  @doc "Whether a check is on its way."
  @spec pending?(Ash.Resource.record()) :: boolean()
  def pending?(check),
    do: is_nil(check.checked_at) or DateTime.before?(check.checked_at, check.requested_at)

  @doc """
  The WebMCP tools Patchbay's own check found for a site, the one count every
  page shows: on its front page, then on every page the directory lists for
  it that the check read whole, each name once, with the page it was found on
  and its description. Nil until a check has finished: the site is not
  checked. A check that could not be done keeps the last finished one's tools.
  """
  @spec tools(Ash.Resource.record() | nil) :: [map()] | nil
  def tools(%{findings: %{"webmcp" => front, "directory" => directory}, page_url: page_url}) do
    on_front = Enum.map(front, &Map.put(&1, "address", page_url))

    Enum.uniq_by(
      on_front ++ listed(directory, directory |> Map.keys() |> Enum.sort()),
      & &1["name"]
    )
  end

  def tools(_check), do: nil

  @doc """
  The tools the check found on `pages` alone, some of the pages the directory
  lists, by the rule of `tools/1`: a directory row for another address on the
  site, such as a product's own, counts only its own pages.
  """
  @spec tools(Ash.Resource.record() | nil, [String.t()]) :: [map()] | nil
  def tools(%{findings: %{"webmcp" => _front, "directory" => directory}}, pages),
    do: directory |> listed(pages) |> Enum.uniq_by(& &1["name"])

  def tools(_check, _pages), do: nil

  defp listed(directory, pages),
    do: Enum.flat_map(pages, &(get_in(directory, [&1, "tools"]) || []))
end
