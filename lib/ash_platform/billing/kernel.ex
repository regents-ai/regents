defmodule AshPlatform.Billing.Kernel do
  @moduledoc false

  alias AshPlatform.Actors.System
  alias AshPlatform.Billing.{BillingAccount, LedgerEntry, SpendReservation}

  def record_provider_funding(%{arguments: args}, _actor) do
    key = funding_key(args.provider_reference)

    case ledger_entry(key) do
      {:ok, nil} -> create_funding(args, key)
      {:ok, entry} -> verify_funding_retry(entry, args)
      {:error, error} -> {:error, error}
    end
  end

  def credit_summary(%{arguments: args}, _actor) do
    case account_by_human(args.human_account_id) do
      {:ok, nil} -> {:ok, empty_summary()}
      {:ok, account} -> {:ok, summary(account)}
      {:error, error} -> {:error, error}
    end
  end

  def reserve_spend(%{arguments: args}, _actor) do
    case reservation_by_operation(args.operation_key) do
      {:ok, nil} -> create_reservation(args)
      {:ok, reservation} -> verify_reservation_retry(reservation, args)
      {:error, error} -> {:error, error}
    end
  end

  def consume(%{arguments: args}, _actor) do
    key = settlement_key(args.settlement_key)

    case ledger_entry(key) do
      {:ok, nil} -> create_consumption(args, key)
      {:ok, entry} -> verify_consumption_retry(entry, args)
      {:error, error} -> {:error, error}
    end
  end

  def close(%{arguments: args}, _actor, status) when status in [:released, :expired] do
    with {:ok, reservation} when not is_nil(reservation) <- reservation_by_id(args.reservation_id),
         {:ok, account} <- owned_account(reservation.billing_account_id, args.human_account_id) do
      close_loaded_reservation(reservation, account, status)
    else
      {:ok, nil} -> {:error, "reservation was not found"}
      {:error, error} -> {:error, error}
    end
  end

  defp create_funding(args, key) do
    result =
      Ash.DataLayer.transaction(BillingAccount, fn ->
        with {:ok, account} <- open_account(args.human_account_id),
             {:ok, entry} <-
               append_ledger(%{
                 billing_account_id: account.id,
                 kind: :provider_funding,
                 idempotency_key: key,
                 provider_reference: args.provider_reference,
                 reservation_id: nil,
                 amount_cents: args.amount_cents
               }),
             {:ok, _account} <- update_account(account, :add_funding, args.amount_cents) do
          entry
        else
          {:error, error} -> Ash.DataLayer.rollback(BillingAccount, error)
        end
      end)

    converge_ledger_retry(result, key, &verify_funding_retry(&1, args))
  end

  defp create_reservation(args) do
    case account_by_human(args.human_account_id) do
      {:ok, account} when not is_nil(account) ->
        result =
          Ash.DataLayer.transaction(BillingAccount, fn ->
            with {:ok, reservation} <-
                   create_reservation_record(account.id, args.operation_key, args.amount_cents),
                 {:ok, _account} <-
                   update_account(account, :increase_reserved, args.amount_cents) do
              reservation
            else
              {:error, error} -> Ash.DataLayer.rollback(BillingAccount, error)
            end
          end)

        converge_reservation_retry(result, args)

      {:ok, nil} ->
        {:error, "billing account has no funded credit"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_consumption(args, key) do
    with {:ok, reservation} when not is_nil(reservation) <- reservation_by_id(args.reservation_id),
         {:ok, account} <- owned_account(reservation.billing_account_id, args.human_account_id) do
      result =
        Ash.DataLayer.transaction(BillingAccount, fn ->
          with {:ok, entry} <-
                 append_ledger(%{
                   billing_account_id: account.id,
                   kind: :reservation_consumption,
                   idempotency_key: key,
                   provider_reference: nil,
                   reservation_id: reservation.id,
                   amount_cents: args.amount_cents
                 }),
               {:ok, _reservation} <- consume_reservation(reservation, args.amount_cents),
               {:ok, _account} <-
                 update_account(account, :settle_reserved, args.amount_cents),
               {:ok, current} <- reservation_by_id(reservation.id) do
            %{entry: entry, reservation: current}
          else
            {:error, error} -> Ash.DataLayer.rollback(BillingAccount, error)
          end
        end)

      case result do
        {:ok, %{reservation: current}} -> {:ok, current}
        {:error, error} -> converge_consumption_retry(error, key, args)
      end
    else
      {:ok, nil} -> {:error, "reservation was not found"}
      {:error, error} -> {:error, error}
    end
  end

  defp close_loaded_reservation(%{status: status} = reservation, _account, status),
    do: {:ok, reservation}

  defp close_loaded_reservation(%{status: status}, _account, requested)
       when status in [:consumed, :released, :expired],
       do: {:error, "#{status} reservation cannot become #{requested}"}

  defp close_loaded_reservation(reservation, account, status) do
    remaining = reservation.amount_cents - reservation.consumed_cents

    result =
      Ash.DataLayer.transaction(BillingAccount, fn ->
        with true <- remaining > 0,
             {:ok, _reservation} <- close_reservation(reservation, status),
             {:ok, _account} <- update_account(account, :return_reserved, remaining),
             {:ok, current} <- reservation_by_id(reservation.id) do
          current
        else
          false -> Ash.DataLayer.rollback(BillingAccount, "reservation has no remaining credit")
          {:error, error} -> Ash.DataLayer.rollback(BillingAccount, error)
        end
      end)

    case result do
      {:ok, current} -> {:ok, current}
      {:error, error} -> converge_close_retry(error, reservation.id, status)
    end
  end

  defp verify_funding_retry(entry, args) do
    with true <- entry.kind == :provider_funding,
         true <- entry.provider_reference == args.provider_reference,
         true <- entry.amount_cents == args.amount_cents,
         {:ok, account} <- account_by_id(entry.billing_account_id),
         true <- account.human_account_id == args.human_account_id do
      {:ok, entry}
    else
      _ -> {:error, "provider reference already records different funding"}
    end
  end

  defp verify_reservation_retry(reservation, args) do
    with true <- reservation.amount_cents == args.amount_cents,
         {:ok, account} <- account_by_id(reservation.billing_account_id),
         true <- account.human_account_id == args.human_account_id do
      {:ok, reservation}
    else
      _ -> {:error, "operation key already records a different reservation"}
    end
  end

  defp verify_consumption_retry(entry, args) do
    with true <- entry.kind == :reservation_consumption,
         true <- entry.reservation_id == args.reservation_id,
         true <- entry.amount_cents == args.amount_cents,
         {:ok, account} <- account_by_id(entry.billing_account_id),
         true <- account.human_account_id == args.human_account_id,
         {:ok, reservation} when not is_nil(reservation) <- reservation_by_id(args.reservation_id) do
      {:ok, reservation}
    else
      _ -> {:error, "settlement key already records different usage"}
    end
  end

  defp converge_ledger_retry({:ok, entry}, _key, _verify), do: {:ok, entry}

  defp converge_ledger_retry({:error, original}, key, verify) do
    case ledger_entry(key) do
      {:ok, nil} -> {:error, original}
      {:ok, entry} -> verify.(entry)
      {:error, _} -> {:error, original}
    end
  end

  defp converge_reservation_retry({:ok, reservation}, _args), do: {:ok, reservation}

  defp converge_reservation_retry({:error, original}, args) do
    case reservation_by_operation(args.operation_key) do
      {:ok, nil} -> {:error, original}
      {:ok, reservation} -> verify_reservation_retry(reservation, args)
      {:error, _} -> {:error, original}
    end
  end

  defp converge_consumption_retry(original, key, args) do
    case ledger_entry(key) do
      {:ok, nil} -> {:error, original}
      {:ok, entry} -> verify_consumption_retry(entry, args)
      {:error, _} -> {:error, original}
    end
  end

  defp converge_close_retry(original, reservation_id, status) do
    case reservation_by_id(reservation_id) do
      {:ok, %{status: ^status} = reservation} ->
        {:ok, reservation}

      {:ok, %{status: other}} when other in [:consumed, :released, :expired] ->
        {:error, "#{other} reservation cannot become #{status}"}

      _ ->
        {:error, original}
    end
  end

  defp open_account(human_account_id) do
    BillingAccount
    |> Ash.Changeset.for_create(:open, %{human_account_id: human_account_id}, actor: system())
    |> Ash.create()
  end

  defp account_by_human(human_account_id) do
    BillingAccount
    |> Ash.Query.for_read(:by_human_account, %{human_account_id: human_account_id},
      actor: system()
    )
    |> Ash.read_one()
  end

  defp account_by_id(id) do
    BillingAccount
    |> Ash.Query.for_read(:by_id, %{id: id}, actor: system())
    |> Ash.read_one()
    |> require_record("billing account was not found")
  end

  defp owned_account(id, human_account_id) do
    with {:ok, account} <- account_by_id(id),
         true <- account.human_account_id == human_account_id do
      {:ok, account}
    else
      false -> {:error, "billing account is not owned by the actor"}
      {:error, error} -> {:error, error}
    end
  end

  defp update_account(account, action, amount_cents) do
    account
    |> Ash.Changeset.for_update(action, %{amount_cents: amount_cents}, actor: system())
    |> Ash.update()
  end

  defp append_ledger(attrs) do
    LedgerEntry
    |> Ash.Changeset.for_create(:append, attrs, actor: system())
    |> Ash.create()
  end

  defp ledger_entry(idempotency_key) do
    LedgerEntry
    |> Ash.Query.for_read(:by_idempotency_key, %{idempotency_key: idempotency_key},
      actor: system()
    )
    |> Ash.read_one()
  end

  defp create_reservation_record(account_id, operation_key, amount_cents) do
    SpendReservation
    |> Ash.Changeset.for_create(
      :reserve,
      %{billing_account_id: account_id, operation_key: operation_key, amount_cents: amount_cents},
      actor: system()
    )
    |> Ash.create()
  end

  defp reservation_by_operation(operation_key) do
    SpendReservation
    |> Ash.Query.for_read(:by_operation_key, %{operation_key: operation_key}, actor: system())
    |> Ash.read_one()
  end

  defp reservation_by_id(id) do
    SpendReservation
    |> Ash.Query.for_read(:by_id, %{id: id}, actor: system())
    |> Ash.read_one()
  end

  defp consume_reservation(reservation, amount_cents) do
    reservation
    |> Ash.Changeset.for_update(:consume, %{amount_cents: amount_cents}, actor: system())
    |> Ash.update()
  end

  defp close_reservation(reservation, status) do
    reservation
    |> Ash.Changeset.for_update(:close, %{status: status}, actor: system())
    |> Ash.update()
  end

  defp require_record({:ok, nil}, message), do: {:error, message}
  defp require_record(result, _message), do: result

  defp summary(account) do
    %{
      currency: account.currency,
      funded_cents: account.funded_cents,
      reserved_cents: account.reserved_cents,
      consumed_cents: account.consumed_cents,
      available_cents: account.funded_cents - account.reserved_cents - account.consumed_cents
    }
  end

  defp empty_summary do
    %{currency: :usd, funded_cents: 0, reserved_cents: 0, consumed_cents: 0, available_cents: 0}
  end

  defp funding_key(reference), do: "funding:" <> reference
  defp settlement_key(key), do: "settlement:" <> key
  defp system, do: %System{}
end
