defmodule AshPlatform.Autolaunch.SubjectTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.SubjectAction
  alias AshPlatform.Autolaunch.SubjectAction.Changes.ResolveSubject

  @unsafe_subject_ids [
    slash: "subject/slash",
    query: "subject?query",
    fragment: "subject#fragment",
    percent: "subject%encoded",
    space: "subject identity",
    unicode: "subject-é",
    too_long: String.duplicate("a", 129)
  ]

  test "anonymous reads use the canonical identity for tokens, actions, and settlements" do
    subject = subject!()

    auction =
      Autolaunch.import_auction!(
        "Subject token auction",
        nil,
        false,
        :graduated,
        DateTime.utc_now(),
        actor: %System{}
      )

    token =
      Autolaunch.import_subject_token!(
        auction.id,
        subject.subject_id,
        "Subject Token",
        "SUBJ",
        "Linked by canonical subject identity.",
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    older =
      Autolaunch.import_subject_action!(
        subject.subject_id,
        "settle_buyback",
        "0x1111111111111111111111111111111111111111",
        8453,
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "2000000",
        "confirmed",
        100,
        actor: %System{}
      )

    Process.sleep(2)

    other_action =
      Autolaunch.import_subject_action!(
        subject.subject_id,
        "stake",
        nil,
        8453,
        nil,
        "1",
        "confirmed",
        nil,
        actor: %System{}
      )

    Process.sleep(2)

    newer =
      Autolaunch.import_subject_action!(
        subject.subject_id,
        "settle_buyback",
        "0x2222222222222222222222222222222222222222",
        8453,
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "3000000",
        "pending",
        101,
        actor: %System{}
      )

    assert {:ok, subjects} = Autolaunch.list_subjects()
    assert subject.subject_id in Enum.map(subjects, & &1.subject_id)

    assert {:ok, public} = Autolaunch.get_public_subject(subject.subject_id)
    assert public.subject_id == "subject:resource"
    assert public.protocol_fee_usdc_total_raw == "12000000"
    assert public.regent_emission_total_raw == "3400000000000000000"
    assert public.pending_buyback_usdc_raw == "5000000"

    assert {:ok, [related]} = Autolaunch.list_subject_tokens(subject.subject_id)
    assert related.id == token.id

    assert {:ok, actions} = Autolaunch.list_subject_actions(subject.subject_id)
    assert Enum.map(actions, & &1.id) == [newer.id, other_action.id, older.id]
    assert Enum.all?(actions, &(&1.subject_id == subject.id))

    assert {:ok, settlements} = Autolaunch.list_subject_settlements(subject.subject_id)
    assert Enum.map(settlements, & &1.id) == [newer.id, older.id]
    assert Enum.all?(settlements, &(&1.action == "settle_buyback"))
    assert {:ok, nil} = Autolaunch.get_public_subject("subject:missing")
  end

  test "canonical subject identity is unique" do
    subject = subject!()

    assert_raise Ash.Error.Invalid, fn ->
      subject!(subject.subject_id)
    end
  end

  test "canonical subject identities reject every value unsafe for the public route" do
    for {unsafe_class, subject_id} <- @unsafe_subject_ids do
      assert {:error, %Ash.Error.Invalid{} = error} = import_subject(subject_id)

      message = Exception.message(error)
      assert message =~ "subject_id", "#{unsafe_class} did not identify the invalid field"

      assert message =~ "must match the pattern" or
               message =~ "length must be less than or equal to 128",
             "#{unsafe_class} did not explain the canonical ID format"
    end
  end

  test "canonical subject identity constraints also protect token and action imports" do
    subject = subject!()

    auction =
      Autolaunch.import_auction!(
        "Canonical identity boundary",
        nil,
        false,
        :graduated,
        DateTime.utc_now(),
        actor: %System{}
      )

    assert {:error, %Ash.Error.Invalid{} = token_error} =
             Autolaunch.import_subject_token(
               auction.id,
               "subject/slash",
               "Unsafe Subject Token",
               "UST",
               nil,
               DateTime.utc_now(),
               nil,
               actor: %System{}
             )

    assert Exception.message(token_error) =~ "must match the pattern"

    assert {:error, %Ash.Error.Invalid{} = action_error} =
             Autolaunch.import_subject_action(
               "#{subject.subject_id}?query",
               "settle_buyback",
               nil,
               8453,
               nil,
               nil,
               "pending",
               nil,
               actor: %System{}
             )

    assert Exception.message(action_error) =~ "must match the pattern"
    refute Exception.message(action_error) =~ "does not identify a public subject"
  end

  test "subject lookup preserves read failures and only treats a missing record as invalid input" do
    changeset = Ash.Changeset.new(SubjectAction)

    missing = ResolveSubject.apply_lookup_result(changeset, {:ok, nil})
    assert [missing_error] = missing.errors
    assert Exception.message(missing_error) =~ "does not identify a public subject"

    read_error =
      Ash.Error.Unknown.UnknownError.exception(error: "subject lookup unavailable")

    failed = ResolveSubject.apply_lookup_result(changeset, {:error, read_error})
    assert failed.errors == [read_error]
    refute Exception.message(hd(failed.errors)) =~ "does not identify a public subject"
  end

  test "subject and action imports require the real system actor" do
    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.import_subject(
                 "subject:forbidden",
                 "agent",
                 8453,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 nil,
                 actor: actor
               )
    end

    subject = subject!()

    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Autolaunch.import_subject_action(
                 subject.subject_id,
                 "settle_buyback",
                 nil,
                 8453,
                 nil,
                 nil,
                 "pending",
                 nil,
                 actor: actor
               )
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Autolaunch.import_subject_action(
               "subject:missing",
               "settle_buyback",
               nil,
               8453,
               nil,
               nil,
               "pending",
               nil,
               actor: %System{}
             )
  end

  defp subject!(subject_id \\ "subject:resource") do
    case import_subject(subject_id) do
      {:ok, subject} -> subject
      {:error, error} -> raise error
    end
  end

  defp import_subject(subject_id) do
    Autolaunch.import_subject(
      subject_id,
      "agent",
      8453,
      "0x3333333333333333333333333333333333333333",
      "0x4444444444444444444444444444444444444444",
      "0x5555555555555555555555555555555555555555",
      "0x6666666666666666666666666666666666666666",
      "0x7777777777777777777777777777777777777777",
      "0x8888888888888888888888888888888888888888",
      1500,
      250,
      200,
      "12000000",
      "3400000000000000000",
      "5000000",
      actor: %System{}
    )
  end
end
