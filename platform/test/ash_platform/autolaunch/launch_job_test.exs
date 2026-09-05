defmodule AshPlatform.Autolaunch.LaunchJobTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch

  @unsafe_job_ids [
    slash: "launch/slash",
    query: "launch?query",
    fragment: "launch#fragment",
    percent: "launch%encoded",
    space: "launch identity",
    unicode: "launch-é",
    too_long: String.duplicate("a", 129)
  ]

  test "anonymous reads expose launch progress, identity, auction linkage, addresses, and times" do
    auction =
      Autolaunch.import_auction!(
        "Launch job auction",
        nil,
        false,
        :active,
        DateTime.utc_now(),
        actor: %System{}
      )

    started_at = ~U[2026-07-30 10:00:00.000000Z]
    finished_at = ~U[2026-07-30 10:15:00.000000Z]

    launch =
      launch!("launch:resource",
        auction_id: auction.id,
        status: "complete",
        step: "record_addresses",
        started_at: started_at,
        finished_at: finished_at
      )

    assert {:ok, launches} = Autolaunch.list_launches()
    assert launch.job_id in Enum.map(launches, & &1.job_id)

    assert {:ok, public} = Autolaunch.get_public_launch(launch.job_id)
    assert public.status == "complete"
    assert public.step == "record_addresses"
    assert public.agent_id == "agent:resource"
    assert public.agent_name == "Resource Agent"
    assert public.token_name == "Resource Token"
    assert public.token_symbol == "RSC"
    assert public.chain_id == 8453
    assert public.auction_id == auction.id
    assert public.agent_safe_address == "0x1111111111111111111111111111111111111111"
    assert public.auction_address == "0x2222222222222222222222222222222222222222"
    assert public.token_address == "0x3333333333333333333333333333333333333333"
    assert public.hook_address == "0x4444444444444444444444444444444444444444"

    assert public.revenue_share_splitter_address ==
             "0x5555555555555555555555555555555555555555"

    assert public.started_at == started_at
    assert public.finished_at == finished_at
    assert {:ok, nil} = Autolaunch.get_public_launch("launch:missing")
  end

  test "canonical launch identity is unique" do
    launch = launch!()

    assert_raise Ash.Error.Invalid, fn ->
      launch!(launch.job_id)
    end
  end

  test "canonical launch identities reject every value unsafe for the public route" do
    for {unsafe_class, job_id} <- @unsafe_job_ids do
      assert {:error, %Ash.Error.Invalid{} = error} = import_launch(job_id)

      message = Exception.message(error)
      assert message =~ "job_id", "#{unsafe_class} did not identify the invalid field"

      assert message =~ "must match the pattern" or
               message =~ "length must be less than or equal to 128",
             "#{unsafe_class} did not explain the canonical ID format"
    end
  end

  test "launch imports require the real system actor" do
    for actor <- [nil, %{role: :system}, %{role: :human, human_account_id: 1}] do
      assert {:error, %Ash.Error.Forbidden{}} = import_launch("launch:forbidden", actor: actor)
    end

    assert {:ok, launch} = import_launch("launch:system", actor: %System{})
    assert launch.job_id == "launch:system"
  end

  defp launch!(job_id \\ "launch:resource", attrs \\ []) do
    case import_launch(job_id, attrs) do
      {:ok, launch} -> launch
      {:error, error} -> raise error
    end
  end

  defp import_launch(job_id, attrs \\ []) do
    Autolaunch.import_launch(
      job_id,
      Keyword.get(attrs, :status, "running"),
      Keyword.get(attrs, :step, "deploy_token"),
      Keyword.get(attrs, :agent_id, "agent:resource"),
      Keyword.get(attrs, :agent_name, "Resource Agent"),
      Keyword.get(attrs, :token_name, "Resource Token"),
      Keyword.get(attrs, :token_symbol, "RSC"),
      Keyword.get(attrs, :chain_id, 8453),
      Keyword.get(attrs, :auction_id),
      Keyword.get(attrs, :agent_safe_address, "0x1111111111111111111111111111111111111111"),
      Keyword.get(attrs, :auction_address, "0x2222222222222222222222222222222222222222"),
      Keyword.get(attrs, :token_address, "0x3333333333333333333333333333333333333333"),
      Keyword.get(attrs, :hook_address, "0x4444444444444444444444444444444444444444"),
      Keyword.get(
        attrs,
        :revenue_share_splitter_address,
        "0x5555555555555555555555555555555555555555"
      ),
      Keyword.get(attrs, :started_at),
      Keyword.get(attrs, :finished_at),
      actor: Keyword.get(attrs, :actor, %System{})
    )
  end
end
