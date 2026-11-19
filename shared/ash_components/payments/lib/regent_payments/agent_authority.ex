defmodule RegentPayments.CompletionActor do
  @moduledoc """
  Restricted to finishing one already authorized payment, never an account owner.
  `wallet_address` is the wallet that signed it. While the payment is being
  found, before that wallet is known, `wallet_address` is empty and
  `wallet_addresses` holds every wallet the actor acts with.
  """
  defstruct [
    :id,
    :wallet_address,
    :authentication_origin,
    :acting_agent_id,
    :beneficiary_profile_id,
    :human_account_id,
    :pairing_id,
    :privy_user_id,
    :payment_intent_id,
    :payment_kind,
    :payment_payload_digest,
    :payment_target_id,
    :payment_target_type,
    wallet_addresses: [],
    origin: :page,
    role: :payment_completion
  ]
end

defmodule RegentPayments.AgentAuthority do
  @moduledoc """
  Frozen delegated payment authority. Sites supply an explicitly typed agent
  actor after SIWA verification and canonical beneficiary lookup. This module
  does not authenticate a wallet or turn an agent into its account owner.

  The reserved payload entry is private server data, included in the immutable
  payload digest. Never serialize an intent's entire payload to a client.
  """

  alias Ash.Error.Changes.InvalidChanges
  alias RegentPayments.CanonicalJSON
  alias RegentPayments.WalletPayment

  @key "__regent_payments_agent_authority"
  @fields ~w(acting_agent_id beneficiary_profile_id human_account_id pairing_id privy_user_id wallet_address)
  @authorized [:settlement_pending, :settled, :applied]

  def key, do: @key
  def authorized?(intent), do: intent.status in @authorized

  def from_actor(%{role: :agent} = actor) do
    snapshot = Map.new(@fields, &{&1, Map.get(actor, String.to_existing_atom(&1))})

    if valid?(snapshot) and Map.get(actor, :id) == snapshot["acting_agent_id"],
      do: {:ok, snapshot},
      else: refused()
  end

  def from_actor(%{role: :payment_completion}), do: refused()
  def from_actor(%{role: :person} = actor), do: human_actor(actor)
  def from_actor(%{role: _}), do: refused()
  def from_actor(actor), do: human_actor(actor)

  defp human_actor(%{id: id}) do
    if match?({:ok, _}, Ecto.UUID.cast(id)), do: {:ok, nil}, else: refused()
  end

  defp human_actor(_), do: refused()

  def snapshot(%{payload: payload} = intent) when is_map(payload) do
    case Map.fetch(intent.payload, @key) do
      :error ->
        {:ok, nil}

      {:ok, snapshot} ->
        if valid?(snapshot) and snapshot["acting_agent_id"] == intent.actor_profile_id and
             CanonicalJSON.digest(intent.payload) == intent.payload_digest,
           do: {:ok, snapshot},
           else: refused()
    end
  end

  def snapshot(_), do: refused()

  def lock(snapshot) do
    case RegentAgents.Authority.lock(
           RegentPayments.repo(nil, nil),
           snapshot["pairing_id"],
           snapshot["privy_user_id"],
           snapshot["wallet_address"]
         ) do
      {:ok, _} -> :ok
      {:error, _} -> refused()
    end
  end

  def current(actor, intent) do
    with {:ok, stored} <- snapshot(intent), {:ok, supplied} <- from_actor(actor) do
      cond do
        stored == nil and supplied == nil -> :ok
        stored != nil and stored == supplied -> lock(stored)
        true -> refused()
      end
    end
  end

  def unchanged_authority(actor, intent) do
    with {:ok, stored} <- snapshot(intent), {:ok, supplied} <- from_actor(actor) do
      if stored == supplied, do: :ok, else: refused()
    end
  end

  def preflight(actor, intent) do
    with {:ok, stored} <- snapshot(intent), {:ok, supplied} <- from_actor(actor) do
      case {stored, supplied} do
        {nil, nil} ->
          :ok

        {%{} = same, same} ->
          current_episode(same)

        _ ->
          refused()
      end
    end
  end

  defp current_episode(snapshot) do
    expected_id = snapshot["pairing_id"]
    expected_owner = snapshot["privy_user_id"]

    case RegentAgents.Authority.resolve(RegentPayments.repo(nil, nil), snapshot["wallet_address"]) do
      {:ok, %{id: ^expected_id, privy_user_id: ^expected_owner}} -> :ok
      _ -> refused()
    end
  end

  # Only this completion actor is passed to the offer. It contains the original
  # attribution, never the replacement owner's or replacement episode's values.
  def completion(actor, intent) do
    with true <- authorized?(intent),
         true <- Map.get(actor, :id) == intent.actor_profile_id,
         {:ok, stored} <- snapshot(intent),
         signer when is_binary(signer) <- original_signer(stored, intent, actor) do
      {:ok,
       struct(
         RegentPayments.CompletionActor,
         Map.merge(stored_fields(stored), %{
           id: actor.id,
           wallet_address: signer,
           authentication_origin: Map.get(actor, :authentication_origin),
           origin: Map.get(actor, :origin, :page),
           payment_intent_id: intent.id,
           payment_kind: intent.kind,
           payment_payload_digest: intent.payload_digest,
           payment_target_id: intent.target_id,
           payment_target_type: intent.target_type
         })
       )}
    else
      _ -> refused()
    end
  end

  # An agent's intent is completed only by the agent's own wallet; a person's,
  # by the person whose account links the wallet that paid.
  defp original_signer(%{"wallet_address" => wallet}, _intent, %{wallet_address: actor_wallet})
       when is_binary(actor_wallet),
       do: if(wallet == String.downcase(actor_wallet), do: wallet)

  defp original_signer(nil, %{receipt: %{payer_address: payer}}, actor) when is_binary(payer),
    do: WalletPayment.signer(WalletPayment.wallets(actor), String.downcase(payer))

  defp original_signer(_, _, _), do: nil

  defp stored_fields(nil), do: %{}

  defp stored_fields(stored),
    do: Map.new(stored, fn {key, value} -> {String.to_existing_atom(key), value} end)

  @doc "Whether this completion is bound to this exact stored intent and offer."
  def completion_for?(%RegentPayments.CompletionActor{} = actor, intent, kind) do
    with true <- authorized?(intent),
         true <- actor.payment_intent_id == intent.id,
         true <- actor.payment_kind == kind and intent.kind == kind,
         true <- actor.payment_payload_digest == intent.payload_digest,
         {:ok, expected} <- completion(actor, intent) do
      expected == actor
    else
      _ -> false
    end
  end

  def completion_for?(_, _, _), do: false

  defp valid?(value) when is_map(value) do
    Enum.sort(Map.keys(value)) == @fields and
      Enum.all?(
        ~w(acting_agent_id beneficiary_profile_id pairing_id),
        &match?({:ok, _}, Ecto.UUID.cast(value[&1]))
      ) and
      is_integer(value["human_account_id"]) and value["human_account_id"] > 0 and
      is_binary(value["privy_user_id"]) and value["privy_user_id"] != "" and
      is_binary(value["wallet_address"]) and
      Regex.match?(~r/\A0x[0-9a-f]{40}\z/, value["wallet_address"])
  end

  defp valid?(_), do: false

  def refused,
    do: {:error, InvalidChanges.exception(message: "original active agent pairing required")}
