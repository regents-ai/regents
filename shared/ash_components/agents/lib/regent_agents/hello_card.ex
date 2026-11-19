defmodule RegentAgents.HelloCard do
  @moduledoc """
  Hello cards: the SIWA service's signed note that a Regent site said an agent
  is paired with a person there, good for a day. An agent shows its card to any
  site in the `x-siwa-hello-card` header beside a signed request, and the site
  checks it against the keys the SIWA service publishes at
  `<siwa url>/.well-known/jwks.json`, without asking anyone.

  A card is a compact JWS signed with EdDSA, typed `siwa-hello-card+jws`, whose
  payload is exactly `cardId`, `subject`, `name`, `person`, `pairedAt`,
  `pairedOn`, `issuedAt` and `expiresAt`, every time in ISO 8601 UTC whole
  seconds. `verify/3` holds a card to all of that, to the published key its
  `kid` names, to `expiresAt` still ahead, and to `subject` being the agent that
  signed the request beside it. The header is not part of what the agent signs,
  so a card is read only after the request's own signature has been verified:
  `put_card/2` then assigns it as `conn.assigns.hello_card`, or nil when there
  is none or it does not pass. A card that does not pass is ignored; the request
  goes on as if none was sent.

  To give an agent a card, the SIWA service asks the site the agent is paired on
  (`POST /api/agents/v1/pairing`, in `RegentAgents.HTTP`) with a service token:
  a compact JWS signed with the same keys, typed `siwa-service+jwt`, issued by
  the SIWA service for this site's origin and the agent's subject, good for 60
  seconds (`verify_service_token/2`). The two types differ on purpose: a card
  is never accepted as a token, nor a token as a card.

  ## What a card says

  A card that passes says only that, until it expires, the site `pairedOn` had
  this agent, which it calls `name`, paired with a person whose profile code is
  `person`: the id of their shared Regent profile, never the Privy user ID, an
  email, a wallet or a name. A site must not conclude from it:

    * that the agent is paired on this site;
    * that the person approved this request, or anything the agent does here;
    * that `name` is unique or verified: it is what the agent is called on that
      site;
    * that `person` is signed in here, or is anyone in particular here;
    * that the agent or its person can pay;
    * that the agent is honest or capable;
    * anything at all once the card has expired, or when the request beside it
      is not signed by the card's `subject`.

  Pages say "paired with a person on <site>", never "trusted" or "verified", and
  never show or greet anyone with the `person` code.

  ## Keys

  The published keys are read through `RegentAgents.Broker`, at the SIWA
  address in `config :regent_agents, siwa: [url: ...]`, and kept for an hour in
  `:persistent_term`. The SIWA service publishes a new key an hour before it
  signs with it; a token or card naming a key not among those kept reads them
  again, once in that call and at most once a minute. A read that fails keeps
  no keys and is not tried again for a minute. A site with no
  `siwa: [origin: ...]` accepts no service token.
  """

  import Plug.Conn, only: [assign: 3, get_req_header: 2]

  alias RegentAgents.Broker

  @card_typ "siwa-hello-card+jws"
  @service_typ "siwa-service+jwt"
  @card_fields Enum.sort(~w(cardId subject name person pairedAt pairedOn issuedAt expiresAt))
  @held {__MODULE__, :keys}
  @failed_at {__MODULE__, :keys_read_failed_at}
  @keep_seconds 3_600
  @read_again_after_seconds 60
  # Regent sites sign agents in on Base (`RegentAgents.HTTP`).
  @base_subject "eip155:8453:"

  @type card :: %{String.t() => String.t()}

  @doc """
  Checks `card`, a compact JWS, against the published keys at `now`, for the
  agent `signer_subject` (`"eip155:<chain id>:<address>"`) whose signed request
  it came with. The answer is the card's eight fields.
  """
  @spec verify(String.t(), String.t(), DateTime.t()) :: {:ok, card()} | :error
  def verify(card, signer_subject, %DateTime{} = now)
      when is_binary(card) and is_binary(signer_subject) do
    with {:ok, fields} <- signed_payload(card, @card_typ, now),
         {:ok, expires_at} <- card_fields(fields),
         ^signer_subject <- fields["subject"],
         true <- DateTime.before?(now, expires_at) do
      {:ok, fields}
    else
      _not_this_agents_card -> :error
    end
  end

  @doc """
  Assigns `:hello_card` on a request whose signature was just verified for
  `wallet`, the lowercase address of the key that signed it on Base, as
  `RegentAgents.Agent` names it: the card in its `x-siwa-hello-card` header when
  `verify/3` passes it, otherwise nil. A site's own `Siwa.AgentAuthPlug` hooks
  call it from `accept/3`.
  """
  @spec put_card(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_card(conn, wallet) when is_binary(wallet) do
    card =
      with [card] <- get_req_header(conn, "x-siwa-hello-card"),
           {:ok, card} <- verify(card, @base_subject <> wallet, DateTime.utc_now()) do
        card
      else
        _no_card -> nil
      end

    assign(conn, :hello_card, card)
  end

  @doc """
  Checks the SIWA service's `token` at `now`: typed `siwa-service+jwt`, signed
  by a published key, issued by the SIWA address in
  `config :regent_agents, siwa: [url: ...]` for this site's
  `siwa: [origin: ...]`, and not expired. The answer is its `sub`, the agent's
  subject.
  """
  @spec verify_service_token(String.t(), DateTime.t()) :: {:ok, String.t()} | :error
  def verify_service_token(token, %DateTime{} = now) when is_binary(token) do
    issuer = siwa_url()
    origin = Keyword.fetch!(config(), :origin)
    now_unix = DateTime.to_unix(now)

    case signed_payload(token, @service_typ, now) do
      {:ok, %{"iss" => ^issuer, "aud" => ^origin, "sub" => subject, "exp" => expires}}
      when is_binary(origin) and is_binary(subject) and is_integer(expires) and
             now_unix < expires ->
        {:ok, subject}

      _refused ->
        :error
    end
  end

  # A compact JWS of type `typ`, signed with EdDSA by the published key its
  # header names; the answer is its payload. The type is checked before any key
  # is looked up.
  defp signed_payload(compact, typ, now) do
    with [header, payload, signature] <- String.split(compact, "."),
         {:ok, %{"alg" => "EdDSA", "typ" => ^typ, "kid" => kid} = named}
         when map_size(named) == 3 and is_binary(kid) <- decode_json(header),
         {:ok, public_key} <- published_key(kid, DateTime.to_unix(now)),
         {:ok, <<_::binary-size(64)>> = signature} <- decode(signature),
         true <-
           :crypto.verify(:eddsa, :none, header <> "." <> payload, signature, [
             public_key,
             :ed25519
           ]),
         {:ok, %{} = fields} <- decode_json(payload) do
      {:ok, fields}
    else
      _unsigned -> :error
    end
  end

  # Exactly the eight fields, each in its shape; the answer is the expiry.
  defp card_fields(fields) do
    with true <- Enum.sort(Map.keys(fields)) == @card_fields,
         {:ok, <<_::binary-size(16)>>} <- decode(fields["cardId"]),
         true <- is_binary(fields["subject"]),
         true <- text?(fields["name"]) and text?(fields["person"]) and text?(fields["pairedOn"]),
         {:ok, _paired_at} <- time(fields["pairedAt"]),
         {:ok, _issued_at} <- time(fields["issuedAt"]) do
      time(fields["expiresAt"])
    end
  end

  defp text?(value), do: is_binary(value) and String.length(value) in 1..200

  # A time in its one spelling: ISO 8601 UTC, whole seconds.
  defp time(text) when is_binary(text) do
    with {:ok, time, 0} <- DateTime.from_iso8601(text),
         ^text <- time |> DateTime.truncate(:second) |> DateTime.to_iso8601() do
      {:ok, time}
    end
  end

  defp time(_not_text), do: :error

  defp published_key(kid, now) do
    {read_at, keys} = held_keys(now)

    case keys do
      %{^kid => public_key} ->
        {:ok, public_key}

      _unknown when now - read_at >= @read_again_after_seconds ->
        {_read_at, keys} = read_keys(now)
        Map.fetch(keys, kid)

      _unknown ->
        :error
    end
  end

  defp held_keys(now) do
    case :persistent_term.get(@held, nil) do
      {read_at, keys} when now - read_at < @keep_seconds -> {read_at, keys}
      _none_or_old -> read_keys(now)
    end
  end

  # A read that failed is not tried again for `@read_again_after_seconds`.
  defp read_keys(now) do
    if now - :persistent_term.get(@failed_at, 0) < @read_again_after_seconds,
      do: {now, %{}},
      else: fetch_keys(now)
  end

  # One read of the published keys, kept only when it succeeds: each Ed25519
  # public key by its `kid`.
  defp fetch_keys(now) do
    case Broker.request(
           method: :get,
           url: siwa_url() <> "/.well-known/jwks.json",
           receive_timeout: 5_000,
           connect_options: [timeout: 2_000]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        held =
          {now,
           Map.new(
             for %{"kty" => "OKP", "crv" => "Ed25519", "kid" => kid, "x" => x} when is_binary(kid) <-
                   keys,
                 {:ok, <<_::binary-size(32)>> = public_key} <- [decode(x)],
                 do: {kid, public_key}
           )}

        :persistent_term.put(@held, held)
        held

      _failed ->
        :persistent_term.put(@failed_at, now)
        {now, %{}}
    end
  end

  defp siwa_url, do: config() |> Keyword.fetch!(:url) |> String.trim_trailing("/")

  defp config, do: Application.fetch_env!(:regent_agents, :siwa)

  # Unpadded base64url in its one spelling.
  defp decode(text) when is_binary(text) do
    with {:ok, bytes} <- Base.url_decode64(text, padding: false),
         ^text <- Base.url_encode64(bytes, padding: false) do
      {:ok, bytes}
    else
      _other -> :error
    end
  end

  defp decode(_not_text), do: :error

  defp decode_json(part) do
    with {:ok, json} <- decode(part), do: Jason.decode(json)
  end
end
