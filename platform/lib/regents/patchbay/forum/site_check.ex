defmodule Regents.Patchbay.Forum.SiteCheck do
  @moduledoc """
  What a site offers agents, as Patchbay last found it: one row per
  registrable domain, whether or not the site has a board.

  `requested_at` is when a check was last asked for and `checked_at` when the
  last one finished. What it found is the one source of a site's tool count:
  the directory, the board and the JSON at `/sites` all read it.

  The table and its rows as patchbay.help keeps them. Patchbay's pages read
  them; nothing here writes them yet.
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

  identities do
    identity(:unique_domain, [:domain])
  end

  actions do
    defaults([:read])
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # Findings are public.
    policy action_type(:read) do
      authorize_if(always())
    end
  end

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

  defp listed(directory, pages),
    do: Enum.flat_map(pages, &(get_in(directory, [&1, "tools"]) || []))
end
