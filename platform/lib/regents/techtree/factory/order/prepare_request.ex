defmodule Regents.Techtree.Factory.Order.PrepareRequest do
  @moduledoc """
  Populates requester identity (`human_account_id`, `agent_wallet`), derives a
  safe lowercase-hyphenated `project_name` slug when omitted, and validates any
  uploaded base64 material archive (`<= 5 MiB` `.tar.gz`) before persisting a
  new Factory order.
  """

  use Ash.Resource.Change

  alias Regents.Techtree.Projects.Package

  @slug_max 63

  @impl true
  def change(changeset, _opts, context) do
    changeset
    |> set_requester(context.actor)
    |> ensure_project_name()
    |> attach_materials()
  end

  defp set_requester(changeset, %{role: :agent, human_account_id: account_id, wallet_address: w})
       when is_integer(account_id) and is_binary(w) do
    changeset
    |> Ash.Changeset.force_change_attribute(:human_account_id, account_id)
    |> Ash.Changeset.force_change_attribute(:agent_wallet, String.downcase(w))
  end

  defp set_requester(changeset, %{role: :human, human_account_id: account_id})
       when is_integer(account_id) do
    Ash.Changeset.force_change_attribute(changeset, :human_account_id, account_id)
  end

  defp set_requester(changeset, _actor), do: changeset

  defp ensure_project_name(changeset) do
    case Ash.Changeset.get_attribute(changeset, :project_name) do
      name when is_binary(name) and name != "" ->
        validate_slug(changeset, name)

      _missing ->
        title = Ash.Changeset.get_attribute(changeset, :title) || "order"
        Ash.Changeset.force_change_attribute(changeset, :project_name, slugify(title))
    end
  end

  defp validate_slug(changeset, name) do
    if Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, name) and byte_size(name) <= @slug_max do
      changeset
    else
      Ash.Changeset.add_error(
        changeset,
        field: :project_name,
        message: "must use lowercase letters, digits, and single hyphens (at most 63 chars)"
      )
    end
  end

  defp slugify(title) do
    base =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 48)
      |> String.trim("-")

    prefix = if base == "", do: "techtree-order", else: base
    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    "#{prefix}-#{suffix}"
  end

  defp attach_materials(changeset) do
    case Ash.Changeset.get_argument(changeset, :material_archive_base64) do
      nil ->
        changeset

      "" ->
        changeset

      encoded when is_binary(encoded) ->
        with {:ok, bytes} <- Base.decode64(encoded),
             {:ok, %{sha256: sha256, size: size}} <- Package.check_intake_archive(bytes) do
          changeset
          |> Ash.Changeset.force_change_attribute(:material_archive, bytes)
          |> Ash.Changeset.force_change_attribute(:material_sha256, sha256)
          |> Ash.Changeset.force_change_attribute(:material_size, size)
        else
          :error ->
            Ash.Changeset.add_error(
              changeset,
              field: :material_archive_base64,
              message: "must be valid base64"
            )

          {:error, message} ->
            Ash.Changeset.add_error(changeset, field: :material_archive_base64, message: message)
        end
    end
  end
end
