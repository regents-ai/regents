defmodule AshPlatformWeb.TechtreePublicationController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree.{Publication, PublicationInput, PublicationReceipt}

  @kinds %{
    "environment_family" => :environment_family,
    "benchmark_slice" => :benchmark_slice,
    "uplift_report" => :uplift_report,
    "reproduction" => :reproduction,
    "audit" => :audit
  }
  @digest_pattern ~r/\A[0-9a-f]{64}\z/

  def create(%Plug.Conn{query_string: ""} = conn, params) do
    with {:ok, attributes} <- validate(params),
         {:ok, node, replayed} <-
           Publication.publish(
             attributes,
             conn.assigns.agent_identity,
             conn.assigns.verified_siwa_envelope
           ) do
      status = if replayed, do: :ok, else: :created

      conn
      |> put_status(status)
      |> json(%{data: PublicationReceipt.published(node, replayed)})
    else
      {:error, :conflict} ->
        error(conn, :conflict, :conflict)

      {:error, :forbidden} ->
        error(conn, :forbidden, :forbidden)

      {:error, :invalid_input} ->
        error(conn, :bad_request, :invalid_input)

      {:error, _reason} ->
        error(conn, :service_unavailable, :temporarily_unavailable)
    end
  end

  def create(conn, _params), do: error(conn, :bad_request, :invalid_input)

  defp validate(params) do
    params = PublicationInput.normalize(params)

    with {:ok, regent_id} <- uuid(params["regent_id"]),
         {:ok, tree_id} <- uuid(params["tree_id"]),
         {:ok, kind} <- kind(params["kind"]),
         {:ok, title} <- string(params["title"], 1, 200),
         {:ok, summary} <- optional_string(params["summary"], 2_000),
         {:ok, payload_hash} <- optional_string(params["payload_hash"], 128),
         {:ok, idempotency_key} <- string(params["idempotency_key"], 1, 255),
         {:ok, manifest_digest} <- digest(params["manifest_digest"]) do
      {:ok,
       %{
         regent_id: regent_id,
         tree_id: tree_id,
         kind: kind,
         title: title,
         summary: summary,
         payload_hash: payload_hash,
         idempotency_key: idempotency_key,
         manifest_digest: manifest_digest
       }}
    end
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_input}
    end
  end

  defp kind(value) do
    case Map.fetch(@kinds, value) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_input}
    end
  end

  defp string(value, minimum, maximum) when is_binary(value) do
    if String.valid?(value) do
      length = String.length(value)

      if length >= minimum and length <= maximum,
        do: {:ok, value},
        else: {:error, :invalid_input}
    else
      {:error, :invalid_input}
    end
  end

  defp string(_value, _minimum, _maximum), do: {:error, :invalid_input}

  defp optional_string(nil, _maximum), do: {:ok, nil}
  defp optional_string(value, maximum), do: string(value, 0, maximum)

  defp digest(value) when is_binary(value) do
    if Regex.match?(@digest_pattern, value),
      do: {:ok, value},
      else: {:error, :invalid_input}
  end

  defp digest(_value), do: {:error, :invalid_input}

  defp error(conn, status, code) do
    idempotency_key =
      case conn.body_params do
        %{"idempotency_key" => value} when is_binary(value) -> value
        _params -> nil
      end

    conn
    |> put_status(status)
    |> json(%{
      error: %{code: code, message: message(code)},
      receipt: PublicationReceipt.failed(code, idempotency_key)
    })
  end

  defp message(:conflict),
    do: "The idempotency key was already used for a different publication."

  defp message(:forbidden),
    do: "The verified agent is not paired with the requested Regent."

  defp message(:invalid_input), do: "The publication request is invalid."

  defp message(:temporarily_unavailable),
    do: "The publication could not be completed at this time."
end
