defmodule AshPlatform.RegentsClub.ActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @attempt "c56a4180-65aa-42ec-a945-5fd21dec0538"

  defmodule MediaHttpClient do
    def get(url, options), do: dispatch(:get, url, options)

    defp dispatch(method, url, options) do
      :ash_platform
      |> Application.fetch_env!(:test_regents_club_media_handler)
      |> then(& &1.(method, url, options))
    end
  end

  setup do
    keys = [
      :regents_club_metadata_cutover,
      :regents_club_chain_client,
      :test_regents_club_chain_responses,
      :regents_club_privy_origin_canary,
      :regents_club_media_full_corpus_attestation,
      :regents_club_media_probe_module,
      :regents_club_media_http_client,
      :test_regents_club_media_handler,
      :wallet_action_clock,
      :privy,
      :privy_verifier
    ]

    previous = Map.new(keys, &{&1, Application.get_env(:ash_platform, &1)})

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)

    Application.put_env(
      :ash_platform,
      :regents_club_chain_client,
      AshPlatform.TestRegentsClubChainClient
    )

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")
    Application.put_env(:ash_platform, :privy_verifier, AshPlatform.TestPrivyVerifier)
    Application.put_env(:ash_platform, :regents_club_privy_origin_canary, true)

    Application.put_env(
      :ash_platform,
      :regents_club_media_full_corpus_attestation,
      RegentsClub.media_release_attestation()["release_manifest_sha256"]
    )

    Application.put_env(
      :ash_platform,
      :regents_club_media_probe_module,
      AshPlatform.TestRegentsClubChainClient
    )

    Application.delete_env(:ash_platform, :test_regents_club_chain_responses)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore(key, value) end) end)

    :ok
  end

  test "prepares only the exact reviewed action inside the current owner lease" do
    account = account!("owner", [@owner])

    assert {:ok, envelope} = Actions.prepare(@owner, @attempt, current_lease(account.id))
    assert envelope.arguments.attempt_id == @attempt
    assert is_binary(envelope.confirmation_token)
    assert envelope.action == "set_base_uri"
    assert envelope.chain_id == 8453
    assert envelope.to == RegentsClub.contract_address()
    assert envelope.value == "0"
    assert envelope.data == RegentsClub.calldata()
    assert envelope.expected_signer == RegentsClub.owner()
    assert envelope.metadata.anchor_block_number == 42
    assert envelope.metadata.current_base_uri == RegentsClub.old_base_uri()
    {:ok, prepared_at, _offset} = DateTime.from_iso8601(envelope.prepared_at)
    {:ok, deadline, _offset} = DateTime.from_iso8601(envelope.metadata.observation_deadline)
    assert DateTime.diff(deadline, prepared_at, :second) == 45 * 60
    assert Actions.observation_open?(envelope)
    assert Actions.valid_envelope?(envelope)

    for changed <- [
          put_in(envelope, [:metadata, :gas_estimate], "0"),
          put_in(envelope, [:metadata, :boundary_token_uris, :last], RegentsClub.old_base_uri()),
          put_in(envelope, [:metadata, :owner_simulation], "unknown"),
          put_in(envelope, [:metadata, :observation_deadline], envelope.expires_at),
          put_in(envelope, [:arguments, :attempt_id], "not-an-attempt"),
          Map.put(envelope, :risk_copy, "Different risk")
        ] do
      refute changed |> resign() |> Actions.valid_envelope?()
    end
  end

  test "fails closed for a disabled gate, a different signer, or a signer absent from linked wallets" do
    account = account!("owner", [@owner])
    lease = current_lease(account.id)

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    assert Actions.prepare(@owner, @attempt, lease) == {:error, :not_authorized}

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)
    assert Actions.prepare(@other, @attempt, lease) == {:error, :not_authorized}

    other = account!("other", [@other])
    assert Actions.prepare(@owner, @attempt, current_lease(other.id)) == {:error, :not_authorized}
  end

  test "rejects stale session authority before trusted preflight" do
    account = account!("stale", [@owner])
    lease = current_lease(account.id)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))

    assert Actions.prepare(@owner, @attempt, lease) == {:error, :session_unavailable}
  end

  test "deployment readiness checks public bootstrap, verifier capability, and Base identity" do
    account = account!("readiness", [@owner])
    lease = current_lease(account.id)
    assert Actions.deployment_readiness(lease) == :ok

    Application.put_env(:ash_platform, :privy, app_id: "")
    assert Actions.deployment_readiness(lease) == {:error, :privy_unavailable}

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      readiness: {:error, :wrong_chain}
    })

    assert Actions.deployment_readiness(lease) == {:error, :wrong_chain}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :regents_club_privy_origin_canary, false)

    assert Actions.deployment_readiness(lease) ==
             {:error, :privy_origin_canary_required}
  end

  test "deployment readiness revalidates the owner lease and exact media attestations" do
    owner = account!("readiness-owner", [@owner])
    other = account!("readiness-other", [@other])

    assert Actions.deployment_readiness(current_lease(other.id)) == {:error, :not_authorized}

    lease = current_lease(owner.id)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))
    assert Actions.deployment_readiness(lease) == {:error, :session_unavailable}

    current = current_lease(owner.id)

    Application.put_env(
      :ash_platform,
      :regents_club_media_full_corpus_attestation,
      RegentsClub.media_release_attestation()["artifact_manifest_sha256"]
    )

    assert Actions.deployment_readiness(current) ==
             {:error, :media_full_corpus_attestation_required}

    Application.put_env(
      :ash_platform,
      :regents_club_media_full_corpus_attestation,
      RegentsClub.media_release_attestation()["release_manifest_sha256"]
    )

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      media_readiness: {:error, :media_probe_failed}
    })

    assert Actions.deployment_readiness(current) == {:error, :media_probe_failed}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :privy_verifier, __MODULE__.MissingVerifier)

    assert Actions.deployment_readiness(current) == {:error, :privy_verifier_unavailable}
  end

  test "live media readiness validates the complete 1,998-token release and representative bytes" do
    use_live_media_handler(:ok)
    account = account!("media-complete", [@owner])

    assert Actions.deployment_readiness(current_lease(account.id)) == :ok

    requests = collect_media_requests([])
    metadata_paths = request_paths(requests, ~r/\A\/metadata\/[1-9][0-9]*\z/)
    png_paths = request_paths(requests, ~r/\A\/images\/animata\/cards\/[1-9][0-9]*\.png\z/)
    mp4_paths = request_paths(requests, ~r/\A\/videos\/regents-club\/[1-9][0-9]*-v1\.mp4\z/)

    assert Enum.count(requests, &match?({:get, "/healthz", _options}, &1)) == 1
    assert MapSet.new(metadata_paths) == expected_metadata_paths()
    assert length(metadata_paths) == 1_998
    assert MapSet.size(MapSet.new(png_paths)) == 1_998
    assert length(png_paths) == 2_001
    assert MapSet.size(MapSet.new(mp4_paths)) == 1_998
    assert length(mp4_paths) == 2_001
  end

  test "live media readiness refuses crossed same-token asset URLs" do
    use_live_media_handler(:crossed_urls)
    account = account!("media-crossed", [@owner])

    assert Actions.deployment_readiness(current_lease(account.id)) ==
             {:error, :media_probe_failed}
  end

  test "live media readiness refuses bad representative MIME and undecodable bodies" do
    account = account!("media-bad-bytes", [@owner])
    lease = current_lease(account.id)

    for mode <- [:bad_mime, :bad_body] do
      use_live_media_handler(mode)
      assert Actions.deployment_readiness(lease) == {:error, :media_probe_failed}
    end
  end

  test "live media readiness refuses a broken middle token and a partial release" do
    use_live_media_handler(:broken_middle)
    account = account!("media-partial", [@owner])

    assert Actions.deployment_readiness(current_lease(account.id)) ==
             {:error, :media_probe_failed}
  end

  test "a signed envelope is not prepared when any authoritative preflight invariant drifts" do
    account = account!("preflight-drift", [@owner])

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      prepare: fn ->
        {:ok,
         %{
           anchor: %{number: 42, hash: "0x" <> String.duplicate("42", 32)},
           owner: RegentsClub.owner(),
           base_uri: RegentsClub.old_base_uri(),
           token_uris: %{
             first: RegentsClub.old_base_uri() <> "1",
             last: RegentsClub.old_base_uri() <> "1998"
           },
           total_supply: 1_997,
           erc4906_supported: true,
           owner_simulation: "success",
           non_owner_simulation: "revert",
           runtime_keccak256: RegentsClub.runtime_keccak256(),
           gas_estimate: 81_189
         }}
      end
    })

    assert Actions.prepare(@owner, @attempt, current_lease(account.id)) ==
             {:error, :not_authorized}
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp use_live_media_handler(mode) do
    recipient = self()
    Application.delete_env(:ash_platform, :regents_club_media_probe_module)
    Application.put_env(:ash_platform, :regents_club_media_http_client, MediaHttpClient)

    Application.put_env(
      :ash_platform,
      :test_regents_club_media_handler,
      fn method, url, options ->
        path = URI.parse(url).path
        send(recipient, {:media_request, method, path, options})
        media_response(method, path, options, mode)
      end
    )
  end

  defp collect_media_requests(requests) do
    receive do
      {:media_request, method, path, options} ->
        collect_media_requests([{method, path, options} | requests])
    after
      0 -> Enum.reverse(requests)
    end
  end

  defp request_paths(requests, pattern) do
    for {:get, path, _options} <- requests, Regex.match?(pattern, path), do: path
  end

  defp expected_metadata_paths do
    1..1998
    |> Enum.map(&"/metadata/#{&1}")
    |> MapSet.new()
  end

  defp media_response(:get, "/healthz", _options, _mode),
    do: {:ok, %{status: 200, headers: [], body: "ok"}}

  defp media_response(:get, "/metadata/" <> encoded, _options, mode) do
    with {token_id, ""} <- Integer.parse(encoded),
         true <- token_id in 1..1998,
         false <- mode == :broken_middle and token_id == 1001 do
      image_id = if mode == :crossed_urls and token_id == 1000, do: 999, else: token_id

      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "application/json; charset=utf-8"}],
         body:
           Jason.encode!(%{
             "image" => "https://media.regents.sh/images/animata/cards/#{image_id}.png",
             "animation_url" => "https://media.regents.sh/videos/regents-club/#{token_id}-v1.mp4"
           })
       }}
    else
      _ -> {:ok, %{status: 404, headers: [], body: "missing"}}
    end
  end

  defp media_response(:get, path, options, mode) do
    cond do
      match = Regex.run(~r/\A\/images\/animata\/cards\/([1-9][0-9]*)\.png\z/, path) ->
        [_, encoded] = match
        asset_response(:get, :png, encoded, options, mode)

      match = Regex.run(~r/\A\/videos\/regents-club\/([1-9][0-9]*)-v1\.mp4\z/, path) ->
        [_, encoded] = match
        asset_response(:get, :mp4, encoded, options, mode)

      true ->
        {:ok, %{status: 404, headers: [], body: "missing"}}
    end
  end

  defp asset_response(method, kind, encoded, options, mode) do
    with {token_id, ""} <- Integer.parse(encoded),
         true <- token_id in 1..1998 do
      valid_asset_response(method, kind, token_id, options, mode)
    else
      _ -> {:ok, %{status: 404, headers: [], body: "missing"}}
    end
  end

  defp valid_asset_response(method, kind, token_id, options, mode) do
    body = asset_body(kind, token_id, mode)
    mime = asset_mime(kind, token_id, mode)
    asset_http_response(method, body, mime, options)
  end

  defp asset_body(:png, 1000, :bad_body), do: "not-a-png"
  defp asset_body(:png, _token_id, _mode), do: png()
  defp asset_body(:mp4, _token_id, _mode), do: mp4()

  defp asset_mime(:png, 1000, :bad_mime), do: "text/plain"
  defp asset_mime(:png, _token_id, _mode), do: "image/png"
  defp asset_mime(:mp4, _token_id, _mode), do: "video/mp4"

  defp asset_http_response(:get, body, mime, options) do
    if range_request?(options) do
      {:ok,
       %{
         status: 206,
         headers: [
           {"content-type", mime},
           {"content-range", "bytes 0-0/#{byte_size(body)}"}
         ],
         body: binary_part(body, 0, 1)
       }}
    else
      {:ok, %{status: 200, headers: [{"content-type", mime}], body: body}}
    end
  end

  defp range_request?(options) do
    Enum.any?(Keyword.get(options, :headers, []), fn
      {key, "bytes=0-0"} -> String.downcase(key) == "range"
      _ -> false
    end)
  end

  defp png do
    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      png_chunk("IHDR", <<1::32, 1::32, 8, 2, 0, 0, 0>>) <>
      png_chunk("IDAT", "x") <>
      png_chunk("IEND", "")
  end

  defp png_chunk(type, data),
    do:
      <<byte_size(data)::32, type::binary-size(4), data::binary, :erlang.crc32(type <> data)::32>>

  defp mp4,
    do: mp4_box("ftyp", "isom") <> mp4_box("moov", "x") <> mp4_box("mdat", "x")

  defp mp4_box(type, data),
    do: <<byte_size(data) + 8::32, type::binary-size(4), data::binary>>

  defp resign(envelope) do
    payload =
      envelope
      |> Map.take([
        :action_id,
        :idempotency_key,
        :resource,
        :action,
        :chain_id,
        :to,
        :value,
        :data,
        :expected_signer,
        :prepared_at,
        :preparation_nonce,
        :expires_at,
        :risk_copy,
        :approval,
        :arguments,
        :metadata
      ])
      |> Jason.encode!()
      |> Jason.decode!()

    token = Phoenix.Token.sign(AshPlatformWeb.Endpoint, "wallet-action", payload)
    Map.put(envelope, :confirmation_token, token)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
