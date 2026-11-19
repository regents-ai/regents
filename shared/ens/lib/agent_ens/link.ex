defmodule AgentEns.Link do
  @moduledoc """
  High-level helpers for planning and preparing ENS and ERC-8004 updates.

  This module is the easiest way to go from "tell me what is missing" to
  "give me the next unsigned request."

  In practice:

  - `prepare_ensip25_update/1` handles only the ENS proof record
  - `prepare_erc8004_update/1` handles only the agent registration update
  - `prepare_bidirectional_link/1` gives you the common all-in-one flow

  These functions do not send anything. They stop after producing the next
  request for your wallet or signer.
  """

  alias AgentEns.Error
  alias AgentEns.ERC8004.Registration
  alias AgentEns.Plan
  alias AgentEns.Tx

  @spec plan(map()) :: {:ok, Plan.LinkPlan.t()} | {:error, Error.t()}
  def plan(input), do: Plan.plan_link(input)

  @spec prepare_erc8004_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, Error.t()}
  def prepare_erc8004_update(input) when is_map(input) do
    input = normalize_link_input(input)

    with {:ok, plan} <- Plan.plan_link(input),
         :ok <- ensure_action_ready(plan, :update_erc8004_registration),
         {:ok, prepared} <-
           Registration.prepare_updated_registration(%{
             current_agent_uri: plan.erc8004_token_uri,
             ens_name: plan.normalized_ens_name,
             fetcher: input.erc8004_fetcher,
             publisher: input.publisher,
             opts: input.erc8004_fetch_opts
           }),
         {:ok, tx} <-
           Tx.build_set_agent_uri_tx(%{
             chain_id: input.registry_chain_id,
             registry_address: input.registry_address,
             agent_id: input.agent_id,
             new_uri: prepared.new_uri
           }) do
      {:ok, %{plan: plan, new_registration: prepared.new_registration, tx: tx}}
    end
  end

  @spec prepare_erc8004_clear(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, Error.t()}
  def prepare_erc8004_clear(input) when is_map(input) do
    input = normalize_link_input(input)

    with {:ok, plan} <- Plan.plan_link(input),
         :ok <- ensure_erc8004_clear_ready(plan),
         {:ok, prepared} <-
           Registration.prepare_cleared_registration(%{
             current_agent_uri: plan.erc8004_token_uri,
             fetcher: input.erc8004_fetcher,
             publisher: input.publisher,
             opts: input.erc8004_fetch_opts
           }),
         {:ok, tx} <-
           Tx.build_set_agent_uri_tx(%{
             chain_id: input.registry_chain_id,
             registry_address: input.registry_address,
             agent_id: input.agent_id,
             new_uri: prepared.new_uri
           }) do
      {:ok, %{plan: plan, new_registration: prepared.new_registration, tx: tx}}
    end
  end

  @spec prepare_ensip25_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), tx: AgentEns.TxRequest.t()}} | {:error, Error.t()}
  def prepare_ensip25_update(input) when is_map(input) do
    input = normalize_link_input(input)

    with {:ok, plan} <- Plan.plan_link(input),
         :ok <- ensure_action_ready(plan, :set_ens_text),
         {:ok, tx} <-
           Tx.build_set_text_tx(%{
             ens_name: plan.normalized_ens_name,
             chain_id: input.ens_chain_id,
             record_chain_id: input.registry_chain_id,
             registry_address: input.registry_address,
             agent_id: input.agent_id,
             resolver_address: plan.resolver_address,
             value: input.value
           }) do
      {:ok, %{plan: plan, tx: tx}}
    end
  end

  @spec prepare_bidirectional_link(map()) ::
          {:ok,
           %{
             plan: Plan.LinkPlan.t(),
             forward: map() | :noop | :blocked,
             erc8004: map() | :noop | :blocked,
             ensip25: map() | :noop | :blocked,
             reverse: map() | :noop | :skipped,
             cleanup: map()
           }}
          | {:error, Error.t()}
  def prepare_bidirectional_link(input) when is_map(input) do
    input = normalize_link_input(input)

    with {:ok, plan} <- Plan.plan_link(input) do
      {:ok,
       %{
         plan: plan,
         forward: maybe_prepare_forward(plan, input),
         erc8004: maybe_prepare_erc8004(plan, input),
         ensip25: maybe_prepare_ensip25(plan, input),
         reverse: maybe_prepare_reverse(plan, input),
         cleanup: %{forward: :noop, ensip25: :noop, erc8004: :noop, reverse: :skipped}
       }}
    end
  end

  defp maybe_prepare_forward(plan, _input) when plan.forward_resolution_verified, do: :noop

  defp maybe_prepare_forward(plan, input) do
    case Enum.find(plan.actions, &(&1.kind == :set_ens_address)) do
      %{status: :ready} ->
        case Tx.build_set_addr_tx(%{
               ens_name: plan.normalized_ens_name,
               chain_id: input.ens_chain_id,
               resolver_address: plan.resolver_address,
               address: input.signer_address
             }) do
          {:ok, tx} -> %{tx: tx}
          {:error, _} -> :blocked
        end

      _ ->
        :blocked
    end
  end

  defp maybe_prepare_erc8004(plan, _input) when plan.erc8004_status == :ens_service_present,
    do: :noop

  defp maybe_prepare_erc8004(_plan, input) do
    case prepare_erc8004_update(input) do
      {:ok, prepared} -> prepared
      {:error, _} -> :blocked
    end
  end

  defp maybe_prepare_ensip25(plan, _input) when plan.verify_status == :verified, do: :noop

  defp maybe_prepare_ensip25(_plan, input) do
    case prepare_ensip25_update(input) do
      {:ok, prepared} -> prepared
      {:error, _} -> :blocked
    end
  end

  defp maybe_prepare_reverse(%{reverse_status: :not_requested}, _input), do: :skipped
  defp maybe_prepare_reverse(%{reverse_status: :unsupported_network}, _input), do: :blocked
  defp maybe_prepare_reverse(%{reverse_status: :signer_required}, _input), do: :blocked
  defp maybe_prepare_reverse(%{reverse_resolution_verified: true}, _input), do: :noop

  defp maybe_prepare_reverse(plan, input) do
    case Tx.build_reverse_set_name_tx(%{
           chain_id: input.ens_chain_id,
           ens_name: plan.normalized_ens_name,
           reverse_registrar: input.reverse_registrar
         }) do
      {:ok, tx} -> %{tx: tx}
      {:error, _} -> :blocked
    end
  end

  defp ensure_action_ready(plan, kind) do
    case Enum.find(plan.actions, &(&1.kind == kind)) do
      %{status: :ready} ->
        :ok

      %{status: :noop} ->
        {:error, Error.new({:unexpected_state, {kind, :already_satisfied}})}

      %{reason: reason} ->
        {:error, Error.new({:unexpected_state, {kind, reason}})}

      nil ->
        {:error, Error.new({:not_found, kind})}
    end
  end

  defp ensure_erc8004_clear_ready(%{erc8004_write_status: :ready}), do: :ok

  defp ensure_erc8004_clear_ready(%{erc8004_write_status: status}) do
    {:error, Error.new({:unexpected_state, {:update_erc8004_registration, status}})}
  end

  defp normalize_link_input(input) do
    %{
      ens_name: Map.get(input, :ens_name),
      ens_chain_id: Map.get(input, :ens_chain_id),
      ens_rpc_url: Map.get(input, :ens_rpc_url),
      registry_chain_id: Map.get(input, :registry_chain_id),
      registry_rpc_url: Map.get(input, :registry_rpc_url),
      registry_address: Map.get(input, :registry_address),
      agent_id: Map.get(input, :agent_id),
      rpc_module: Map.get(input, :rpc_module),
      signer_address: Map.get(input, :signer_address),
      include_reverse?: Map.get(input, :include_reverse?),
      ens_registry: Map.get(input, :ens_registry),
      name_wrapper: Map.get(input, :name_wrapper),
      reverse_registrar: Map.get(input, :reverse_registrar),
      erc8004_fetcher: Map.get(input, :erc8004_fetcher),
      erc8004_fetch_opts: Map.get(input, :erc8004_fetch_opts) || [],
      current_agent_uri: Map.get(input, :current_agent_uri),
      publisher: Map.get(input, :publisher) || Registration.DataUriPublisher,
      value: Map.get(input, :value) || "1"
    }
  end
end
