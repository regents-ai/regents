defmodule AshPlatformWeb.TechtreeNotebookArtifactController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree

  @maximum_node_payload_hash_length 128
  @maximum_source_hash_length 80
  @maximum_payload_hash_length 80
  @maximum_marimo_version_length 32
  @maximum_run_url_length 2_048
  @maximum_manifest_length 524_288
  @maximum_asset_length 2_048

  @allowed_keys [
    "id",
    "node_payload_hash",
    "source_hash",
    "payload_hash",
    "marimo_version",
    "run_url",
    "manifest_json",
    "allowed_assets"
  ]
  def create(%Plug.Conn{query_string: ""} = conn, %{"id" => id} = params) do
    with {:ok, attributes} <- validate(params, id),
         :ok <- current_node_payload(attributes),
         :ok <- existing_identity(attributes),
         {:ok, artifact} <- import_artifact(conn, attributes) do
      conn
      |> put_status(:created)
      |> json(%{data: public_artifact(artifact)})
    else
      {:error, :invalid_request} -> error(conn, 400, :invalid_request)
      {:error, :not_found} -> error(conn, 404, :not_found)
      {:error, :forbidden} -> error(conn, 403, :forbidden)
      {:error, :conflict} -> error(conn, 409, :conflict)
      {:error, :invalid_notebook_artifact} -> error(conn, 422, :invalid_notebook_artifact)
      {:error, :stale_node_payload} -> error(conn, 422, :stale_node_payload)
      {:error, :temporarily_unavailable} -> error(conn, 503, :temporarily_unavailable)
      {:error, %Ash.Error.Forbidden{}} -> error(conn, 403, :forbidden)
      {:error, reason} -> action_error(conn, reason)
    end
  end

  def create(conn, _params), do: error(conn, 400, :invalid_request)

  defp import_artifact(conn, attributes) do
    storage_call = fn ->
      Techtree.import_agent_notebook_artifact(
        attributes.node_id,
        attributes.node_payload_hash,
        attributes.source_hash,
        attributes.payload_hash,
        attributes.marimo_version,
        attributes.run_url,
        attributes.manifest_json,
        attributes.allowed_assets,
        actor: conn.assigns.agent_identity
      )
    end

    case Map.get(conn.private, :techtree_notebook_artifact_importer) do
      nil -> storage_call.()
      importer -> importer.(storage_call)
    end
  end

  defp validate(params, id) do
    with :ok <- allow_parameters(params),
         {:ok, node_id} <- uuid(id),
         {:ok, node_payload_hash} <- required_string(params, "node_payload_hash"),
         {:ok, source_hash} <- required_string(params, "source_hash"),
         {:ok, payload_hash} <- required_string(params, "payload_hash"),
         {:ok, marimo_version} <- required_string(params, "marimo_version"),
         {:ok, run_url} <- required_string(params, "run_url"),
         {:ok, manifest_json} <- required_string(params, "manifest_json"),
         {:ok, allowed_assets} <- required_assets(params, "allowed_assets"),
         :ok <- validate_max_length(node_payload_hash, @maximum_node_payload_hash_length),
         :ok <- validate_max_length(source_hash, @maximum_source_hash_length),
         :ok <- validate_max_length(payload_hash, @maximum_payload_hash_length),
         :ok <- validate_max_length(marimo_version, @maximum_marimo_version_length),
         :ok <- validate_max_length(run_url, @maximum_run_url_length),
         :ok <- validate_manifest_bytes(manifest_json) do
      {:ok,
       %{
         node_id: node_id,
         node_payload_hash: node_payload_hash,
         source_hash: source_hash,
         payload_hash: payload_hash,
         marimo_version: marimo_version,
         run_url: run_url,
         manifest_json: manifest_json,
         allowed_assets: allowed_assets
       }}
    end
  end

  defp allow_parameters(params) do
    if Enum.all?(Map.keys(params), &(&1 in @allowed_keys)),
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_request}
    end
  end

  defp required_string(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _result -> {:error, :invalid_request}
    end
  end

  defp required_assets(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_list(value) and length(value) == 3 ->
        if Enum.all?(value, &valid_asset?/1), do: {:ok, value}, else: {:error, :invalid_request}

      _result ->
        {:error, :invalid_request}
    end
  end

  defp validate_manifest_bytes(manifest_json) do
    if String.valid?(manifest_json) and byte_size(manifest_json) <= @maximum_manifest_length,
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp validate_max_length(value, maximum) do
    if String.valid?(value) and String.length(value) <= maximum,
      do: :ok,
      else: {:error, :invalid_request}
  end

  defp valid_asset?(value) when is_binary(value),
    do: String.valid?(value) and String.length(value) <= @maximum_asset_length

  defp valid_asset?(_value), do: false

  defp current_node_payload(attributes) do
    case Techtree.get_public_node(attributes.node_id, actor: nil) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, %{payload_hash: payload_hash}} when payload_hash == attributes.node_payload_hash ->
        :ok

      {:ok, _node} ->
        {:error, :stale_node_payload}

      {:error, _error} ->
        {:error, :temporarily_unavailable}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp existing_identity(attributes) do
    case Ecto.Adapters.SQL.query(
           AshPlatform.Repo,
           """
           SELECT 1
           FROM techtree.notebook_artifacts
           WHERE node_id = $1
             AND node_payload_hash = $2
             AND source_hash = $3
           LIMIT 1
           """,
           [
             Ecto.UUID.dump!(attributes.node_id),
             attributes.node_payload_hash,
             attributes.source_hash
           ]
         ) do
      {:ok, %{rows: [[1]]}} -> {:error, :conflict}
      {:ok, %{rows: []}} -> :ok
      {:error, _error} -> {:error, :temporarily_unavailable}
    end
  rescue
    _error -> {:error, :temporarily_unavailable}
  end

  defp public_artifact(artifact) do
    %{
      id: artifact.id,
      node_id: artifact.node_id,
      node_payload_hash: artifact.node_payload_hash,
      source_hash: artifact.source_hash,
      payload_hash: artifact.payload_hash,
      marimo_version: artifact.marimo_version,
      runtime: Atom.to_string(artifact.runtime),
      compatibility: Atom.to_string(artifact.compatibility),
      run_url: artifact.run_url,
      allowed_assets: artifact.allowed_assets,
      inserted_at: DateTime.to_iso8601(artifact.inserted_at)
    }
  end

  defp action_error(conn, %Ash.Error.Forbidden{}), do: error(conn, 403, :forbidden)

  defp action_error(conn, %Ash.Error.Invalid{errors: errors}) do
    if unique_identity_error?(errors) do
      error(conn, 409, :conflict)
    else
      error(conn, 422, :invalid_notebook_artifact)
    end
  end

  defp action_error(conn, %Ash.Error.Unknown{}),
    do: error(conn, 503, :temporarily_unavailable)

  defp action_error(conn, %Ecto.ConstraintError{}),
    do: error(conn, 503, :temporarily_unavailable)

  defp action_error(conn, _reason), do: error(conn, 503, :temporarily_unavailable)

  defp unique_identity_error?(errors) when is_list(errors) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{private_vars: private_vars}
      when is_list(private_vars) ->
        Keyword.get(private_vars, :constraint) == "notebook_artifacts_unique_node_source_index"

      _error ->
        false
    end)
  end

  defp unique_identity_error?(_errors), do: false

  defp error(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message(code)}})
  end

  defp message(:invalid_request), do: "The agent write request is invalid."
  defp message(:forbidden), do: "The verified agent is not the node publisher."
  defp message(:not_found), do: "The requested public node was not found."
  defp message(:conflict), do: "The notebook artifact identity already exists."
  defp message(:invalid_notebook_artifact), do: "The notebook artifact is invalid."
  defp message(:stale_node_payload), do: "The notebook does not match the node's current payload."

  defp message(:temporarily_unavailable),
    do: "The agent write could not be completed at this time."
end
