defmodule AshPlatform.Techtree.PublicationReceipt do
  @moduledoc false

  def published(node, replayed) do
    %{
      action_id: node.id,
      capability_id: "techtree.node.publish",
      action_kind: "publish",
      resource_type: "techtree_node",
      resource_id: node.id,
      status: "published",
      idempotency_key: node.idempotency_key,
      created_at: DateTime.to_iso8601(node.inserted_at),
      updated_at: DateTime.to_iso8601(node.published_at),
      public_url: "/techtree/nodes/#{node.id}",
      next_recommended_action: "view_public_node",
      next_poll_at: nil,
      approval_required: false,
      error_code: nil,
      replayed: replayed
    }
  end

  def failed(code, idempotency_key) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      action_id: Ash.UUID.generate(),
      capability_id: "techtree.node.publish",
      action_kind: "publish",
      resource_type: "techtree_node",
      resource_id: nil,
      status: "failed",
      idempotency_key: admitted_key(idempotency_key),
      created_at: now,
      updated_at: now,
      public_url: nil,
      next_recommended_action: next_action(code),
      next_poll_at: nil,
      approval_required: false,
      error_code: Atom.to_string(code),
      replayed: false
    }
  end

  defp admitted_key(value) when is_binary(value) do
    if String.valid?(value) and String.length(value) in 1..255, do: value, else: nil
  end

  defp admitted_key(_value), do: nil

  defp next_action(:temporarily_unavailable), do: "retry_later"
  defp next_action(:rate_limited), do: "retry_later"
  defp next_action(:unauthorized), do: "sign_new_request"
  defp next_action(:forbidden), do: "pair_agent_with_regent"
  defp next_action(:conflict), do: "use_new_idempotency_key"
  defp next_action(:invalid_input), do: "correct_publication_request"
end
