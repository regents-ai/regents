defmodule RegentsWeb.Keyfleet.AgentTools.Account.Answer do
  @moduledoc """
  An agent's own profile and its person's account, the same over its signed
  requests and as the Claude connector's tools (`RegentsWeb.Keyfleet.AgentTools.Account`):
  reading, making and setting the status of its profile (`:profile`, `:join`,
  `:edit_profile`), setting and removing its picture (`:avatar_start`,
  `:avatar_upload`, `:avatar_remove`), and its person's Points (`:points`).
  Each answer is `{status, body, retry_after}`, `retry_after` in seconds past a
  limit and otherwise nil; `params` is the signed request's JSON body.

  A picture is set in two steps because it is larger than a signed request
  can carry. `:avatar_start` names it: its SHA-256, its length and its type.
  It answers one upload address, good for ten minutes, carrying a ticket
  signed by this site that binds the agent, its profile and exactly that
  picture. `upload/3` takes the bytes for that ticket; the ticket is its
  permission, so the upload is not signed itself, and `:avatar_upload` sends
  them to the address as base64. `:avatar_remove` takes the picture away.
  Each start and each upload spends the agent's wallet's `:avatar_uploads`
  allowance, since every upload keeps a new picture and has the one it
  replaces deleted.

  A profile is answered with the agent's page in the agent registry, whether
  a World ID-verified person stands behind it and how many agents that person
  stands behind, as its profile saved them.

  `:leave_message` leaves a private message for the site's team, the same over
  `POST /api/v1/messages/{topic}` (`RegentsWeb.Keyfleet.AgentMessageController`). A
  new message answers 201 with its receipt; a retry with the operation_id of a
  message the agent already left answers 200 with that message's receipt and
  leaves nothing (`Regents.Keyfleet.LeftMessages.LeftMessage.AgentLeave`). Its
  `params` hold the topic the address names, and its messages count under the
  key `RegentsWeb.ClientAddress.client_key/1` makes of the `waiter` the caller
  passes: its address's, or a connected app's account's.
  """

  alias RegentAgents.HumanBacking
  alias Regents.Account.Actors.{Agent, Human}
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Agents.Avatar
  alias Regents.Limits
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.Refusal

  @salt "agent avatar upload"
  @ticket_seconds 10 * 60
  @uploads "/api/v1/keyfleet/avatar/upload/"
  # The ticket is signed, not sealed, so it names the agent and nothing the
  # SIWA service said about it.
  @ticket_actor_fields [
    :wallet_address,
    :chain_id,
    :verification_method,
    :audience,
    :credential_ref,
    :pairing_id,
    :privy_user_id,
    :human_account_id
  ]

  @doc """
  Answers `op` for `actor`; nothing here waits, so the waiter only names what
  a message for the team counts against: an address, or a connected app's
  account.
  """
  @spec answer(atom(), map(), Agent.t(), term()) ::
          {pos_integer(), map(), pos_integer() | nil}
  def answer(:join, %{"name" => name, "declared_harness" => harness}, actor, _waiter) do
    case Agents.ensure_profile(%{name: name, declared_harness: harness}, actor: actor) do
      {:ok, profile} -> profile(profile)
      {:error, _error} -> refusal(422, "invalid_profile")
    end
  end

  def answer(:join, _params, _actor, _waiter), do: refusal(422, "invalid_profile")

  def answer(:profile, _params, actor, _waiter) do
    case Agents.get_my_profile(actor: actor) do
      {:ok, nil} -> refusal(404, "profile_not_found")
      {:ok, profile} -> profile(profile)
      {:error, _error} -> refusal(503, "profile_unavailable")
    end
  end

  def answer(:edit_profile, params, actor, _waiter) do
    with {:ok, profile} when not is_nil(profile) <- Agents.get_my_profile(actor: actor),
         {:ok, profile} <- Agents.edit_my_profile(profile, params, actor: actor) do
      profile(profile)
    else
      {:ok, nil} -> refusal(404, "profile_not_found")
      {:error, _error} -> refusal(422, "invalid_profile")
    end
  end

  def answer(:avatar_start, params, actor, _waiter) do
    with :ok <- Limits.admit(:keyfleet_avatar_uploads, actor.wallet_address),
         {:ok, declared} <- Avatar.declare(params),
         {:ok, %{id: profile_id}} <- Agents.get_my_profile(actor: actor) do
      ticket =
        Phoenix.Token.sign(Endpoint, @salt, %{
          profile_id: profile_id,
          declared: declared,
          agent: Map.take(actor, @ticket_actor_fields)
        })

      ok(%{
        upload_url: Endpoint.url() <> @uploads <> ticket,
        method: "PUT",
        content_type: declared.content_type,
        expires_at: DateTime.utc_now() |> DateTime.add(@ticket_seconds) |> DateTime.to_iso8601()
      })
    else
      {:limited, seconds} -> limited(seconds)
      :error -> refusal(422, "invalid_avatar")
      {:ok, nil} -> refusal(404, "profile_not_found")
      {:error, _error} -> refusal(503, "profile_unavailable")
    end
  end

  # The bytes go to the address the start answered, on this site only, as
  # the browser tool sends them.
  def answer(:avatar_upload, %{"upload_url" => url} = params, _actor, _waiter) do
    with {:ok, ticket} <- ticket(url),
         {:ok, upload} <- upload(ticket, params["content_type"]) do
      case Base.decode64(params["bytes_base64"], ignore: :whitespace, padding: false) do
        {:ok, bytes} -> keep(upload, bytes)
        :error -> refusal(422, "invalid_request")
      end
    else
      :not_here -> refusal(401, "avatar_upload_expired")
      refused -> refused
    end
  end

  def answer(:avatar_remove, _params, actor, _waiter) do
    case Agents.get_my_profile(actor: actor) do
      {:ok, nil} ->
        refusal(404, "profile_not_found")

      {:ok, profile} ->
        ok(%{avatar_url: Avatar.url(Agents.remove_avatar!(profile, actor: actor))})

      {:error, _error} ->
        refusal(503, "profile_unavailable")
    end
  end

  @doc """
  The upload the `ticket` was started for, sent as `content_type`, before its
  bytes are read: `{:ok, upload}`, for `keep/2`, or the refusal. The ticket is
  the permission; the agent it names is checked as it stands now, and the
  upload spends its allowance.
  """
  @spec upload(String.t(), term()) ::
          {:ok, map()} | {pos_integer(), map(), pos_integer() | nil}
  def upload(ticket, content_type) do
    with {:ok, %{profile_id: profile_id, declared: declared, agent: agent}} <-
           Phoenix.Token.verify(Endpoint, @salt, ticket, max_age: @ticket_seconds),
         {:paired, {:ok, actor}} <- {:paired, paired_ticket_actor(agent)},
         :ok <- Limits.admit(:keyfleet_avatar_uploads, actor.wallet_address),
         {:type, true} <- {:type, content_type == declared.content_type} do
      {:ok, %{actor: actor, profile_id: profile_id, declared: declared}}
    else
      {:error, _reason} -> refusal(401, "avatar_upload_expired")
      {:paired, :not_paired} -> refusal(403, "agent_not_paired")
      {:limited, seconds} -> limited(seconds)
      {:type, false} -> refusal(422, "avatar_mismatch")
    end
  end

  # Rebuilds the signed ticket's agent and verifies its live pairing episode and
  # owner still match the episode that minted the ticket.
  defp paired_ticket_actor(agent_fields) do
    raw = struct!(Agent, agent_fields)
    id = raw.pairing_id
    owner = raw.privy_user_id

    with true <- is_binary(id) and is_binary(owner) and Agent.authenticated?(raw),
         {:ok, %Agent{pairing: %Human{}, pairing_id: ^id, privy_user_id: ^owner} = actor} <-
           Agent.with_pairing(raw) do
      {:ok, actor}
    else
      _unpaired -> :not_paired
    end
  end

  @doc """
  Keeps `bytes` as the picture of an `upload/2`: its new `avatar_url`, or the
  refusal. `:too_large` is a body longer than a picture may be, refused
  unread, and `:unreadable` one that stopped coming.
  """
  @spec keep(map(), binary() | :too_large | :unreadable) ::
          {pos_integer(), map(), pos_integer() | nil}
  def keep(_upload, :too_large), do: refusal(413, "request_too_large")
  def keep(_upload, :unreadable), do: refusal(503, "avatar_unavailable")

  def keep(upload, bytes) do
    if byte_size(bytes) > Avatar.max_bytes(),
      do: refusal(413, "request_too_large"),
      else: store(upload, bytes)
  end

  defp store(%{actor: actor, profile_id: profile_id, declared: declared}, bytes) do
    case Agents.store_avatar(actor, profile_id, declared, bytes) do
      {:ok, profile} -> ok(%{avatar_url: Avatar.url(profile)})
      {:error, :mismatch} -> refusal(422, "avatar_mismatch")
      {:error, :unreadable} -> refusal(422, "invalid_avatar")
      {:error, :profile_not_found} -> refusal(404, "profile_not_found")
      {:error, _reason} -> refusal(503, "avatar_unavailable")
    end
  end

  # The ticket in an upload address on this site, resolved against the site's
  # own address as a browser resolves it, with nothing asked after it.
  defp ticket(url) when is_binary(url) do
    site = URI.parse(Endpoint.url())
    address = URI.merge(site, url)

    with true <- {address.scheme, address.port} == {site.scheme, site.port},
         true <- String.downcase(address.host || "") == site.host,
         true <- address.query in [nil, ""],
         @uploads <> ticket when ticket != "" <- address.path do
      {:ok, URI.decode(ticket)}
    else
      _elsewhere -> :not_here
    end
  rescue
    # A ticket whose escapes are not ones.
    ArgumentError -> :not_here
  end

  defp ticket(_url), do: :not_here

  defp limited(seconds), do: {429, Refusal.body("avatar_limit_reached"), seconds}

  defp ok(body), do: {200, body, nil}
  defp refusal(status, code), do: {status, Refusal.body(code), nil}

  defp profile(profile) do
    profile
    |> HumanBacking.describe()
    |> Map.merge(%{
      registry_listing: profile.registry_url,
      profile:
        profile
        |> Map.take([
          :id,
          :wallet_address,
          :name,
          :declared_harness,
          :proficiencies,
          :interests,
          :service_ideas,
          :current_status,
          :status_updated_at,
          :last_activity_at
        ])
        |> Map.put(:avatar_url, Avatar.url(profile))
    })
    |> ok()
  end
end
