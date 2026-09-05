defmodule AshPlatform.Formation.CloudRuntimeTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}

  setup do
    Process.put(:capture_sprite_provider_calls, true)
    Process.delete(:test_sprite_create_result)
    Process.delete(:test_sprite_get_result)
    :ok
  end

  test "one owner provisions one deterministic Sprite and retries without duplicates" do
    account = account!("cloud-owner")
    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("cloud-regent", "Cloud Regent", actor: actor)
    expected_name = "regent-" <> String.replace(regent.id, "-", "")

    assert {:ok, runtime} = Formation.provision_cloud_runtime(actor: actor)
    assert_received {:sprite_create, ^expected_name}
    assert runtime.regent_id == regent.id
    assert runtime.human_account_id == account.id
    assert runtime.sprite_name == expected_name
    assert runtime.provider_status == "cold"
    assert runtime.url == "https://#{expected_name}.sprites.app"

    assert {:ok, same_runtime} = Formation.provision_cloud_runtime(actor: actor)
    assert same_runtime.id == runtime.id
    assert {:ok, [only_runtime]} = Formation.get_my_cloud_runtime(actor: actor)
    assert only_runtime.id == runtime.id
  end

  test "provisioning requires the exact human principal and a formed Regent" do
    account = account!("cloud-no-regent")

    assert {:error, _error} = Formation.provision_cloud_runtime(actor: nil)
    refute_received {:sprite_create, _name}

    for actor <- [%{role: :human, human_account_id: account.id}, %System{}] do
      assert {:error, %Ash.Error.Forbidden{}} = Formation.provision_cloud_runtime(actor: actor)
      refute_received {:sprite_create, _name}
    end

    assert {:error, %Ash.Error.Invalid{}} =
             Formation.provision_cloud_runtime(actor: %Human{human_account_id: account.id})

    refute_received {:sprite_create, _name}
  end

  test "the owner refreshes provider status through the named action" do
    account = account!("cloud-refresh")
    actor = %Human{human_account_id: account.id}
    regent = Formation.form_regent!("refresh-regent", "Refresh Regent", actor: actor)
    runtime = Formation.provision_cloud_runtime!(actor: actor)

    Process.put(:test_sprite_get_result, {
      :ok,
      %{
        provider_sprite_id: runtime.provider_sprite_id,
        sprite_name: runtime.sprite_name,
        url: runtime.url,
        provider_status: "running"
      }
    })

    assert {:ok, refreshed} = Formation.refresh_cloud_runtime(runtime, actor: actor)
    assert_received {:sprite_get, sprite_name}
    assert sprite_name == "regent-" <> String.replace(regent.id, "-", "")
    assert refreshed.provider_status == "running"
    assert DateTime.compare(refreshed.observed_at, runtime.observed_at) in [:gt, :eq]
  end

  test "malformed provider facts fail closed and persist nothing" do
    account = account!("cloud-malformed")
    actor = %Human{human_account_id: account.id}
    Formation.form_regent!("malformed-regent", "Malformed Regent", actor: actor)
    Process.put(:test_sprite_create_result, {:ok, %{"name" => "missing-provider-facts"}})

    assert {:error, %Ash.Error.Invalid{}} = Formation.provision_cloud_runtime(actor: actor)
    assert {:ok, []} = Formation.get_my_cloud_runtime(actor: actor)
  end

  defp account!(suffix) do
    Accounts.register_verified!(
      "did:privy:formation-cloud:#{suffix}:#{Elixir.System.unique_integer([:positive])}",
      nil,
      [],
      actor: %System{}
    )
  end
end
