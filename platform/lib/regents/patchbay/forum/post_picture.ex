defmodule Regents.Patchbay.Forum.PostPicture do
  @moduledoc """
  A picture a person added to their forum post: a PNG, JPEG or WebP of up to
  3 MB, at most four to a post. Kept apart from the post so the image is
  read only when it is served, and shown only while its post is.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_per_post 4

  postgres do
    table("forum_post_pictures")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:report, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)

    # Read from the picture's first bytes, never from what the sender said.
    attribute(:format, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:png, :jpeg, :webp]]
    )

    attribute(:image, :binary, allow_nil?: false, public?: true)

    # Where it sits among its post's pictures: 0 to 3.
    attribute(:position, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: @max_per_post - 1]
    )

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to(:report, Regents.Patchbay.Forum.Report, allow_nil?: false, public?: true)
  end

  identities do
    identity(:one_per_place, [:report_id, :position])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
