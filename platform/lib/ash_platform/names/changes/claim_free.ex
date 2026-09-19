defmodule AshPlatform.Names.Changes.ClaimFree do
  @moduledoc """
  Records a free claim and spends the free claim that pays for it, inside the
  create's own transaction. The name goes to the wallet whose free claim was
  spent: the sign-in's main wallet first, then its linked wallets in order.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Error.Changes.InvalidArgument
  alias Ash.Error.Changes.InvalidChanges
  alias AshPlatform.Names
  alias AshPlatform.Names.Allowance

  @ens_parent "regent.eth"

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, &claim(&1, Ash.Context.to_opts(context)))
  end

  defp claim(changeset, opts) do
    label = Ash.Changeset.get_argument(changeset, :label)

    with {:ok, false} <- Names.label_claimed?(label, opts),
         {:ok, allowance} <- spend_free_claim(opts),
         {:ok, names} <- names(label, allowance.parent_name) do
      Ash.Changeset.force_change_attributes(
        changeset,
        Map.merge(names, %{
          parent_node: allowance.parent_node,
          parent_name: allowance.parent_name,
          label: label,
          owner_address: allowance.address,
          is_free: true,
          is_in_use: false,
          claim_status: "reserved",
          created_at: DateTime.utc_now()
        })
      )
    else
      {:ok, true} -> Ash.Changeset.add_error(changeset, label_error("is already claimed"))
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  defp spend_free_claim(opts) do
    unspent = Ash.Query.filter(Allowance, free_mints_used < snapshot_total)

    with {:ok, allowances} <- Names.list_my_allowances(Keyword.put(opts, :query, unspent)) do
      case Enum.sort_by(allowances, &wallet_position(&1, opts[:actor])) do
        [] -> {:error, InvalidChanges.exception(message: "no free claims are left")}
        [allowance | _] -> Names.use_free_claim(allowance, opts)
      end
    end
  end

  defp wallet_position(allowance, actor) do
    Enum.find_index(actor.wallet_addresses, &(&1 == String.downcase(allowance.address)))
  end

  defp names(label, parent_name) do
    fqdn = label <> "." <> parent_name
    ens_fqdn = label <> "." <> @ens_parent

    with {:ok, node} <- AgentEns.Verify.namehash(fqdn),
         {:ok, ens_node} <- AgentEns.Verify.namehash(ens_fqdn) do
      {:ok, %{fqdn: fqdn, node: hex(node), ens_fqdn: ens_fqdn, ens_node: hex(ens_node)}}
    else
      {:error, _error} -> {:error, label_error("can’t be used as a name")}
    end
  end

  defp hex(node), do: "0x" <> Base.encode16(node, case: :lower)

  defp label_error(message), do: InvalidArgument.exception(field: :label, message: message)
end
