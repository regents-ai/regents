defmodule Regents.Keyfleet.Early.Signup do
  @moduledoc """
  One address on the early-access list.

  An address is stored trimmed and lowercased, with its host in ASCII form
  (`Regents.Keyfleet.Early.Signup.StoredEmail`), so each one is on the list once
  whatever its case or the spelling of its host. An address holds only
  letters, marks and digits in any script and the punctuation an address
  takes; anything else, a character drawn as nothing or a space among them,
  is refused. Leaving an address that is already there changes nothing.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Early,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "early_signups"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    defaults [:read]

    create :sign_up do
      accept [:email]

      # Only what an address may hold, once trimmed: letters, combining marks
      # and decimal digits in any script; the punctuation the mail standard
      # takes unquoted before the @ (RFC 5322's atext), the dot and the @; the
      # three other dots a host may be typed with (`StoredEmail`), after the
      # last @ only, as the lookahead says: none of them with an @ after it;
      # and the nine characters the host standard takes beyond letters, marks
      # and digits (RFC 5892's exceptions and contextual rules: the middle dot
      # of Catalan's l·l, the Greek lower numeral sign, the Hebrew geresh and
      # gershayim, the katakana middle dot, the Tibetan tsheg, two Arabic
      # signs and the ideographic zero). Nothing default-ignorable, which
      # takes out the Hangul fillers and the variation selectors, letters and
      # marks though they are.
      validate match(
                 :email,
                 ~r/\A(?!.*[\x{3002}\x{FF0E}\x{FF61}].*@)(?:(?!\p{DI})[\p{L}\p{M}\p{Nd}!#$%&'*+\-\/=?^_`{|}~.@\x{3002}\x{FF0E}\x{FF61}\x{B7}\x{375}\x{5F3}\x{5F4}\x{30FB}\x{F0B}\x{6FD}\x{6FE}\x{3007}])+\z/u
               )

      change Regents.Keyfleet.Early.Signup.StoredEmail

      upsert? true
      upsert_identity :unique_email
      upsert_fields []
    end
  end

  policies do
    # Anyone may leave an address; the page limits how often one client can.
    policy action(:sign_up) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  attributes do
    uuid_primary_key :id

    # One @ with something on both sides, a dot in the domain and no spaces. The
    # pattern reads bytes (it has no `u` flag), so its lookahead holds an
    # address to 254 bytes: once trimmed as typed, and again as stored.
    attribute :email, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A(?=.{1,254}\z)[^@\s]+@[^@\s]+\.[^@\s]+\z/s]

    create_timestamp :inserted_at
  end
end
