defmodule Regents.Patchbay.Forum.ListedSitePicture do
  @moduledoc """
  The picture Patchbay took of a listed site's home page, for its row on
  /sites while the site has no board of its own: one per listed domain, taken
  once. A site with a board shows the board's picture instead
  (`Regents.Patchbay.Forum.SiteScreenshot`).

  A domain whose page gave no picture keeps a row without one, so it is not
  asked for again.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

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
      constraints(min_length: 1, max_length: 253)
    end

    # Nil when no picture came back.
    attribute(:image, :binary, allow_nil?: true, public?: true)
    attribute(:taken_at, :utc_datetime_usec, allow_nil?: false, public?: true)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
