defmodule Regents.Patchbay.Forum.SiteCheck do
  @moduledoc """
  What a site offers agents, as Patchbay last found it: one row per
  registrable domain, whether or not the site has a board.

  `requested_at` is when a check was last asked for and `checked_at` when the
  last one finished. What it found is the one source of a site's tool count:
  the directory, the board and the JSON at `/sites` all read it.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

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
      constraints(min_length: 1, max_length: 253)
    end

    # The last findings; nil before the first check. Failures keep previous findings.
    attribute(:findings, :map, allow_nil?: true, public?: true)

    attribute(:requested_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:checked_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    # The front page the last finished check read; empty when it read none.
    attribute :page_url, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 2048)
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

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