end

defmodule RegentPayments.Checks.CompletionActor do
  @moduledoc false
  use Ash.Policy.SimpleCheck
  def describe(_), do: "actor is restricted to an already authorized payment"
  def match?(%{role: :payment_completion}, _, _), do: true
  def match?(_, _, _), do: false
end

defmodule RegentPayments.Checks.AuthorityOwner do
  @moduledoc false
  use Ash.Policy.FilterCheck
  import Ash.Expr
  alias RegentPayments.AgentAuthority

  def describe(_), do: "actor owns the frozen payment authority"

  def filter(%{role: :agent} = actor, _, opts) do
    case AgentAuthority.from_actor(actor) do
      {:ok, snapshot} ->
        key = AgentAuthority.key()
        owner = snapshot["privy_user_id"]
        beneficiary = snapshot["beneficiary_profile_id"]
        human = Integer.to_string(snapshot["human_account_id"])
        wallet = snapshot["wallet_address"]
        episode = actor.pairing_id
        payload = if opts[:through], do: ref([opts[:through]], :payload), else: ref(:payload)

        expr(
          fragment("? -> ? ->> 'privy_user_id'", ^payload, ^key) == ^owner and
            fragment("? -> ? ->> 'beneficiary_profile_id'", ^payload, ^key) == ^beneficiary and
            fragment("? -> ? ->> 'human_account_id'", ^payload, ^key) == ^human and
            fragment("? -> ? ->> 'wallet_address'", ^payload, ^key) == ^wallet and
            fragment(
              "EXISTS (SELECT 1 FROM regent_agents.paired_agents WHERE id::text = ? AND privy_user_id = ? AND wallet = ?)",
              ^episode,
              ^owner,
              ^wallet
            )
        )

      _ ->
        false
    end
  end

  def filter(
        %{role: :payment_completion, payment_intent_id: id} = actor,
        %{action: %{name: :for_update}},
        _
      ) do
    key = AgentAuthority.key()
    wallets = RegentPayments.WalletPayment.wallets(actor)

    expr(
      id == ^id and status in [:settlement_pending, :settled, :applied] and
        ((is_nil(fragment("? -> ?", payload, ^key)) and
            fragment(
              "EXISTS (SELECT 1 FROM regent_payments.payment_receipts WHERE payment_intent_id = ? AND lower(payer_address) = ANY(?))",
              id,
              ^wallets
            )) or
           fragment("? -> ? ->> 'wallet_address'", payload, ^key) in ^wallets)
    )
  end

  def filter(%{role: :payment_completion, payment_intent_id: id}, _, opts) do
    if opts[:through] == :payment_intent,
      do:
        expr(
          payment_intent_id == ^id and
            payment_intent.status in [:settlement_pending, :settled, :applied]
        ),
      else: false
  end

  def filter(_, _, opts) do
    key = AgentAuthority.key()
    payload = if opts[:through], do: ref([opts[:through]], :payload), else: ref(:payload)
    expr(is_nil(fragment("? -> ?", ^payload, ^key)))
  end
end
