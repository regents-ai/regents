defmodule AshPlatform.Autolaunch.SubjectWalletOperationsTest do
  @moduledoc """
  The locked lifecycle: who may dispatch, which hash may bind, what a receipt is
  allowed to settle, and what a concurrent logout or a second socket may do to
  any of it.
  """

  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Autolaunch
  alias AshPlatform.SubjectWalletFixture, as: Fixture
  alias AshPlatform.TestAutolaunchSubjectWalletChainClient, as: ChainClient

  @approval_hash "0x" <> String.duplicate("a1", 32)
  @action_hash "0x" <> String.duplicate("b2", 32)
  @other_hash "0x" <> String.duplicate("c3", 32)

  setup do
    Fixture.install()
    Fixture.actor()
  end

  describe "EXACTLY_ONE_SENDABLE_STEP: a step is claimed once and its hash is durable before the next" do
    test "the approval settles, the action becomes sendable, and the whole action confirms",
         context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})
      assert operation.step == :approval

      assert {:ok, %{operation: claimed}} = claim(context, operation)
      assert claimed.state == :dispatched

      assert {:ok, %{operation: bound}} = bind(context, operation, :approval, @approval_hash)
      assert bound.state == :submitted
      assert bound.approval_transaction_hash == @approval_hash

      ChainClient.put(%{outcomes: %{approval: %{outcome: :confirmed}}})
      assert {:ok, %{operation: advanced}} = verify(context, operation)
      assert advanced.step == :action
      assert advanced.state == :prepared
      assert advanced.approval_transaction_hash == @approval_hash

      assert {:ok, _claimed} = claim(context, operation)
      assert {:ok, %{operation: sent}} = bind(context, operation, :action, @action_hash)
      assert sent.state == :submitted

      ChainClient.put(%{outcomes: %{action: %{outcome: :confirmed, result: %{"staked" => "10"}}}})
      assert {:ok, %{operation: confirmed}} = verify(context, operation)

      assert confirmed.state == :confirmed
      assert confirmed.result == %{"staked" => "10"}
      assert confirmed.terminal_at
    end

    test "a hash reported for a step the row is not on cannot bind", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, operation)

      assert {:error, error} = bind(context, operation, :action, @action_hash)
      assert Fixture.refusal(error) == :submitted_step_mismatch
    end

    test "a pending read writes nothing, so the same hash stays readable", context do
      {:ok, operation} = submitted_approval(context)

      ChainClient.put(%{outcomes: %{approval: %{outcome: :pending}}})
      assert {:ok, %{operation: unchanged}} = verify(context, operation)

      assert unchanged.state == :submitted
      assert unchanged.step == :approval
      assert unchanged.approval_transaction_hash == @approval_hash
    end

    test "no provider read ever happens inside the lease transaction", context do
      {:ok, operation} = submitted_approval(context)

      ChainClient.put(%{outcomes: %{approval: %{outcome: :confirmed}}})
      assert {:ok, _advanced} = verify(context, operation)

      refute ChainClient.state().read_in_transaction?
    end
  end

  describe "ONE_WINNER_PER_DISPATCH: the database decides every race" do
    test "two sockets claiming one dispatch produce exactly one winner", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})

      results = race(fn -> claim(context, operation) end, 2)

      assert Enum.count(results, &match?({:ok, %{operation: %{state: :dispatched}}}, &1)) == 1
      assert Enum.count(results, &match?({:error, _refused}, &1)) == 1
    end

    test "a bound hash never becomes resendable, whichever call lands first", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, operation)

      [bound, released] =
        race_each([
          fn -> bind(context, operation, :approval, @approval_hash) end,
          fn -> release(context, operation) end
        ])

      # Whichever won, the row is never both released and carrying a hash.
      assert {:ok, %{operation: current}} = open(context)

      case current.approval_transaction_hash do
        nil ->
          assert current.state == :prepared
          assert match?({:error, _refused}, bound)

        @approval_hash ->
          assert current.state == :submitted
          assert match?({:error, _refused}, released)
      end
    end

    test "an exact replay is a no-op while a different hash conflicts", context do
      {:ok, operation} = submitted_approval(context)

      assert {:ok, %{operation: replayed}} = bind(context, operation, :approval, @approval_hash)
      assert replayed.approval_transaction_hash == @approval_hash

      assert {:error, error} = bind(context, operation, :approval, @other_hash)
      assert Fixture.refusal(error) == :submitted_hash_conflict
    end

    test "the same hash cannot be reused by another operation in the same phase", context do
      {:ok, first} = submitted_approval(context)
      assert {:ok, %{operation: %{state: :submitted}}} = open(context)

      # Ending the first operation frees the account's slot for this subject but
      # never frees the hash it already bound.
      assert {:ok, _closed} = start_new(context, first)
      {:ok, second} = review(context, :stake, %{"amount" => "11"})
      assert {:ok, _claimed} = claim(context, second)

      assert {:error, _conflict} = bind(context, second, :approval, @approval_hash)
    end

    test "an approval hash offered as an action hash cannot settle either", context do
      {:ok, operation} = review(context, :unstake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, operation)
      assert {:ok, _bound} = bind(context, operation, :action, @action_hash)

      # The unique action-hash identity refuses the reuse outright, and even if it
      # bound, verification matches this phase's exact target and calldata.
      {:ok, other} = other_subject_operation(context)
      assert {:ok, _claimed} = claim(context, other)
      assert {:error, _conflict} = bind(context, other, :action, @action_hash)
    end

    test "terminal settlement races return the row's own winning outcome", context do
      {:ok, operation} = submitted_action(context)

      ChainClient.put(%{outcomes: %{action: %{outcome: :confirmed}}})
      results = race(fn -> verify(context, operation) end, 2)

      assert Enum.all?(results, &match?({:ok, %{operation: %{state: :confirmed}}}, &1))
      assert {:ok, %{operation: nil}} = open(context)
    end

    test "a read that answered about a row another socket has moved is dropped", context do
      {:ok, operation} = submitted_action(context)

      ChainClient.put(%{
        outcomes: %{action: %{outcome: :confirmed}},
        raced: fn -> start_new(context, operation) end
      })

      assert {:ok, %{operation: settled}} = verify(context, operation)

      # The account ended it between the read and the lock, so the read's own
      # answer is not applied to a row it no longer described.
      assert settled.state == :submission_unknown
    end
  end

  describe "ONE_OPEN_PER_ACCOUNT_AND_SUBJECT: subjects are independent of one another" do
    test "an undispatched review is replaced while a claimed one holds the slot", context do
      {:ok, first} = review(context, :stake, %{"amount" => "10"})
      {:ok, second} = review(context, :stake, %{"amount" => "11"})
      refute first.action_id == second.action_id

      assert {:ok, _claimed} = claim(context, second)

      assert {:error, error} =
               Autolaunch.prepare_subject_wallet_action(
                 context[:subject].subject_id,
                 Fixture.wallet(),
                 :stake,
                 %{"amount" => "12"},
                 context[:opts]
               )

      assert Fixture.refusal(error) == :action_in_flight
    end

    test "a different subject stays completely independent", context do
      {:ok, held} = review(context, :stake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, held)

      assert {:ok, other} = other_subject_operation(context)
      assert other.state == :prepared
    end
  end

  describe "STALE_LOGOUT_WRITES_NOTHING: no durable write outlives its own authority" do
    test "a revoked lease refuses the very next durable write", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})
      assert SessionAuthority.revoke(claim_of(context))

      assert {:error, error} = claim(context, operation)
      assert Fixture.refusal(error) == :session_unavailable

      assert {:error, refused} =
               Autolaunch.prepare_subject_wallet_action(
                 context[:subject].subject_id,
                 Fixture.wallet(),
                 :stake,
                 %{"amount" => "1"},
                 context[:opts]
               )

      assert Fixture.refusal(refused) == :session_unavailable
    end

    test "a write that commits before a logout keeps every fact it wrote", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})

      assert {:ok, %{operation: claimed}} = claim(context, operation)
      assert claimed.state == :dispatched

      assert SessionAuthority.revoke(claim_of(context))

      # The committed claim survives; the account simply cannot write again.
      assert {:ok, current} = row(context, operation)
      assert current.state == :dispatched
    end
  end

  describe "REVIEW_IS_BOUND_TO_ITS_SIGNER: a wallet switch cannot retarget anything" do
    test "another wallet cannot dispatch a review prepared for this signer", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})

      assert {:error, error} =
               Autolaunch.claim_subject_wallet_dispatch(
                 context[:subject].subject_id,
                 operation.action_id,
                 "0x9999999999999999999999999999999999999999",
                 context[:opts]
               )

      assert Fixture.refusal(error) == :wrong_signer
      assert {:ok, %{state: :prepared}} = row(context, operation)
    end

    test "an in-flight action stays bound to the wallet it was reviewed for", context do
      {:ok, operation} = submitted_action(context)

      assert {:error, _refused} =
               Autolaunch.claim_subject_wallet_dispatch(
                 context[:subject].subject_id,
                 operation.action_id,
                 "0x9999999999999999999999999999999999999999",
                 context[:opts]
               )

      assert {:ok, %{state: :submitted, signer: signer}} = row(context, operation)
      assert signer == Fixture.wallet()
    end
  end

  describe "TERMINAL_STAYS_TERMINAL: nothing reopens a finished action" do
    test "a late hash attaches without reopening a terminal action", context do
      {:ok, operation} = submitted_action(context)

      ChainClient.put(%{outcomes: %{action: %{outcome: :reverted}}})
      assert {:ok, %{operation: reverted}} = verify(context, operation)
      assert reverted.state == :reverted

      # The same hash replays as an authority no-op rather than an error.
      assert {:ok, %{operation: replayed}} = bind(context, operation, :action, @action_hash)
      assert replayed.state == :reverted
      assert replayed.terminal_at == reverted.terminal_at
    end

    test "an explicit wallet rejection ends a claimed step that never sent", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, operation)

      assert {:ok, %{operation: closed}} =
               Autolaunch.close_subject_wallet_not_sent(
                 context[:subject].subject_id,
                 operation.action_id,
                 context[:opts]
               )

      assert closed.state == :not_sent
      assert closed.terminal_at
      assert is_nil(closed.approval_transaction_hash)
    end

    test "a review nobody dispatched is withdrawn, and a claimed one is not", context do
      {:ok, operation} = review(context, :stake, %{"amount" => "10"})

      assert {:ok, %{operation: cancelled}} =
               Autolaunch.cancel_subject_wallet_review(
                 context[:subject].subject_id,
                 operation.action_id,
                 context[:opts]
               )

      assert cancelled.state == :cancelled

      {:ok, claimed_operation} = review(context, :stake, %{"amount" => "10"})
      assert {:ok, _claimed} = claim(context, claimed_operation)

      assert {:error, _refused} =
               Autolaunch.cancel_subject_wallet_review(
                 context[:subject].subject_id,
                 claimed_operation.action_id,
                 context[:opts]
               )
    end
  end

  # Helpers

  defp review(context, kind, params) do
    {:ok, %{operation: operation}} =
      Autolaunch.prepare_subject_wallet_action(
        context[:subject].subject_id,
        Fixture.wallet(),
        kind,
        params,
        context[:opts]
      )

    {:ok, operation}
  end

  defp claim(context, operation) do
    Autolaunch.claim_subject_wallet_dispatch(
      operation.subject_id,
      operation.action_id,
      Fixture.wallet(),
      context[:opts]
    )
  end

  defp bind(context, operation, step, hash) do
    Autolaunch.bind_subject_wallet_hash(
      operation.subject_id,
      operation.action_id,
      step,
      hash,
      context[:opts]
    )
  end

  defp verify(context, operation) do
    Autolaunch.verify_subject_wallet_step(
      operation.subject_id,
      operation.action_id,
      context[:opts]
    )
  end

  defp release(context, operation) do
    Autolaunch.release_unstarted_subject_wallet_dispatch(
      operation.subject_id,
      operation.action_id,
      context[:opts]
    )
  end

  defp start_new(context, operation) do
    Autolaunch.start_new_subject_wallet_action(
      operation.subject_id,
      operation.action_id,
      context[:opts]
    )
  end

  defp open(context),
    do: Autolaunch.open_subject_wallet_operation(context[:subject].subject_id, context[:opts])

  defp row(context, operation) do
    with {:ok, %{operation: current}} <- open(context) do
      if current && current.action_id == operation.action_id,
        do: {:ok, current},
        else: terminal_row(context, operation)
    end
  end

  defp terminal_row(context, operation) do
    AshPlatform.Autolaunch.SubjectWalletOperations.fetch(
      context[:account].id,
      context[:subject].subject_id,
      operation.action_id,
      false
    )
  end

  # An action with no approval step, already sent.
  defp submitted_action(context) do
    {:ok, operation} = review(context, :unstake, %{"amount" => "10"})
    {:ok, _claimed} = claim(context, operation)
    {:ok, _bound} = bind(context, operation, :action, @action_hash)
    {:ok, operation}
  end

  defp submitted_approval(context) do
    {:ok, operation} = review(context, :stake, %{"amount" => "10"})
    {:ok, _claimed} = claim(context, operation)
    {:ok, _bound} = bind(context, operation, :approval, @approval_hash)
    {:ok, operation}
  end

  defp other_subject_operation(context) do
    other = Fixture.subject!("subject:wallet:other:#{Elixir.System.unique_integer([:positive])}")

    with {:ok, %{operation: operation}} <-
           Autolaunch.prepare_subject_wallet_action(
             other.subject_id,
             Fixture.wallet(),
             :unstake,
             %{"amount" => "5"},
             context[:opts]
           ),
         do: {:ok, operation}
  end

  defp claim_of(context) do
    %{
      lineage: context[:opts][:context][:session_lease][:lineage],
      generation: 0
    }
  end

  # Separate database connections and a barrier, so the race is a real one rather
  # than a scheduling accident.
  defp race(work, count), do: race_each(List.duplicate(work, count))

  defp race_each(works) do
    parent = self()
    barrier = :erlang.unique_integer()

    works
    |> Enum.map(fn work ->
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(AshPlatform.Repo, parent, self())
        send(parent, {:ready, barrier, self()})

        receive do
          {:go, ^barrier} -> work.()
        end
      end)
    end)
    |> started(barrier)
    |> Enum.map(&Task.await(&1, 15_000))
  end

  defp started(tasks, barrier) do
    for _task <- tasks do
      receive do
        {:ready, ^barrier, pid} -> send(pid, {:go, barrier})
      end
    end

    tasks
  end
end
