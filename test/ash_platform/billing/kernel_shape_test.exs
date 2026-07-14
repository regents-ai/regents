defmodule AshPlatform.Billing.KernelShapeTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Billing
  alias AshPlatform.Billing.{BillingAccount, LedgerEntry, SpendReservation}

  test "the billing domain exposes only the six prepaid kernel interfaces" do
    interfaces =
      Billing
      |> Ash.Domain.Info.resource_references()
      |> Enum.flat_map(& &1.definitions)
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert interfaces ==
             Enum.sort([
               :consume_reserved_spend,
               :credit_summary,
               :expire_reservation,
               :record_provider_funding,
               :release_reservation,
               :reserve_spend
             ])
  end

  test "kernel resources have no generic public mutations" do
    for resource <- [BillingAccount, LedgerEntry, SpendReservation],
        action <- Ash.Resource.Info.actions(resource),
        action.type in [:create, :update, :destroy] do
      refute action.name in [:create, :update, :destroy]
    end
  end

  test "the database identities pin the three idempotency boundaries" do
    assert Enum.any?(
             Ash.Resource.Info.identities(BillingAccount),
             &(&1.name == :one_per_human_account)
           )

    assert Enum.any?(
             Ash.Resource.Info.identities(LedgerEntry),
             &(&1.name == :globally_unique_idempotency_key)
           )

    assert Enum.any?(
             Ash.Resource.Info.identities(SpendReservation),
             &(&1.name == :globally_unique_operation_key)
           )
  end

  test "reservation authorization keeps its explicit atomic credit guard" do
    action = Ash.Resource.Info.action(BillingAccount, :increase_reserved)

    assert Enum.any?(
             action.changes,
             &match?(
               %Ash.Resource.Validation{
                 module: AshPlatform.Billing.Validations.HasAvailableCredit
               },
               &1
             )
           )
  end

  test "money arguments accept only positive integer cents" do
    for {resource, action_name, params} <- [
          {BillingAccount, :record_provider_funding,
           %{human_account_id: 1, provider_reference: "provider-test"}},
          {BillingAccount, :reserve_spend,
           %{human_account_id: 1, operation_key: "operation-test"}},
          {BillingAccount, :consume_reserved_spend,
           %{
             human_account_id: 1,
             reservation_id: Ash.UUID.generate(),
             settlement_key: "settlement-test"
           }}
        ],
        amount <- [0, -1, 1.5] do
      input =
        Ash.ActionInput.for_action(
          resource,
          action_name,
          Map.put(params, :amount_cents, amount),
          actor: %AshPlatform.Actors.Human{human_account_id: 1}
        )

      refute input.valid?
    end
  end
end
