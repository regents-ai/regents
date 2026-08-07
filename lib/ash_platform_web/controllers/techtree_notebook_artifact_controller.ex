defmodule AshPlatformWeb.TechtreeNotebookArtifactController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree

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
        if Enum.all?(value, &is_binary/1), do: {:ok, value}, else: {:error, :invalid_request}

      _result ->
        {:error, :invalid_request}
    end
  end

  defp validate_manifest_bytes(manifest_json) do
    if String.valid?(manifest_json) and byte_size(manifest_json) <= 524_288,
      do: :ok,
      else: {:error, :invalid_request}
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

  defp action_error(conn, reason) do
    message = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)

    cond do
      String.contains?(message, "unique_node_source") or
        String.contains?(message, "already exists") or
        String.contains?(message, "has already been taken") or
          String.contains?(message, "unique constraint") ->
        error(conn, 409, :conflict)

      String.contains?(message, "current payload") ->
        error(conn, 422, :stale_node_payload)

      String.contains?(message, "public node") ->
        error(conn, 404, :not_found)

      String.contains?(message, "Notebook") or String.contains?(message, "notebook") ->
        error(conn, 422, :invalid_notebook_artifact)

      true ->
        error(conn, 503, :temporarily_unavailable)
    end
  end

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
