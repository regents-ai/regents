defmodule Regents.Patchbay.Limits.LimitWrites do
  @moduledoc """
  Holds each writer to the `:allowance` named in `Regents.Limits`, as in
  ash-template, and, with `:address_allowance`, the client address the write
  came from as well, which the caller passes as `context: %{client_key: key}`
  (`RegentsWeb.Patchbay.ClientAddress.visitor_key/1`). A write counts when it is
  saved, never while it is typed. The
  count runs before the statement, so an update that uses it sets
  `require_atomic? false`. A writer past the allowance is refused with
  `Regents.Patchbay.Limits.Spent`, on `:field`, in the words of `:message`.
  """

  use Ash.Resource.Change

  alias Regents.Limits
  alias Regents.Patchbay.Limits.Spent

  @impl true
  def init(opts) do
    if Enum.all?([:allowance, :field, :message], &Keyword.has_key?(opts, &1)),
      do: {:ok, opts},
      else: {:error, "LimitWrites takes :allowance, :field and :message"}
  end

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if admitted?(changeset, opts, actor),
        do: changeset,
        else:
          Ash.Changeset.add_error(
            changeset,
            Spent.exception(field: opts[:field], message: opts[:message])
          )
    end)
  end

  defp admitted?(changeset, opts, actor) do
    Limits.spend(allowance_name(opts[:allowance]), writer(actor)) == :ok and
      address_admitted?(changeset, opts[:address_allowance])
  end

  defp address_admitted?(_changeset, nil), do: true

  defp address_admitted?(%{context: %{client_key: key}}, allowance),
    do: Limits.spend(allowance_name(allowance), key) == :ok

  @allowances %{
    message: :patchbay_message,
    message_address: :patchbay_message_address,
    search_address: :patchbay_search_address,
    wallet_read: :patchbay_wallet_read
  }

  defp allowance_name(name) when is_atom(name), do: Map.get(@allowances, name, name)

  defp writer(%{id: id}) when not is_nil(id), do: "actor:" <> to_string(id)
  defp writer(%{beneficiary_profile_id: id}) when is_binary(id), do: "profile:" <> id
  defp writer(%{human_account_id: id}) when not is_nil(id), do: "human:" <> to_string(id)
  defp writer(_other), do: "anonymous"
end
