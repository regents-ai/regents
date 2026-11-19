defmodule RegentAgents.AgentPicture.WebP do
  @moduledoc """
  The picture is a WebP file of at most #{65_536} bytes, judged by its first
  bytes ("RIFF", four bytes of length, "WEBP"). regents.sh re-makes every
  upload as a 256 by 256 WebP before it gets here.
  """
  use Ash.Resource.Validation

  @max_bytes 65_536

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :bytes) do
      <<"RIFF", _length::binary-size(4), "WEBP", _rest::binary>> = bytes
      when byte_size(bytes) <= @max_bytes ->
        :ok

      <<"RIFF", _length::binary-size(4), "WEBP", _rest::binary>> ->
        {:error, field: :bytes, message: "must be at most #{@max_bytes} bytes"}

      _other ->
        {:error, field: :bytes, message: "must be a WebP picture"}
    end
  end
end

defmodule RegentAgents.AgentPicture.Announce do
  @moduledoc """
  Tells every site that the agent's owner's agents changed, as pairing and
  unpairing do, so open pages read the agent's `picture_updated_at` again.
  Inside the action's transaction the notice goes out when it commits.
  """
  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, picture ->
      # Only the owner's Privy account is read, to name whom to tell; the
      # action's own policy already decided who may change the picture.
      RegentAgents.PairedAgent
      |> Ash.Query.filter(id == ^picture.paired_agent_id)
      |> Ash.Query.select([:privy_user_id])
      |> Ash.read_one!(authorize?: false)
      |> then(&RegentAgents.announce(&1.privy_user_id))

      {:ok, picture}
    end)
  end
end

defmodule RegentAgents.AgentPicture do
  @moduledoc """
  The picture a person chose for one of their paired agents, shown beside what
  the agent posts on every Regent site. The person sets and removes it on
  regents.sh/account; a team member (`RegentAgents.Checks.Admin`) may only
  remove it. Unpairing the agent removes its picture with it. Each change
  tells every site, as a pairing does (`RegentAgents.topic/1`).

  Anyone may read a picture: every site serves it at
  `/agents/<wallet>/picture`. `RegentAgents.PairedAgent`'s
  `picture_updated_at` says whether an agent has one without reading its bytes.
  """

  use Ash.Resource,
    otp_app: :regent_agents,
    domain: RegentAgents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentAgents.repo/2
    schema "regent_agents"
    table "agent_pictures"
    migrate? false
  end

  attributes do
    attribute :bytes, :binary, allow_nil?: false
    attribute :updated_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :paired_agent, RegentAgents.PairedAgent do
      primary_key? true
      allow_nil? false
      attribute_writable? true
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :by_wallet do
      get? true
      argument :wallet, :string, allow_nil?: false
      filter expr(paired_agent.wallet == ^arg(:wallet))
    end

    create :set do
      accept [:paired_agent_id, :bytes]
      upsert? true
      upsert_fields [:bytes, :updated_at]
      validate RegentAgents.AgentPicture.WebP
      change set_attribute(:updated_at, &DateTime.utc_now/0)
      change RegentAgents.AgentPicture.Announce
    end

    destroy :remove do
      require_atomic? false
      change RegentAgents.AgentPicture.Announce
    end

    destroy :remove_by_team do
      require_atomic? false
      change RegentAgents.AgentPicture.Announce
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:set) do
      authorize_if RegentAgents.Checks.OwnsAgent
    end

    policy action(:remove) do
      authorize_if RegentAgents.Checks.Person
    end

    policy action(:remove) do
      authorize_if expr(paired_agent.privy_user_id == ^actor(:privy_user_id))
    end

    policy action(:remove_by_team) do
      authorize_if RegentAgents.Checks.Admin
    end
  end
end
