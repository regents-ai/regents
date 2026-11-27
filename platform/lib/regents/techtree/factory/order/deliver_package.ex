defmodule Regents.Techtree.Factory.Order.DeliverPackage do
  @moduledoc """
  Atomically verifies an uploaded `uplift-package/1` or `uplift-package/2`
  archive, delivers the resulting `Regents.Techtree.Projects.Project` row to
  the ordering customer inside the same database transaction, and links it onto
  the `Regents.Techtree.Factory.Order`.
  """

  use Ash.Resource.Change

  alias Regents.Account.Actors.System, as: SystemActor
  alias Regents.Techtree.Projects

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      order = changeset.data
      bytes = Ash.Changeset.get_argument(changeset, :package_bytes)
      expected_sha = Ash.Changeset.get_argument(changeset, :expected_sha256)
      job_id = Ash.Changeset.get_argument(changeset, :external_job_id)

      with :ok <- require_owner(order),
           {:ok, project} <- deliver_project(order, bytes, expected_sha) do
        changeset
        |> Ash.Changeset.force_change_attribute(:delivered_at, DateTime.utc_now())
        |> Ash.Changeset.force_change_attribute(:external_job_id, job_id)
        |> Ash.Changeset.force_change_attribute(:delivered_project_id, project.id)
      else
        {:error, %Ash.Error.Invalid{errors: errors}} ->
          Ash.Changeset.add_error(changeset,
            field: :package_bytes,
            message: leaf_error_message(errors)
          )

        {:error, message} when is_binary(message) ->
          Ash.Changeset.add_error(changeset, field: :package_bytes, message: message)

        {:error, _other} ->
          Ash.Changeset.add_error(changeset,
            field: :package_bytes,
            message: "Package could not be verified and saved."
          )
      end
    end)
  end

  defp leaf_error_message(errors) when is_list(errors) do
    errors
    |> Enum.flat_map(fn
      %{errors: nested} when is_list(nested) -> [leaf_error_message(nested)]
      %{message: msg} when is_binary(msg) and msg != "" -> [msg]
      _other -> []
    end)
    |> Enum.uniq()
    |> case do
      [] -> "Package failed validation."
      messages -> Enum.join(messages, "; ")
    end
  end

  defp leaf_error_message(_other), do: "Package failed validation."

  defp require_owner(%{human_account_id: id}) when is_integer(id), do: :ok

  defp require_owner(_order),
    do: {:error, "This order has no linked human_account_id to deliver a project to."}

  defp deliver_project(order, bytes, expected_sha) do
    customer_name =
      order.customer_contact_name ||
        order.customer_company ||
        order.agent_wallet ||
        "Techtree Customer"

    Projects.deliver_project(
      %{
        human_account_id: order.human_account_id,
        customer_name: String.slice(customer_name, 0, 200),
        delivered_by_name: "Uplift Factory",
        package_bytes: bytes,
        expected_sha256: expected_sha
      },
      actor: %SystemActor{}
    )
  end
end
