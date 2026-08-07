defmodule AshPlatformWeb.TechtreeEvidenceController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Techtree

  @allowed_keys ["id", "status", "reason", "evidence_reference_ids"]
  @statuses %{
    "reproduced" => :reproduced,
    "disputed" => :disputed,
    "superseded" => :superseded,
    "expired" => :expired,
    "invalidated" => :invalidated
  }

  def create(%Plug.Conn{query_string: ""} = conn, %{"id" => id} = params) do
    with {:ok, attributes} <- validate(params, id),
         {:ok, update} <- append(conn, attributes) do
      conn
      |> put_status(:created)
      |> json(%{data: public_update(update)})
    else
      {:error, :invalid_request} -> error(conn, 400, :invalid_request)
      {:error, :invalid_evidence_reference} -> error(conn, 422, :invalid_evidence_reference)
      {:error, :forbidden} -> error(conn, 403, :forbidden)
      {:error, :temporarily_unavailable} -> error(conn, 503, :temporarily_unavailable)
      {:error, %Ash.Error.Forbidden{}} -> error(conn, 403, :forbidden)
      {:error, reason} -> action_error(conn, reason)
    end
  end

  def create(conn, _params), do: error(conn, 400, :invalid_request)

  defp append(conn, attributes) do
    Techtree.append_evidence_state_update(
      attributes.node_id,
      attributes.status,
      attributes.reason,
      attributes.evidence_reference_ids,
      conn.assigns.verified_siwa_envelope,
      actor: conn.assigns.agent_identity
    )
  end

  defp validate(params, id) do
    with :ok <- allow_parameters(params),
         {:ok, node_id} <- uuid(id),
         {:ok, status} <- status(params["status"]),
         {:ok, reason} <- reason(Map.get(params, "reason")),
         {:ok, reference_ids} <-
           references(Map.get(params, "evidence_reference_ids", []), node_id) do
      {:ok,
       %{
         node_id: node_id,
         status: status,
         reason: reason,
         evidence_reference_ids: reference_ids
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

  defp status(value) do
    case Map.fetch(@statuses, value) do
      {:ok, status} -> {:ok, status}
      :error -> {:error, :invalid_request}
    end
  end

  defp reason(nil), do: {:ok, nil}

  defp reason(value) when is_binary(value) do
    if String.valid?(value) and String.length(value) in 1..2_000,
      do: {:ok, value},
      else: {:error, :invalid_request}
  end

  defp reason(_value), do: {:error, :invalid_request}

  defp references(reference_ids, node_id) when is_list(reference_ids) do
    if length(reference_ids) <= 100 do
      with {:ok, reference_ids} <- cast_references(reference_ids),
           true <- length(reference_ids) == length(Enum.uniq(reference_ids)),
           false <- node_id in reference_ids do
        {:ok, reference_ids}
      else
        _result -> {:error, :invalid_evidence_reference}
      end
    else
      {:error, :invalid_evidence_reference}
    end
  end

  defp references(_reference_ids, _node_id), do: {:error, :invalid_request}

  defp cast_references(reference_ids) do
    Enum.reduce_while(reference_ids, {:ok, []}, fn reference_id, {:ok, casted} ->
      case Ecto.UUID.cast(reference_id) do
        {:ok, reference_id} -> {:cont, {:ok, [reference_id | casted]}}
        :error -> {:halt, {:error, :invalid_evidence_reference}}
      end
    end)
    |> case do
      {:ok, reference_ids} -> {:ok, Enum.reverse(reference_ids)}
      error -> error
    end
  end

  defp public_update(update) do
    %{
      id: update.id,
      node_id: update.node_id,
      status: Atom.to_string(update.status),
      reason: update.reason,
      evidence_reference_ids: update.evidence_reference_ids,
      updated_at: DateTime.to_iso8601(update.inserted_at)
    }
  end

  defp action_error(conn, reason) do
    message = Exception.message(reason)

    cond do
      String.contains?(message, "invalid_evidence_reference") ->
        error(conn, 422, :invalid_evidence_reference)

      String.contains?(message, "temporary database error") ->
        error(conn, 503, :temporarily_unavailable)

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
  defp message(:invalid_evidence_reference), do: "The evidence reference is invalid."

  defp message(:temporarily_unavailable),
    do: "The agent write could not be completed at this time."
end
