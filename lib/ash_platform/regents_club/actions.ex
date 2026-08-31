defmodule AshPlatform.RegentsClub.MediaDecoder do
  @moduledoc false

  @command_timeout 30_000
  @command_shutdown_grace 1_000
  @max_diagnostic_bytes 8_192

  def validate(kind, body) when kind in [:png, :mp4] and is_binary(body) do
    case write_temp_file(kind, body) do
      {:ok, directory, path} ->
        result =
          try do
            valid_probe?(kind, path) and valid_decode?(kind, path)
          rescue
            _error -> false
          catch
            _kind, _reason -> false
          end

        cleaned? = remove_temp(directory)
        result and cleaned?

      :error ->
        false
    end
  end

  def validate(_kind, _body), do: false

  defp run_bounded(
         executable,
         arguments,
         timeout \\ @command_timeout,
         max_output \\ @max_diagnostic_bytes
       )

  defp run_bounded(executable, arguments, timeout, max_output)
       when is_binary(executable) and is_list(arguments) and is_integer(timeout) and timeout > 0 and
              is_integer(max_output) and max_output > 0 do
    with {:ok, bounded_executable, bounded_arguments, shutdown, shutdown_grace} <-
           bounded_command(executable, arguments, timeout) do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(bounded_executable)},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            args: Enum.map(bounded_arguments, &String.to_charlist/1)
          ]
        )

      deadline = System.monotonic_time(:millisecond) + timeout + shutdown_grace

      try do
        collect_command(port, deadline, max_output, 0, [])
      after
        stop_port(port, shutdown)
      end
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp run_bounded(_executable, _arguments, _timeout, _max_output), do: :error

  defp bounded_command(executable, arguments, timeout) do
    case System.find_executable("timeout") do
      timeout_executable when is_binary(timeout_executable) ->
        {:ok, timeout_executable,
         ["--signal=KILL", timeout_duration(timeout), executable | arguments], :wrapper,
         @command_shutdown_grace}

      _other ->
        case System.find_executable("kill") do
          kill_executable when is_binary(kill_executable) ->
            {:ok, executable, arguments, {:signal, kill_executable}, 0}

          _other ->
            :error
        end
    end
  end

  defp timeout_duration(milliseconds) do
    seconds = div(milliseconds, 1_000)
    remainder = milliseconds |> rem(1_000) |> Integer.to_string() |> String.pad_leading(3, "0")
    "#{seconds}.#{remainder}s"
  end

  defp valid_probe?(kind, path) do
    with executable when is_binary(executable) <- find_executable("ffprobe"),
         {:ok, output} <-
           run_bounded(executable, [
             "-v",
             "error",
             "-select_streams",
             "v:0",
             "-show_entries",
             "stream=codec_name,codec_type,width,height",
             "-show_entries",
             "format=format_name",
             "-of",
             "json",
             path
           ]),
         {:ok, probe} <- Jason.decode(output) do
      expected_probe?(kind, probe)
    else
      _error -> false
    end
  end

  defp expected_probe?(
         :png,
         %{
           "streams" => [
             %{
               "codec_name" => "png",
               "codec_type" => "video",
               "width" => width,
               "height" => height
             }
           ],
           "format" => %{"format_name" => "png_pipe"}
         }
       ),
       do: positive_dimensions?(width, height)

  defp expected_probe?(
         :mp4,
         %{
           "streams" => [
             %{
               "codec_name" => "h264",
               "codec_type" => "video",
               "width" => width,
               "height" => height
             }
           ],
           "format" => %{"format_name" => format_name}
         }
       )
       when is_binary(format_name) do
    positive_dimensions?(width, height) and "mp4" in String.split(format_name, ",")
  end

  defp expected_probe?(_kind, _probe), do: false

  defp valid_decode?(kind, path) do
    with executable when is_binary(executable) <- find_executable("ffmpeg"),
         {:ok, output} <- run_bounded(executable, decode_arguments(kind, path)) do
      String.trim(output) == ""
    else
      _error -> false
    end
  end

  defp decode_arguments(:png, path),
    do: [
      "-nostdin",
      "-v",
      "error",
      "-xerror",
      "-i",
      path,
      "-map",
      "0:v:0",
      "-frames:v",
      "1",
      "-f",
      "null",
      "-"
    ]

  defp decode_arguments(:mp4, path),
    do: [
      "-nostdin",
      "-v",
      "error",
      "-xerror",
      "-i",
      path,
      "-map",
      "0:v:0",
      "-f",
      "null",
      "-"
    ]

  defp positive_dimensions?(width, height),
    do: is_integer(width) and width > 0 and is_integer(height) and height > 0

  defp write_temp_file(kind, body) do
    case System.tmp_dir() do
      root when is_binary(root) ->
        root
        |> Path.join(temp_directory_name())
        |> create_temp_file(kind, body)

      _other ->
        :error
    end
  rescue
    _error -> :error
  end

  defp create_temp_file(directory, kind, body) do
    case make_temp_directory(directory) do
      :ok -> write_temp_contents(directory, kind, body)
      _error -> :error
    end
  end

  defp write_temp_contents(directory, kind, body) do
    path = Path.join(directory, "asset" <> extension(kind))

    case secure_write(directory, path, body) do
      :ok ->
        {:ok, directory, path}

      _error ->
        remove_temp(directory)
        :error
    end
  end

  defp secure_write(directory, path, body) do
    with :ok <- chmod_temp_directory(directory) do
      write_temp_body(path, body)
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp temp_directory_name do
    random = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
    "ash-regents-club-media-" <> random
  end

  defp extension(:png), do: ".png"
  defp extension(:mp4), do: ".mp4"

  # The path is generated from 144 random bits under the OS temp root and is
  # revalidated immediately before the filesystem call.
  # sobelow_skip ["Traversal.FileModule"]
  defp make_temp_directory(directory) do
    if safe_temp_directory?(directory) do
      File.mkdir(directory)
    else
      :error
    end
  end

  # The directory passes the same fixed-root and random-name validation.
  # sobelow_skip ["Traversal.FileModule"]
  defp chmod_temp_directory(directory) do
    if safe_temp_directory?(directory) do
      # sobelow_skip ["Traversal.FileModule"]
      File.chmod(directory, 0o700)
    else
      :error
    end
  end

  # The filename is one of two fixed values inside that validated directory.
  # sobelow_skip ["Traversal.FileModule"]
  defp write_temp_body(path, body) do
    if safe_temp_file?(path) do
      # sobelow_skip ["Traversal.FileModule"]
      File.write(path, body, [:binary, :exclusive])
    else
      :error
    end
  end

  defp safe_temp_file?(path) do
    safe_temp_directory?(Path.dirname(path)) and Path.basename(path) in ["asset.png", "asset.mp4"]
  end

  defp safe_temp_directory?(directory) do
    case System.tmp_dir() do
      root when is_binary(root) ->
        expanded_root = Path.expand(root)
        expanded_directory = Path.expand(directory)

        Path.dirname(expanded_directory) == expanded_root and
          String.match?(
            Path.basename(expanded_directory),
            ~r/\Aash-regents-club-media-[A-Za-z0-9_-]{24}\z/
          )

      _other ->
        false
    end
  end

  # Only the validated, process-generated directory above can reach removal.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_temp_tree(directory) do
    if safe_temp_directory?(directory) do
      # sobelow_skip ["Traversal.FileModule"]
      File.rm_rf(directory)
    else
      {:error, directory, :einval}
    end
  end

  if Mix.env() == :test do
    @doc false
    def test_run_bounded(executable, arguments, timeout, max_output),
      do: run_bounded(executable, arguments, timeout, max_output)

    defp find_executable(name) do
      case Application.get_env(:ash_platform, :regents_club_media_executable_finder) do
        finder when is_function(finder, 1) -> finder.(name)
        _other -> System.find_executable(name)
      end
    end

    defp remove_temp(directory) do
      result =
        case Application.get_env(:ash_platform, :regents_club_media_temp_cleanup) do
          cleanup when is_function(cleanup, 1) -> cleanup.(directory)
          _other -> remove_temp_tree(directory)
        end

      match?({:ok, _removed}, result)
    rescue
      _error -> false
    end
  else
    defp find_executable(name), do: System.find_executable(name)

    defp remove_temp(directory) do
      match?({:ok, _removed}, remove_temp_tree(directory))
    rescue
      _error -> false
    end
  end

  defp collect_command(port, deadline, max_output, output_size, chunks) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} when is_binary(data) ->
        collect_command_data(port, deadline, max_output, output_size, chunks, data)

      {^port, {:exit_status, 0}} ->
        command_result(output_size, chunks)

      {^port, {:exit_status, _status}} ->
        :error
    after
      remaining ->
        :error
    end
  end

  defp collect_command_data(port, deadline, max_output, :overflow, _chunks, _data),
    do: collect_command(port, deadline, max_output, :overflow, [])

  defp collect_command_data(port, deadline, max_output, output_size, chunks, data) do
    next_size = output_size + byte_size(data)

    if next_size > max_output do
      collect_command(port, deadline, max_output, :overflow, [])
    else
      collect_command(port, deadline, max_output, next_size, [data | chunks])
    end
  end

  defp command_result(:overflow, _chunks), do: :error

  defp command_result(_output_size, chunks),
    do: {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

  defp stop_port(port, shutdown) do
    if Port.info(port) do
      stop_os_process(port, shutdown)
      Port.close(port)
    end

    :ok
  rescue
    _error -> :ok
  end

  defp stop_os_process(_port, :wrapper), do: :ok

  defp stop_os_process(port, {:signal, kill_executable}) do
    with {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid) do
      kill_port =
        Port.open(
          {:spawn_executable, String.to_charlist(kill_executable)},
          [
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            args: [~c"-KILL", pid |> Integer.to_string() |> String.to_charlist()]
          ]
        )

      receive do
        {^kill_port, {:exit_status, _status}} -> :ok
      after
        @command_shutdown_grace ->
          if Port.info(kill_port), do: Port.close(kill_port)
      end
    end

    :ok
  rescue
    _error -> :ok
  end
end

defmodule AshPlatform.RegentsClub.Actions do
  @moduledoc false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.MediaDecoder
  alias AshPlatform.WalletActions.{Address, Envelope}

  @resource "regents_club_metadata"
  @contract_name "RegentsClub"
  @risk_copy "Collection-wide metadata cutover for Regents Club tokens 1 through 1998. No prepared rollback exists."
  @observation_seconds 45 * 60
  @media_origin "https://media.regents.sh"
  @representative_tokens [1, 1000, 1998]
  @media_concurrency 16
  @media_task_timeout 200_000

  def deployment_readiness(%{lineage: lineage, account_id: account_id}) do
    callback = fn account ->
      with true <- RegentsClub.authorized_account?(account),
           :ok <- functional_readiness(account) do
        {:ok, :ok}
      else
        false -> {:error, :not_authorized}
        {:error, reason} -> {:error, reason}
      end
    end

    case SessionAuthority.transact_lease(lineage, account_id, callback) do
      {:ok, :ok} -> :ok
      {:error, :stale_authority} -> {:error, :session_unavailable}
      result -> result
    end
  end

  def deployment_readiness(_lease), do: {:error, :session_unavailable}
  def status, do: chain_client().status()
  def observe_hash(envelope, hash), do: chain_client().observe(envelope, hash)
  def recover_unknown(envelope), do: chain_client().recover(envelope)

  def prepare(active_wallet, attempt_id, %{lineage: lineage, account_id: account_id}) do
    with true <- RegentsClub.enabled?(),
         true <- RegentsClub.valid_attempt_id?(attempt_id),
         {:ok, signer} <- Address.normalize(active_wallet),
         true <- signer == RegentsClub.owner() do
      callback = fn account -> prepare_current(account, signer, attempt_id) end

      case SessionAuthority.transact_lease(lineage, account_id, callback) do
        {:error, :stale_authority} -> {:error, :session_unavailable}
        result -> result
      end
    else
      false -> {:error, :not_authorized}
      :error -> {:error, :not_authorized}
    end
  end

  def prepare(_active_wallet, _attempt_id, _lease), do: {:error, :session_unavailable}

  def valid_envelope?(envelope) do
    Envelope.valid?(envelope, validation()) and exact_envelope?(envelope)
  rescue
    _ -> false
  end

  def valid_observation_envelope?(envelope) do
    Envelope.valid_for_confirmation?(envelope, validation()) and exact_envelope?(envelope)
  rescue
    _ -> false
  end

  def observation_open?(envelope) when is_map(envelope) do
    with {:ok, deadline, _offset} <-
           DateTime.from_iso8601(field(field(envelope, :metadata), :observation_deadline)),
         :lt <- DateTime.compare(Envelope.current_time(), deadline) do
      true
    else
      _ -> false
    end
  end

  def observation_open?(_envelope), do: false

  defp prepare_current(account, signer, attempt_id) do
    with true <- RegentsClub.authorized_account?(account),
         true <- signer == RegentsClub.owner(),
         :ok <- functional_readiness(account),
         {:ok, preflight} <- chain_client().prepare(signer),
         envelope <- envelope(attempt_id, signer, preflight),
         true <- valid_envelope?(envelope) do
      {:ok, envelope}
    else
      false -> {:error, :not_authorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp envelope(attempt_id, signer, preflight) do
    prepared_at = Envelope.current_time()

    Envelope.new(RegentsClub.action(), signer, RegentsClub.calldata(),
      to: RegentsClub.contract_address(),
      resource: @resource,
      contract_name: @contract_name,
      risk_copy: @risk_copy,
      prepared_at: prepared_at,
      arguments: %{attempt_id: attempt_id, new_base_uri: RegentsClub.new_base_uri()},
      metadata: %{
        anchor_block_number: preflight.anchor.number,
        anchor_block_hash: preflight.anchor.hash,
        current_base_uri: preflight.base_uri,
        boundary_token_uris: preflight.token_uris,
        total_supply: preflight.total_supply,
        erc4906_supported: preflight.erc4906_supported,
        owner_simulation: preflight.owner_simulation,
        non_owner_simulation: preflight.non_owner_simulation,
        gas_estimate: Integer.to_string(preflight.gas_estimate),
        runtime_keccak256: preflight.runtime_keccak256,
        calldata_keccak256: RegentsClub.calldata_keccak256(),
        observation_deadline:
          prepared_at |> DateTime.add(@observation_seconds, :second) |> DateTime.to_iso8601()
      }
    )
  end

  defp exact_envelope?(envelope) do
    exact_transaction?(envelope) and
      exact_arguments?(field(envelope, :arguments)) and
      exact_preflight?(field(envelope, :metadata)) and
      exact_observation_deadline?(envelope)
  end

  defp exact_transaction?(envelope) do
    checks = [
      field(envelope, :resource) == @resource,
      field(envelope, :action) == RegentsClub.action(),
      field(envelope, :chain_id) == RegentsClub.chain_id(),
      field(envelope, :to) == RegentsClub.contract_address(),
      field(envelope, :value) == "0",
      field(envelope, :data) == RegentsClub.calldata(),
      field(envelope, :expected_signer) == RegentsClub.owner(),
      field(envelope, :risk_copy) == @risk_copy
    ]

    Enum.all?(checks)
  end

  defp exact_arguments?(arguments) when is_map(arguments) do
    field(arguments, :new_base_uri) == RegentsClub.new_base_uri() and
      RegentsClub.valid_attempt_id?(field(arguments, :attempt_id))
  end

  defp exact_arguments?(_arguments), do: false

  defp exact_preflight?(metadata) when is_map(metadata) do
    anchor_number = field(metadata, :anchor_block_number)
    gas_estimate = field(metadata, :gas_estimate)

    checks = [
      is_integer(anchor_number) and anchor_number >= 0,
      valid_hash?(field(metadata, :anchor_block_hash)),
      field(metadata, :current_base_uri) == RegentsClub.old_base_uri(),
      field(metadata, :runtime_keccak256) == RegentsClub.runtime_keccak256(),
      field(metadata, :total_supply) == 1998,
      field(metadata, :erc4906_supported) == true,
      field(metadata, :owner_simulation) == "success",
      field(metadata, :non_owner_simulation) == "revert",
      field(metadata, :calldata_keccak256) == RegentsClub.calldata_keccak256(),
      positive_integer_string?(gas_estimate),
      boundary_uris?(field(metadata, :boundary_token_uris), RegentsClub.old_base_uri())
    ]

    Enum.all?(checks)
  end

  defp exact_preflight?(_metadata), do: false

  defp exact_observation_deadline?(envelope) do
    with {:ok, prepared_at, _offset} <- DateTime.from_iso8601(field(envelope, :prepared_at)),
         {:ok, deadline, _offset} <-
           DateTime.from_iso8601(field(field(envelope, :metadata), :observation_deadline)) do
      DateTime.diff(deadline, prepared_at, :second) == @observation_seconds
    else
      _ -> false
    end
  end

  defp validation do
    [
      to: RegentsClub.contract_address(),
      signer: RegentsClub.owner(),
      resource: @resource,
      contract_name: @contract_name,
      action: RegentsClub.action()
    ]
  end

  defp functional_readiness(account) do
    with true <- RegentsClub.authorized_account?(account),
         :ok <- public_privy_bootstrap(),
         :ok <- server_verifier(),
         true <- Application.get_env(:ash_platform, :regents_club_privy_origin_canary, false),
         :ok <- media_attestation(),
         :ok <- media_probes(),
         :ok <- chain_client().readiness() do
      :ok
    else
      false -> {:error, :privy_origin_canary_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp public_privy_bootstrap do
    case Application.get_env(:ash_platform, :privy, [])[:app_id] do
      value when is_binary(value) ->
        if(String.trim(value) == "", do: {:error, :privy_unavailable}, else: :ok)

      _ ->
        {:error, :privy_unavailable}
    end
  end

  defp server_verifier do
    verifier = Application.get_env(:ash_platform, :privy_verifier, AshPlatform.Privy)
    config = Application.get_env(:ash_platform, :privy, [])

    capable? =
      Code.ensure_loaded?(verifier) and function_exported?(verifier, :verify_session_pair, 1)

    configured? = verifier != AshPlatform.Privy or present?(config[:verification_key])
    if capable? and configured?, do: :ok, else: {:error, :privy_verifier_unavailable}
  end

  defp media_attestation do
    attestation = RegentsClub.media_release_attestation()

    checks = [
      Application.get_env(:ash_platform, :regents_club_media_full_corpus_attestation) ==
        attestation["release_manifest_sha256"],
      attestation["release_manifest_sha256"] == RegentsClub.release_manifest_sha256(),
      attestation["full_corpus_route_count"] ==
        RegentsClub.last_token_id() - RegentsClub.first_token_id() + 1,
      attestation["live_probe_token_ids"] == @representative_tokens,
      attestation["operator_attestation_required"] == true,
      present?(attestation["active_image_digest"]),
      present?(attestation["artifact_manifest_sha256"]),
      present?(attestation["production_deployment_verification_sha256"])
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :media_full_corpus_attestation_required}
  end

  if Mix.env() == :test do
    defp media_probes do
      case Application.get_env(:ash_platform, :regents_club_media_probe_module) do
        module when is_atom(module) and not is_nil(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :media_readiness, 0),
            do: module.media_readiness(),
            else: {:error, :media_probe_failed}

        _ ->
          live_media_probes()
      end
    end

    defp release_manifest do
      case Application.get_env(:ash_platform, :regents_club_media_manifest_module) do
        module when is_atom(module) and not is_nil(module) ->
          if Code.ensure_loaded?(module) and function_exported?(module, :release_manifest, 0),
            do: module.release_manifest(),
            else: :error

        _other ->
          {:ok, RegentsClub.release_manifest()}
      end
    rescue
      _error -> :error
    end
  else
    defp media_probes, do: live_media_probes()

    defp release_manifest do
      {:ok, RegentsClub.release_manifest()}
    rescue
      _error -> :error
    end
  end

  defp live_media_probes do
    client = Application.get_env(:ash_platform, :regents_club_media_http_client, Req)

    with {:ok, release_manifest} <- release_manifest(),
         {:ok, %{status: 200, body: body}} <- get(client, @media_origin <> "/healthz"),
         true <- is_binary(body) and String.trim(body) == "ok",
         :ok <- verify_live_release(client, release_manifest) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_live_release(client, release_manifest) when is_map(release_manifest) do
    token_ids = Enum.to_list(RegentsClub.first_token_id()..RegentsClub.last_token_id())

    with true <- map_size(release_manifest) == length(token_ids),
         true <- Enum.sort(Map.keys(release_manifest)) == token_ids do
      token_ids
      |> Task.async_stream(
        fn token_id -> verify_live_token(client, Map.fetch!(release_manifest, token_id)) end,
        max_concurrency: @media_concurrency,
        ordered: false,
        timeout: @media_task_timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce(:ok, fn
        {:ok, :ok}, result ->
          result

        _failure, _result ->
          {:error, :media_probe_failed}
      end)
    else
      false -> {:error, :media_probe_failed}
    end
  end

  defp verify_live_release(_client, _release_manifest), do: {:error, :media_probe_failed}

  defp verify_live_token(client, %{token_id: token_id} = release_row) do
    with {:ok, metadata} <- metadata(client, release_row),
         image when is_binary(image) <- metadata["image"],
         animation when is_binary(animation) <- metadata["animation_url"],
         true <- exact_asset_url?(image, release_row.image.path),
         true <- exact_asset_url?(animation, release_row.video.path),
         :ok <- verify_asset(client, image, :png, token_id, release_row.image),
         :ok <- verify_asset(client, animation, :mp4, token_id, release_row.video) do
      :ok
    else
      _ ->
        {:error, :media_probe_failed}
    end
  end

  defp metadata(client, %{token_id: token_id, metadata: expected}) do
    with {:ok, %{status: 200, headers: headers, body: body}} <-
           get(client, @media_origin <> "/metadata/#{token_id}"),
         true <- content_type?(headers, "application/json"),
         true <- is_binary(body) and byte_size(body) == expected.bytes,
         true <- sha256(body) == expected.sha256,
         {:ok, metadata} when is_map(metadata) <- Jason.decode(body) do
      {:ok, metadata}
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_asset(client, url, kind, token_id, expected)
       when token_id in @representative_tokens,
       do: verify_representative_asset(client, url, kind, expected)

  defp verify_asset(client, url, kind, _token_id, expected) when kind in [:png, :mp4] do
    with {:ok, %{status: 206, headers: headers, body: body}} <-
           get(client, url, [{"range", "bytes=0-0"}]),
         true <- content_type?(headers, asset_content_type(kind)),
         true <- valid_partial_range?(headers, body, expected.bytes) do
      :ok
    else
      _ -> {:error, :media_probe_failed}
    end
  end

  defp verify_representative_asset(client, url, kind, expected) do
    with {:ok, %{status: 200, headers: headers, body: body}} <- get(client, url),
         true <- content_type?(headers, asset_content_type(kind)),
         true <- header(headers, "content-length") == Integer.to_string(expected.bytes),
         true <- byte_size(body) == expected.bytes,
         true <- sha256(body) == expected.sha256,
         true <- MediaDecoder.validate(kind, body),
         {:ok, %{status: 206, headers: range_headers, body: range_body}} <-
           get(client, url, [{"range", "bytes=0-0"}]),
         true <- content_type?(range_headers, asset_content_type(kind)),
         true <- valid_range?(range_headers, range_body, body, expected.bytes) do
      :ok
    else
      _ ->
        {:error, :media_probe_failed}
    end
  end

  defp exact_asset_url?(url, expected_path) do
    case URI.new(url) do
      {:ok,
       %URI{
         scheme: "https",
         host: "media.regents.sh",
         userinfo: nil,
         path: path,
         query: nil,
         fragment: nil
       }}
      when is_binary(path) ->
        path == "/" <> expected_path and url == @media_origin <> "/" <> expected_path

      _ ->
        false
    end
  end

  defp valid_range?(
         headers,
         <<first_byte>>,
         <<first_byte, _rest::binary>> = full_body,
         expected_bytes
       ),
       do:
         byte_size(full_body) == expected_bytes and
           header(headers, "content-range") == "bytes 0-0/#{expected_bytes}"

  defp valid_range?(_headers, _range_body, _full_body, _expected_bytes), do: false

  defp valid_partial_range?(headers, <<_first_byte>>, expected_bytes),
    do: header(headers, "content-range") == "bytes 0-0/#{expected_bytes}"

  defp valid_partial_range?(_headers, _body, _expected_bytes), do: false

  defp asset_content_type(:png), do: "image/png"
  defp asset_content_type(:mp4), do: "video/mp4"

  defp content_type?(headers, expected) do
    case header(headers, "content-type") do
      value when is_binary(value) ->
        value |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase() ==
          expected

      _ ->
        false
    end
  end

  defp header(headers, name) when is_map(headers) do
    case Map.get(headers, name) do
      [value | _] when is_binary(value) -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == name, do: value

      _ ->
        nil
    end)
  end

  defp header(_headers, _name), do: nil

  defp get(client, url, headers \\ []) do
    client.get(url,
      connect_options: [timeout: 3_000],
      receive_timeout: 8_000,
      retry: false,
      decode_body: false,
      headers: headers
    )
  rescue
    _ -> {:error, :media_probe_failed}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp sha256(contents),
    do: :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)

  defp boundary_uris?(uris, base_uri) when is_map(uris) do
    field(uris, :first) == base_uri <> Integer.to_string(RegentsClub.first_token_id()) and
      field(uris, :last) == base_uri <> Integer.to_string(RegentsClub.last_token_id())
  end

  defp boundary_uris?(_uris, _base_uri), do: false

  defp positive_integer_string?(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> true
      _ -> false
    end
  end

  defp positive_integer_string?(_value), do: false

  defp valid_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/\A[0-9a-fA-F]+\z/)

  defp valid_hash?(_hash), do: false
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp chain_client,
    do:
      Application.get_env(
        :ash_platform,
        :regents_club_chain_client,
        AshPlatform.RegentsClub.RpcClient
      )
end
