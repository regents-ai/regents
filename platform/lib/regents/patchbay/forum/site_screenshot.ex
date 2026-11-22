defmodule Regents.Patchbay.Forum.SiteScreenshot do
  @moduledoc """
  The picture Patchbay took of a site's page for its card, kept apart from
  the site so the image is read only when it is served. One per site.

  The table and its rows as patchbay.help keeps them. A picture is read to
  be served (`/patchbay/site-screenshots/:site_id`); nothing here writes or
  forgets one: taking a picture comes with Patchbay's background work.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_site_screenshots")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:image, :binary, allow_nil?: false, public?: true)
    attribute(:captured_at, :utc_datetime_usec, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:site, Regents.Patchbay.Forum.Site, allow_nil?: false, public?: true)
  end

  identities do
    identity(:one_per_site, [:site_id])
  end

  actions do
    defaults([:read])
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # The picture is shown on a public card.
    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
