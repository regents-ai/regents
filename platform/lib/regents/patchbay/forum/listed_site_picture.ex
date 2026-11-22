defmodule Regents.Patchbay.Forum.ListedSitePicture do
  @moduledoc """
  The picture Patchbay took of a listed site's home page, for its row on
  /sites while the site has no board of its own: one per listed domain, taken
  once. A site with a board shows the board's picture instead
  (`Regents.Patchbay.Forum.SiteScreenshot`).

  A domain whose page gave no picture keeps a row without one, so it is not
  asked for again.

  The table and its rows as patchbay.help keeps them. A picture is read to
  be served (`/patchbay/listed-site-pictures/:domain`) and for its row on the
  directory; nothing here takes one: that comes with Patchbay's background
  work.
  """

  alias Regents.Patchbay.Forum.Origin

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_listed_site_pictures")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    attribute :domain, :string do
      primary_key?(true)
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: Origin.max_host_length())
    end

    # Nil when no picture came back.
    attribute(:image, :binary, allow_nil?: true, public?: true)
    attribute(:taken_at, :utc_datetime_usec, allow_nil?: false, public?: true)
  end

  actions do
    read :pictured do
      description("The listed sites' pictures that came back.")
      filter(expr(not is_nil(image)))
    end

    read :shown do
      description(
        "When the pictures of the home pages of `domains` were taken, without the images."
      )

      argument(:domains, {:array, :string}, allow_nil?: false)
      filter(expr(domain in ^arg(:domains) and not is_nil(image)))
      prepare(build(select: [:domain, :taken_at]))
    end
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # The picture is shown on the public list.
    policy action_type(:read) do
      authorize_if(always())
    end
  end

  @doc """
  Where the site's row loads the picture from, as patchbay.help names it;
  `at` changes with each picture. A page draws it through
  `RegentsWeb.Patchbay.Forum.BoardHTML.picture_url/1`.
  """
  @spec path(Ash.Resource.record()) :: String.t()
  def path(picture),
    do: "/listed-site-pictures/#{picture.domain}?at=#{DateTime.to_unix(picture.taken_at)}"
end
