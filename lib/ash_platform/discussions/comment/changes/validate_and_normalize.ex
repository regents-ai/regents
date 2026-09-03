defmodule AshPlatform.Discussions.Comment.Changes.ValidateAndNormalize do
  use Ash.Resource.Change

  alias AshPlatform.Autolaunch
  alias AshPlatform.Discussions.Markdown

  @impl true
  def change(changeset, _opts, _context) do
    target_type = Ash.Changeset.get_argument(changeset, :target_type)
    target_id = Ash.Changeset.get_argument(changeset, :target_id)
    body = Ash.Changeset.get_argument(changeset, :body)
    client_request_id = Ash.Changeset.get_argument(changeset, :client_request_id)

    changeset
    |> validate_target(target_type, target_id)
    |> normalize_body(body)
    |> Ash.Changeset.change_attribute(:target_type, target_type)
    |> Ash.Changeset.change_attribute(:target_id, target_id)
    |> Ash.Changeset.change_attribute(:client_request_id, client_request_id)
  end

  defp validate_target(changeset, target_type, target_id) do
    if target_exists?(target_type, target_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset, field: :target_id, message: "does not exist")
    end
  end

  defp target_exists?(:autolaunch_auction, id), do: present?(Autolaunch.get_public_auction(id))
  defp target_exists?(:autolaunch_token, id), do: present?(Autolaunch.get_public_token(id))
  defp target_exists?(_target_type, _id), do: false

  defp present?({:ok, record}), do: not is_nil(record)
  defp present?(_result), do: false

  defp normalize_body(changeset, body) do
    case Markdown.normalize_and_validate(body) do
      {:ok, normalized} ->
        Ash.Changeset.change_attribute(changeset, :body, normalized)

      {:error, :empty} ->
        Ash.Changeset.add_error(changeset, field: :body, message: "must not be empty")

      {:error, :too_long} ->
        Ash.Changeset.add_error(changeset,
          field: :body,
          message: "must be 2,000 characters or fewer"
        )

      {:error, _reason} ->
        Ash.Changeset.add_error(changeset,
          field: :body,
          message: "contains unsupported formatting"
        )
    end
  end
end
