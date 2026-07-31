defmodule AshPlatform.Autolaunch.SubjectPaymentChainClient do
  @moduledoc false

  @callback confirm(map(), String.t(), String.t() | nil) ::
              {:ok, map()} | {:error, atom()}
  @callback approval_status(map(), String.t()) ::
              {:ok, :pending | :success | :reverted} | {:error, atom()}

  def module do
    Application.get_env(
      :ash_platform,
      :autolaunch_subject_payment_chain_client,
      AshPlatform.Autolaunch.SubjectPaymentRpcClient
    )
  end
end
