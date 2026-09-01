defmodule AshPlatform.RegentsClub.ActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions

  @owner "0x45C9a201e2937608905fEF17De9A67f25F9f98E0"
  @other "0x1111111111111111111111111111111111111111"
  @selected "0x2222222222222222222222222222222222222222"
  @attempt "c56a4180-65aa-42ec-a945-5fd21dec0538"

  defmodule MediaHttpClient do
    def get(url, options), do: dispatch(:get, url, options)

    defp dispatch(method, url, options) do
      :ash_platform
      |> Application.fetch_env!(:test_regents_club_media_handler)
      |> then(& &1.(method, url, options))
    end
  end

  defmodule MediaFixtures do
    @png Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAACXBIWXMAAAABAAAAAQBPJcTWAAAAF0lEQVR4nGP8w0AaYCFR/aiGUQ1DSAMAZPEBOnXWok4AAAAASUVORK5CYII="
         )
    @mp4 """
         AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMUbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAA+gAAQAA
         AQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
         AAAAAgAAAj90cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAA+gAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA
         AAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAPoAAAAAAABAAAAAAG3
         bWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAQABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRl
         b0hhbmRsZXIAAAABYm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAA
         AQAAASJzdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAA
         AAABFUxhdmM2Mi4xMS4xMDAgbGlieDI2NAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAAD
         AAg8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAABZYAAAAAAAAABhzdHRzAAAAAAAAAAEA
         AAABAABAAAAAABxzdHNjAAAAAAAAAAEAAAABAAAAAQAAAAEAAAAUc3RzegAAAAAAAALLAAAAAQAAABRzdGNvAAAAAAAAAAEA
         AANEAAAAYXVkdGEAAABZbWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAsaWxzdAAAACSpdG9v
         AAAAHGRhdGEAAAABAAAAAExhdmY2Mi4zLjEwMAAAAAhmcmVlAAAC021kYXQAAAKtBgX//6ncRem95tlIt5Ys2CDZI+7veDI2
         NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1
         IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MSByZWY9MyBkZWJsb2NrPTE6
         MDowIGFuYWx5c2U9MHgzOjB4MTEzIG1lPWhleCBzdWJtZT03IHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTEg
         bWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0xIDh4OGRjdD0xIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNr
         aXA9MSBjaHJvbWFfcXBfb2Zmc2V0PS0yIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAg
         bnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVz
         PTMgYl9weXJhbWlkPTIgYl9hZGFwdD0xIGJfYmlhcz0wIGRpcmVjdD0xIHdlaWdodGI9MSBvcGVuX2dvcD0wIHdlaWdodHA9
         MiBrZXlpbnQ9MjUwIGtleWludF9taW49MSBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFkPTQwIHJj
         PWNyZiBtYnRyZWU9MSBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40
         MCBhcT0xOjEuMDAAgAAAABZliIQAFf/+7M9+BTZo5i/D8UVzjn2B
         """
         |> String.replace(~r/\s+/, "")
         |> Base.decode64!()

    def png, do: @png
    def mp4, do: @mp4

    def metadata(token_id) do
      Jason.encode!(%{
        "image" => "https://media.regents.sh/images/animata/cards/#{token_id}.png",
        "animation_url" => "https://media.regents.sh/videos/regents-club/#{token_id}-v2.mp4"
      })
    end

    def release_manifest do
      png_sha256 = sha256(@png)
      mp4_sha256 = sha256(@mp4)

      rows =
        Map.new(1..1998, fn token_id ->
          metadata = metadata(token_id)

          {token_id,
           %{
             token_id: token_id,
             image: %{
               path: "images/animata/cards/#{token_id}.png",
               sha256: png_sha256,
               bytes: byte_size(@png)
             },
             video: %{
               path: "videos/regents-club/#{token_id}-v2.mp4",
               sha256: mp4_sha256,
               bytes: byte_size(@mp4)
             },
             metadata: %{
               path: "metadata/regents-club/#{token_id}.json",
               sha256: sha256(metadata),
               bytes: byte_size(metadata)
             }
           }}
        end)

      {:ok, rows}
    end

    defp sha256(contents),
      do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)
  end

  defmodule PartialMediaFixtures do
    def release_manifest do
      {:ok, rows} = MediaFixtures.release_manifest()
      {:ok, Map.delete(rows, 1998)}
    end
  end

  setup do
    keys = [
      :regents_club_metadata_cutover,
      :regents_club_chain_client,
      :test_regents_club_chain_responses,
      :regents_club_privy_origin_canary,
      :regents_club_media_probe_module,
      :regents_club_media_http_client,
      :regents_club_media_manifest_module,
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
      :regents_club_media_probe_module,
      AshPlatform.TestRegentsClubChainClient
    )

    Application.put_env(:ash_platform, :regents_club_media_manifest_module, MediaFixtures)

    Application.delete_env(:ash_platform, :test_regents_club_chain_responses)

    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore(key, value) end) end)

    :ok
  end

  test "binds the exact reviewed action to any normalized selected wallet inside the current lease" do
    account = account!("selected-wallet", [@other])

    assert {:ok, envelope} = Actions.prepare(@selected, @attempt, current_lease(account.id))
    assert envelope.arguments.attempt_id == @attempt
    assert is_binary(envelope.confirmation_token)
    assert envelope.action == "set_base_uri"
    assert envelope.chain_id == 8453
    assert envelope.to == RegentsClub.contract_address()
    assert envelope.value == "0"
    assert envelope.data == RegentsClub.calldata()
    assert envelope.expected_signer == String.downcase(@selected)
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

  test "fails closed for a disabled gate or invalid wallet but does not require a linked owner" do
    account = account!("authenticated", [@other])
    lease = current_lease(account.id)

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, false)
    assert Actions.prepare(@selected, @attempt, lease) == {:error, :not_authorized}

    Application.put_env(:ash_platform, :regents_club_metadata_cutover, true)
    assert {:ok, envelope} = Actions.prepare(@selected, @attempt, lease)
    assert envelope.expected_signer == String.downcase(@selected)
    assert Actions.prepare("not-an-address", @attempt, lease) == {:error, :not_authorized}
  end

  test "rejects stale session authority before trusted preflight" do
    account = account!("stale", [@owner])
    lease = current_lease(account.id)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))

    assert Actions.prepare(@owner, @attempt, lease) == {:error, :session_unavailable}
  end

  test "network and media checks complete before the final session transaction" do
    account = account!("transaction-boundary", [@other])
    test_pid = self()

    record = fn check ->
      send(test_pid, {:external_check, check, AshPlatform.Repo.in_transaction?()})
    end

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      media_readiness: fn ->
        record.(:media)
        :ok
      end,
      status: fn ->
        record.(:status)
        {:ok, %{state: :ready, base_uri: RegentsClub.old_base_uri()}}
      end,
      prepare: fn ->
        record.(:prepare)
        {:ok, preflight()}
      end
    })

    assert {:ok, _envelope} = Actions.prepare(@selected, @attempt, current_lease(account.id))

    for check <- [:media, :status, :prepare] do
      assert_receive {:external_check, ^check, false}
    end
  end

  test "deployment readiness checks public bootstrap, verifier capability, and Base identity" do
    account = account!("readiness", [@owner])
    lease = current_lease(account.id)
    assert {:ok, %{state: :ready}} = Actions.deployment_readiness(lease)

    Application.put_env(:ash_platform, :privy, app_id: "")
    assert Actions.deployment_readiness(lease) == {:error, :privy_unavailable}

    Application.put_env(:ash_platform, :privy, app_id: "public-test-id")

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      status: {:error, :wrong_chain}
    })

    assert Actions.deployment_readiness(lease) == {:error, :wrong_chain}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :regents_club_privy_origin_canary, false)

    assert Actions.deployment_readiness(lease) ==
             {:error, :privy_origin_canary_required}
  end

  test "deployment readiness accepts any current human lease and revalidates runtime probes" do
    account = account!("readiness-human", [@other])
    lease = current_lease(account.id)
    assert {:ok, %{state: :ready}} = Actions.deployment_readiness(lease)
    assert is_binary(SessionAuthority.revoke(%{lineage: lease.lineage, generation: 1}))
    assert Actions.deployment_readiness(lease) == {:error, :session_unavailable}

    current = current_lease(account.id)

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{
      media_readiness: {:error, :media_probe_failed}
    })

    assert Actions.deployment_readiness(current) == {:error, :media_probe_failed}

    Application.put_env(:ash_platform, :test_regents_club_chain_responses, %{})
    Application.put_env(:ash_platform, :privy_verifier, __MODULE__.MissingVerifier)

    assert Actions.deployment_readiness(current) == {:error, :privy_verifier_unavailable}
  end

  test "runtime checks only three representative media rows; release verification checks all rows" do
    use_live_media_handler(:ok)
    account = account!("media-complete", [@owner])

    assert {:ok, %{state: :ready}} = Actions.deployment_readiness(current_lease(account.id))

    requests = collect_media_requests([])

    metadata_paths =
      request_paths(requests, ~r/\A\/metadata\/regents-club\/[1-9][0-9]*\.json\z/)

    png_paths = request_paths(requests, ~r/\A\/images\/animata\/cards\/[1-9][0-9]*\.png\z/)
    mp4_paths = request_paths(requests, ~r/\A\/videos\/regents-club\/[1-9][0-9]*-v2\.mp4\z/)

    assert Enum.count(requests, &match?({:get, "/healthz", _options}, &1)) == 1
    assert MapSet.new(metadata_paths) == representative_metadata_paths()
    assert length(metadata_paths) == 3
    assert length(png_paths) == 3
    assert length(mp4_paths) == 3

    assert :ok =
             Mix.Tasks.AshPlatform.VerifyChainManifest.verify_media_release(
               MediaHttpClient,
               elem(MediaFixtures.release_manifest(), 1)
             )

    release_requests = collect_media_requests([])
    assert length(release_requests) == 1 + 1_998 * 3
  end

  test "packaged release manifest has the exact approved bytes and contiguous mappings" do
    path = "contracts/regents-club-release-manifest.tsv"
    contents = File.read!(path)

    assert sha256(contents) ==
             "5c8c4a7bcce2dc38d3f1d3dcdd13aee064ed9c03799056c37f273a08a453e402"

    assert {:ok, rows} = RegentsClub.parse_release_manifest(contents)
    assert rows == RegentsClub.release_manifest()
    assert Map.keys(rows) |> Enum.sort() == Enum.to_list(1..1998)

    assert rows[1] == %{
             token_id: 1,
             image: %{
               path: "images/animata/cards/1.png",
               sha256: "039ff95d493dbfe92eefeabb5b263c9eab05644ab34ed59a60a0e199459811d0",
               bytes: 1_508_008
             },
             video: %{
               path: "videos/regents-club/1-v2.mp4",
               sha256: "4c274efb3a133d0e3162fb96ff2bf27c66fa3bfa0e9cd341b2b4b4b24ff4137c",
               bytes: 452_948
             },
             metadata: %{
               path: "metadata/regents-club/1.json",
               sha256: "7a940e11903de7b74225ccbc6e2c9ed495f2a170a12c98f6086f36ef441d0c63",
               bytes: 740
             }
           }

    assert rows[1998].image.path == "images/animata/cards/1998.png"
    assert rows[1998].video.path == "videos/regents-club/1998-v2.mp4"
    assert rows[1998].metadata.path == "metadata/regents-club/1998.json"

    assert :error == RegentsClub.parse_release_manifest("bad header\n" <> contents)

    assert :error ==
             RegentsClub.parse_release_manifest(
               String.replace(contents, "\n2\t", "\n3\t", global: false)
             )

    assert :error == RegentsClub.parse_release_manifest(String.trim_trailing(contents))
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

  test "release verification refuses a broken middle token, wrong asset size, and partial manifest" do
    use_live_media_handler(:broken_middle)
    release_manifest = elem(MediaFixtures.release_manifest(), 1)

    assert {:error, _reason} =
             Mix.Tasks.AshPlatform.VerifyChainManifest.verify_media_release(
               MediaHttpClient,
               release_manifest
             )

    use_live_media_handler(:wrong_asset_size)

    assert {:error, _reason} =
             Mix.Tasks.AshPlatform.VerifyChainManifest.verify_media_release(
               MediaHttpClient,
               release_manifest
             )

    use_live_media_handler(:ok)
    assert {:ok, partial} = PartialMediaFixtures.release_manifest()

    assert {:error, :invalid_media_release} =
             Mix.Tasks.AshPlatform.VerifyChainManifest.verify_media_release(
               MediaHttpClient,
               partial
             )
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

    assert Actions.prepare(@selected, @attempt, current_lease(account.id)) ==
             {:error, :not_authorized}
  end

  defp account!(suffix, wallets) do
    Accounts.register_verified!("did:privy:regents-club-#{suffix}", hd(wallets), wallets,
      actor: %System{}
    )
  end

  defp preflight do
    %{
      anchor: %{number: 42, hash: "0x" <> String.duplicate("42", 32)},
      owner: RegentsClub.owner(),
      base_uri: RegentsClub.old_base_uri(),
      token_uris: %{
        first: RegentsClub.old_base_uri() <> "1",
        last: RegentsClub.old_base_uri() <> "1998"
      },
      total_supply: 1998,
      erc4906_supported: true,
      owner_simulation: "success",
      non_owner_simulation: "revert",
      runtime_keccak256: RegentsClub.runtime_keccak256(),
      gas_estimate: 81_189
    }
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

  defp representative_metadata_paths do
    [1, 1000, 1998]
    |> Enum.map(&"/metadata/regents-club/#{&1}.json")
    |> MapSet.new()
  end

  defp media_response(:get, "/healthz", _options, _mode),
    do: {:ok, %{status: 200, headers: [], body: "ok"}}

  defp media_response(:get, "/metadata/regents-club/" <> encoded, _options, mode) do
    encoded = String.trim_trailing(encoded, ".json")

    with {token_id, ""} <- Integer.parse(encoded),
         true <- token_id in 1..1998,
         false <- mode == :broken_middle and token_id == 1001 do
      body =
        if mode == :crossed_urls and token_id == 1000 do
          Jason.encode!(%{
            "image" => "https://media.regents.sh/images/animata/cards/999.png",
            "animation_url" => "https://media.regents.sh/videos/regents-club/1000-v2.mp4"
          })
        else
          MediaFixtures.metadata(token_id)
        end

      {:ok,
       %{
         status: 200,
         headers: [{"content-type", "application/json; charset=utf-8"}],
         body: body
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

      match = Regex.run(~r/\A\/videos\/regents-club\/([1-9][0-9]*)-v2\.mp4\z/, path) ->
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

    declared_size =
      if mode == :wrong_asset_size and kind == :png and token_id == 1001,
        do: byte_size(body) + 1,
        else: byte_size(body)

    asset_http_response(method, body, mime, options, declared_size)
  end

  defp asset_body(:png, 1000, :bad_body), do: "not-a-png"
  defp asset_body(:png, _token_id, _mode), do: MediaFixtures.png()
  defp asset_body(:mp4, _token_id, _mode), do: MediaFixtures.mp4()

  defp asset_mime(:png, 1000, :bad_mime), do: "text/plain"
  defp asset_mime(:png, _token_id, _mode), do: "image/png"
  defp asset_mime(:mp4, _token_id, _mode), do: "video/mp4"

  defp asset_http_response(:get, body, mime, options, declared_size) do
    if range_request?(options) do
      {:ok,
       %{
         status: 206,
         headers: [
           {"content-type", mime},
           {"content-range", "bytes 0-0/#{declared_size}"}
         ],
         body: binary_part(body, 0, 1)
       }}
    else
      {:ok,
       %{
         status: 200,
         headers: [
           {"content-type", mime},
           {"content-length", Integer.to_string(declared_size)}
         ],
         body: body
       }}
    end
  end

  defp range_request?(options) do
    Enum.any?(Keyword.get(options, :headers, []), fn
      {key, "bytes=0-0"} -> String.downcase(key) == "range"
      _ -> false
    end)
  end

  defp sha256(contents),
    do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)

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
