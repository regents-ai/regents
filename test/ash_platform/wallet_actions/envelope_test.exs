defmodule AshPlatform.WalletActions.EnvelopeTest do
  use ExUnit.Case, async: true

  alias AshPlatform.WalletActions.Envelope

  @signer "0x1111111111111111111111111111111111111111"
  @target "0x2222222222222222222222222222222222222222"
  @data "0xabcdef"
  @context [to: @target, resource: "example", contract_name: "Example", risk_copy: "Review"]
  @validation [
    to: @target,
    signer: @signer,
    resource: "example",
    contract_name: "Example",
    action: "act"
  ]

  test "requires explicit capability context" do
    assert_raise KeyError, fn -> Envelope.new("act", @signer, @data, risk_copy: "Review") end
  end

  test "rejects zero signer and target addresses" do
    zero = "0x" <> String.duplicate("0", 40)

    assert_raise ArgumentError, fn -> Envelope.new("act", zero, @data, @context) end

    assert_raise ArgumentError, fn ->
      Envelope.new("act", @signer, @data, Keyword.replace!(@context, :to, zero))
    end
  end

  test "rejects target and signer drift" do
    envelope = Envelope.new("act", @signer, @data, @context)
    assert Envelope.valid?(envelope, @validation)
    refute Envelope.valid?(envelope, Keyword.replace!(@validation, :to, @signer))

    refute Envelope.valid?(
             %{envelope | expected_signer: @target},
             @validation
           )
  end

  test "rejects an expired preparation" do
    old = DateTime.utc_now() |> DateTime.add(-601, :second)
    previous = Application.get_env(:ash_platform, :wallet_action_clock)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> old end)
    envelope = Envelope.new("act", @signer, @data, @context)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end)
    on_exit(fn -> restore(:wallet_action_clock, previous) end)
    refute Envelope.valid?(envelope, @validation)
    refute Envelope.valid_for_confirmation?(envelope, @validation)
  end

  test "rejects an otherwise authentic envelope advertising more than ten minutes" do
    envelope = Envelope.new("act", @signer, @data, @context)
    assert Envelope.valid?(envelope, @validation)
    assert Envelope.valid_for_confirmation?(envelope, @validation)
    {:ok, prepared_at, _offset} = DateTime.from_iso8601(envelope.prepared_at)

    envelope =
      envelope
      |> Map.put(:expires_at, prepared_at |> DateTime.add(601, :second) |> DateTime.to_iso8601())
      |> resign()

    refute Envelope.valid?(envelope, @validation)
    refute Envelope.valid_for_confirmation?(envelope, @validation)
  end

  test "binds validation to the expected action" do
    envelope = Envelope.new("act", @signer, @data, @context)
    refute Envelope.valid?(envelope, Keyword.replace!(@validation, :action, "other"))

    refute Envelope.valid_for_confirmation?(
             envelope,
             Keyword.replace!(@validation, :action, "other")
           )
  end

  test "rejects an intact signed envelope for another current signer or handler contract" do
    envelope = Envelope.new("act", @signer, @data, @context)
    other_signer = "0x3333333333333333333333333333333333333333"

    for validator <- [&Envelope.valid?/2, &Envelope.valid_for_confirmation?/2] do
      refute validator.(envelope, Keyword.replace!(@validation, :signer, other_signer))
      refute validator.(envelope, Keyword.replace!(@validation, :contract_name, "Other"))
    end
  end

  test "rejects empty context and malformed calldata before signing" do
    for {field, context} <- [
          {:action, {"", @data, @context}},
          {:resource, {"act", @data, Keyword.replace!(@context, :resource, "")}},
          {:contract_name, {"act", @data, Keyword.replace!(@context, :contract_name, "")}},
          {:risk_copy, {"act", @data, Keyword.replace!(@context, :risk_copy, "")}}
        ] do
      assert_raise ArgumentError, ~r/#{field}/, fn ->
        {action, data, opts} = context
        Envelope.new(action, @signer, data, opts)
      end
    end

    for data <- ["", "0x", "0x0", "0xzz"] do
      assert_raise ArgumentError, ~r/data/, fn -> Envelope.new("act", @signer, data, @context) end
    end
  end

  # A durable submitted hash has to stay verifiable once its signing window
  # closes, or a launch that really is on Base could never be told the truth
  # about. Only the resources that own a durable operation are on that list.
  test "an expired launch envelope is no longer sendable but is still confirmable" do
    old = DateTime.utc_now() |> DateTime.add(-601, :second)
    previous = Application.get_env(:ash_platform, :wallet_action_clock)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> old end)

    launch = Envelope.new("autolaunch_launch", @signer, @data, launch_context())
    other = Envelope.new("act", @signer, @data, @context)

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end)
    on_exit(fn -> restore(:wallet_action_clock, previous) end)

    refute Envelope.valid?(launch, resource: "autolaunch_launch")
    assert Envelope.valid_for_confirmation?(launch, resource: "autolaunch_launch")

    # A resource that owns no durable operation is not confirmable after expiry.
    refute Envelope.valid_for_confirmation?(other, @validation)
  end

  defp launch_context do
    [
      to: @target,
      resource: "autolaunch_launch",
      contract_name: "RegentsAutolaunchFactoryV1",
      risk_copy: "Review"
    ]
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)

  defp resign(envelope) do
    payload =
      envelope
      |> Map.take([
        :action_id,
        :idempotency_key,
        :resource,
        :action,
        :chain_id,
        :to,
        :value,
        :data,
        :expected_signer,
        :prepared_at,
        :expires_at,
        :risk_copy,
        :approval,
        :arguments,
        :metadata
      ])
      |> Jason.encode!()
      |> Jason.decode!()

    Map.put(
      envelope,
      :confirmation_token,
      Phoenix.Token.sign(AshPlatformWeb.Endpoint, "wallet-action", payload)
    )
  end
end
