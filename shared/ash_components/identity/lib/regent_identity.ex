defmodule RegentIdentity do
  @moduledoc """
  Canonical Regent profiles in the shared `regent_identity` schema, whose one
  migration ran once, from Regents. Each product supplies its own repository
  connection to the same database and keeps its own sessions, product account IDs
  and authorization.

  A verified Privy sign-in makes and refreshes a profile (`sync/1`, `ensure/1`);
  the profile's owner (`RegentIdentity.Owner`), as the site resolved them, reads
  and edits it (`get_my_profile/1`, `edit_profile/3`).
  """
  use Ash.Domain

  alias RegentIdentity.Owner

  resources do
    resource RegentIdentity.Profile do
      define :get_my_profile, action: :mine, not_found_error?: false
      define :edit_profile, action: :edit
    end
  end

  def repo(_resource, _operation), do: Application.fetch_env!(:regent_identity, :repo)

  @doc "Synchronizes an explicit verified sign-in/link event. Passive page loads only read."
  def sync(%RegentPrivy.Session{issued_at: issued} = actor) when is_integer(issued) do
    if RegentIdentity.VerifiedActor.match?(actor, nil, []) do
      Ash.transact(RegentIdentity.Profile, fn -> sync_locked(actor) end)
    else
      {:error, :unverified_identity}
    end
  end

  def sync(_actor), do: {:error, :missing_issued_at}

  @doc """
  Gives a verified person their profile when they have none, at sign-in. A
  profile they already have is left as it is: refreshing it stays with `sync/1`.
  """
  def ensure(%RegentPrivy.Session{} = actor) do
    case get_my_profile(actor: Owner.of(actor)) do
      {:ok, nil} -> sync(actor)
      found -> found
    end
  end

  @doc """
  The profile ID of the person `privy_user_id` of `app_id`, for a server acting
  for that person without their session, such as a paired agent paying for
  them; nil until they have a profile. Only the ID is read.
  """
  def profile_id(app_id, privy_user_id) do
    RegentIdentity.Profile
    |> Ash.Query.for_read(:person, %{app_id: app_id, privy_user_id: privy_user_id})
    |> Ash.Query.select([:id])
    # The person is not here to prove themselves; the caller already verified
    # who acts for them, and only the ID leaves.
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:ok, nil}
      {:ok, profile} -> {:ok, profile.id}
      {:error, error} -> {:error, error}
    end
  end

  defp sync_locked(actor) do
    # Serialize one person's reconciliation across sites before reading. This
    # never controls wallet operations, payment requests or transaction sends.
    lock(actor)

    with {:ok, profile} <- get_my_profile(actor: Owner.of(actor)),
         {:ok, profile} <- reconcile(profile, actor) do
      profile
    end
  end

  defp reconcile(nil, actor) do
    RegentIdentity.Profile
    |> Ash.Changeset.for_create(:register, %{}, actor: actor)
    |> Ash.create()
  end

  defp reconcile(profile, actor) do
    x = Enum.find(actor.linked_socials, &(&1.provider == :x)) || %{}

    same =
      MapSet.new(profile.wallet_addresses) == MapSet.new(actor.wallet_addresses) and
        {profile.x_subject, profile.x_username, profile.x_display_name} ==
          {x[:subject], x[:username], x[:display_name]}

    cond do
      actor.issued_at < profile.proof_issued_at ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :identity,
           message: "stale identity evidence"
         )}

      actor.issued_at == profile.proof_issued_at and not same ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :identity,
           message: "conflicting identity evidence"
         )}

      same and actor.issued_at == profile.proof_issued_at ->
        {:ok, profile}

      true ->
        profile |> Ash.Changeset.for_update(:refresh, %{}, actor: actor) |> Ash.update()
    end
  end

  @doc false
  def lock(actor) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({actor.app_id, actor.privy_user_id}))
    <<key::signed-64, _::binary>> = digest
    Ecto.Adapters.SQL.query!(repo(nil, :mutate), "SELECT pg_advisory_xact_lock($1)", [key])
  end

  @doc "Owner-only response shared by UI and agent adapters. Never contains provider subjects."
  def present(%RegentIdentity.Profile{} = profile) do
    %{
      profile_id: profile.id,
      verification_basis: "last_synchronized_privy_proof",
      evidence_issued_at: profile.proof_issued_at,
      display_name: profile.display_name,
      linked_wallets: profile.wallet_addresses,
      wallet: %{
        address: profile.wallet_address,
        verified:
          not is_nil(profile.wallet_address) and
            profile.wallet_address in profile.wallet_addresses
      },
      x:
        if(profile.x_subject,
          do: %{
            username: profile.x_username,
            display_name: profile.x_display_name,
            verified: true,
            source: "privy"
          },
          else: nil
        )
    }
  end
end
