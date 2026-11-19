defmodule RegentAgents.Authority do
  @moduledoc """
  Current pairing evidence for product authorization. A site supplies its Repo,
  which must share the pairing database. Mutation callers use `lock/4` inside
  the transaction that commits their domain effect. The row lock serializes
  authorization with revocation; it never changes an agent into a person.
  """

  @doc "Read the current owner and episode for a SIWA-verified wallet."
  def resolve(repo, wallet) when is_binary(wallet) do
    query(repo, "wallet = $1", [String.downcase(wallet)], "")
  end

  @doc "Recheck an exact episode and owner, retaining the lock until the effect commits."
  def lock(repo, pairing_id, privy_user_id, wallet) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "pairing lock requires the product transaction")

    case Ecto.UUID.dump(pairing_id) do
      {:ok, id} ->
        query(
          repo,
          "id = $1 AND privy_user_id = $2 AND wallet = $3",
          [id, privy_user_id, String.downcase(wallet)],
          " FOR UPDATE"
        )

      :error ->
        {:error, :not_paired}
    end
  end

  @doc "Lock the current episode when an authenticated account owner changes a grant."
  def lock_current(repo, privy_user_id, wallet) do
    unless repo.in_transaction?(),
      do: raise(ArgumentError, "pairing lock requires the product transaction")

    query(
      repo,
      "privy_user_id = $1 AND wallet = $2",
      [privy_user_id, String.downcase(wallet)],
      " FOR UPDATE"
    )
  end

  @doc "Recheck a queued action's recorded episode immediately before starting work."
  def active_episode?(repo, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.dump(id),
         {:ok, _} <- query(repo, "id = $1", [id], "") do
      true
    else
      _ -> false
    end
  end

  defp query(repo, condition, params, lock) do
    sql =
      "SELECT id, privy_user_id, wallet FROM regent_agents.paired_agents WHERE " <>
        condition <> lock

    case Ecto.Adapters.SQL.query(repo, sql, params) do
      {:ok, %{rows: [[id, owner, wallet]]}} ->
        {:ok, %{id: Ecto.UUID.load!(id), privy_user_id: owner, wallet: wallet}}

      {:ok, %{rows: []}} ->
        {:error, :not_paired}

      {:error, error} ->
        {:error, error}
    end
  end
end
