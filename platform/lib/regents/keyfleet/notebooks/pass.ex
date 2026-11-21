defmodule Regents.Keyfleet.Notebooks.Pass do
  @moduledoc """
  The pass every request to a fleet's hub carries: an ES256 JWT this site
  signs, naming who the request is for (`sub`, `email`) and which fleet's hub
  may accept it (`aud` is `keyfleet-hub:<fleet id>`). It lasts
  `pass_ttl_seconds`.

  The keys are the JWK Set in `config :regents, :keyfleet_notebooks, signing_keys`
  (`KEYFLEET_HUB_SIGNING_KEY`). The first signs; every one is published at
  `/.well-known/hub-jwks.json`, so a new key can be published before it signs
  and an old one kept until the passes it signed have run out. Each key is
  named by its RFC 7638 thumbprint.
  """

  alias Regents.Keyfleet.Notebooks

  @doc "A pass for `subject` to the fleet's hub."
  def mint(fleet_id, subject) do
    sign(
      %{"aud" => audience(fleet_id), "sub" => subject, "email" => Notebooks.email(subject)},
      Notebooks.config()[:pass_ttl_seconds]
    )
  end

  @doc """
  `claims` signed by this site's first key, with its issuer and a life of
  `ttl_seconds` from now. The fleets' code store and the graph machine take
  passes signed the same way (`Regents.Keyfleet.Code.Pass`, `Regents.Keyfleet.Graph.Pass`).
  """
  def sign(claims, ttl_seconds) do
    [signer | _published] = keys()
    now = System.system_time(:second)

    claims =
      Map.merge(claims, %{
        "iss" => Notebooks.config()[:issuer],
        "iat" => now,
        "exp" => now + ttl_seconds
      })

    {_fields, token} =
      signer
      |> JOSE.JWT.sign(%{"alg" => "ES256", "kid" => kid(signer), "typ" => "JWT"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  @doc """
  The claims of `token` when one of this site's keys signed it with ES256, for
  `audience`, by this site's issuer, and it has not run out; `:error` for
  anything else.
  """
  @spec verify(String.t(), String.t()) :: {:ok, map()} | :error
  def verify(token, audience) do
    issuer = Notebooks.config()[:issuer]
    now = System.system_time(:second)

    case Enum.find_value(keys(), &signed_claims(&1, token)) do
      %{"aud" => ^audience, "iss" => ^issuer, "exp" => exp} = claims
      when is_integer(exp) and exp > now ->
        {:ok, claims}

      _unsigned_or_not_for_audience ->
        :error
    end
  end

  # JOSE raises on a token that is not a compact JWS at all.
  defp signed_claims(key, token) do
    case JOSE.JWT.verify_strict(JOSE.JWK.to_public(key), ["ES256"], token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> claims
      _unsigned -> nil
    end
  rescue
    _not_a_token -> nil
  end

  @doc "Who a pass for the fleet's hub is for."
  def audience(fleet_id), do: "keyfleet-hub:#{fleet_id}"

  @doc "The public half of every key, as the JWK Set the hubs read."
  def jwks do
    %{
      "keys" =>
        Enum.map(keys(), fn key ->
          {_fields, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
          Map.merge(public, %{"kid" => kid(key), "alg" => "ES256", "use" => "sig"})
        end)
    }
  end

  # The set is private, so a value that isn't one is named, never quoted.
  defp keys do
    case Notebooks.config()[:signing_keys] do
      nil -> []
      set -> set |> jwk_set() |> Enum.map(&JOSE.JWK.from_map/1)
    end
  end

  defp jwk_set(set) do
    case Jason.decode(set) do
      {:ok, %{"keys" => keys}} when is_list(keys) -> keys
      _not_a_set -> raise "KEYFLEET_HUB_SIGNING_KEY is not a JWK Set"
    end
  end

  defp kid(key), do: JOSE.JWK.thumbprint(key)
end
