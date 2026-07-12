defmodule AshPlatform.Techtree.NotebookArtifact.Proof do
  @moduledoc false

  @supported_marimo_version "0.23.14"
  @hash_pattern ~r/\Asha256:[0-9a-f]{64}\z/
  @required_asset_origins [
    "https://cdn.jsdelivr.net",
    "https://wasm.marimo.app",
    "https://files.pythonhosted.org"
  ]

  def validate(attributes) when is_map(attributes) do
    with :ok <- validate_version(attributes),
         :ok <- validate_hashes(attributes),
         :ok <- validate_manifest(attributes),
         :ok <- validate_run_url(attributes),
         :ok <- validate_allowed_assets(attributes) do
      :ok
    end
  end

  def runnable?(artifact) do
    artifact
    |> Map.take([
      :source_hash,
      :payload_hash,
      :marimo_version,
      :runtime,
      :compatibility,
      :run_url,
      :manifest_json,
      :allowed_assets
    ])
    |> validate()
    |> Kernel.==(:ok)
  end

  defp validate_version(%{
         marimo_version: @supported_marimo_version,
         runtime: :pyodide,
         compatibility: :verified
       }),
       do: :ok

  defp validate_version(_attributes), do: {:error, "uses an unsupported notebook runtime"}

  defp validate_hashes(%{
         source_hash: source_hash,
         payload_hash: payload_hash,
         manifest_json: manifest_json
       }) do
    cond do
      not valid_hash?(source_hash) ->
        {:error, "has an invalid source hash"}

      not valid_hash?(payload_hash) ->
        {:error, "has an invalid payload hash"}

      payload_hash != sha256(manifest_json) ->
        {:error, "does not match its artifact manifest"}

      true ->
        :ok
    end
  end

  defp validate_hashes(_attributes), do: {:error, "is missing artifact hashes"}

  defp validate_manifest(%{
         manifest_json: manifest_json,
         source_hash: source_hash,
         marimo_version: marimo_version
       }) do
    with {:ok,
          %{
            "schema_version" => 1,
            "runtime" => "pyodide",
            "marimo_version" => ^marimo_version,
            "source_hash" => ^source_hash,
            "files" => files
          }}
         when is_list(files) and files != [] <- Jason.decode(manifest_json),
         true <- Enum.all?(files, &valid_file?/1),
         true <- Enum.any?(files, &(&1["path"] == "index.html")) do
      :ok
    else
      _result -> {:error, "has an invalid artifact manifest"}
    end
  end

  defp validate_manifest(_attributes), do: {:error, "is missing its artifact manifest"}

  defp validate_run_url(%{run_url: run_url, payload_hash: payload_hash})
       when is_binary(run_url) and is_binary(payload_hash) do
    case URI.parse(run_url) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        userinfo: nil,
        query: nil,
        fragment: nil,
        path: path
      }
      when scheme in ["http", "https"] and is_binary(host) and is_integer(port) and
             is_binary(path) and path != "" ->
        with true <- allowed_origin?(scheme, host, port),
             :ok <- validate_content_address(path, payload_hash) do
          :ok
        else
          false -> {:error, "uses an unapproved notebook origin"}
          {:error, message} -> {:error, message}
        end

      _uri ->
        {:error, "has an invalid notebook URL"}
    end
  end

  defp validate_run_url(_attributes), do: {:error, "is missing its notebook URL"}

  defp validate_content_address(path, "sha256:" <> payload_hash) do
    if payload_hash in Path.split(path),
      do: :ok,
      else: {:error, "does not use its content-addressed artifact path"}
  end

  defp validate_content_address(_path, _payload_hash),
    do: {:error, "has an invalid payload hash"}

  defp allowed_origin?(scheme, host, port) do
    origin =
      if URI.default_port(scheme) == port,
        do: "#{scheme}://#{host}",
        else: "#{scheme}://#{host}:#{port}"

    origin in Application.fetch_env!(:ash_platform, :notebook_origins)
  end

  defp validate_allowed_assets(%{allowed_assets: @required_asset_origins}), do: :ok

  defp validate_allowed_assets(_attributes), do: {:error, "has invalid allowed assets"}

  defp valid_file?(%{"path" => path, "sha256" => hash})
       when is_binary(path) and is_binary(hash) do
    path != "" and not String.starts_with?(path, "/") and
      not Enum.member?(Path.split(path), "..") and valid_hash?(hash)
  end

  defp valid_file?(_file), do: false

  defp valid_hash?(value) when is_binary(value), do: Regex.match?(@hash_pattern, value)
  defp valid_hash?(_value), do: false

  defp sha256(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end
end
