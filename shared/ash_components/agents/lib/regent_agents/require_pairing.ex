defmodule RegentAgents.RequirePairing do
  @moduledoc "Recheck agent delegation inside the product mutation's transaction."
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, %{actor: %{role: :agent} = actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case RegentAgents.Authority.lock(
             opts[:repo],
             actor.pairing_id,
             actor.privy_user_id,
             actor.wallet_address
           ) do
        {:ok, _} -> changeset
        {:error, _} -> Ash.Changeset.add_error(changeset, "active pairing required")
      end
    end)
  end

  def change(changeset, _opts, _context), do: changeset
end

defmodule RegentAgents.Checks.Paired do
  @moduledoc "Admit a currently paired agent without granting account-owner authority."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "agent has the current pairing episode and owner"

  @impl true
  def match?(%{role: :agent, pairing_id: id, privy_user_id: owner} = actor, _, opts)
      when is_binary(id) and is_binary(owner) do
    wallet = Map.get(actor, Keyword.get(opts, :wallet_field, :wallet_address))
    repo = opts[:repo] || Application.fetch_env!(opts[:repo_app], :repo)

    if is_binary(wallet) do
      case RegentAgents.Authority.resolve(repo, wallet) do
        {:ok, %{id: ^id, privy_user_id: ^owner}} -> true
        _ -> false
      end
    else
      false
    end
  end

  def match?(_, _, _), do: false
end
