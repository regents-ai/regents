defmodule AgentEns do
  @moduledoc """
  Main entry point for the package.

  If you are new to `ens_elixir`, start here instead of jumping straight into the
  lower-level modules.

  The package is built around a simple progression:

  - verify an existing ENSIP-25 proof
  - read the current state of a name
  - plan what still needs to change
  - prepare the next unsigned request

  The most useful functions are:

  - `verify/6` for a yes-or-no check
  - `verify_agent/5` when you want to use a built-in ERC-8004 network
  - `read_name/1` for a fuller view of a name or subname
  - `plan_link/1` for a read-only snapshot of what is done, missing, ready, or blocked
  - `prepare_ensip25_update/1` for the ENS proof record
  - `prepare_erc8004_update/1` for the agent registration update
  - `prepare_bidirectional_link/1` for the common "do both sides" flow

  When you need a more focused one-off ENS change, use `AgentEns.Tx`.

  All public functions return either `{:ok, value}` or `{:error, %AgentEns.Error{}}`.
  """

  alias AgentEns.ERC7930
  alias AgentEns.Link
  alias AgentEns.Plan
  alias AgentEns.Read
  alias AgentEns.RecordKey
  alias AgentEns.Tx
  alias AgentEns.Verify

  @doc """
  Builds the ENSIP-25 text record key for an EVM registry entry.
  """
  @spec evm_record_key(non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, AgentEns.Error.t()}
  def evm_record_key(chain_id, registry_address, agent_id) do
    RecordKey.evm_record_key(chain_id, registry_address, agent_id)
  end

  @doc """
  Builds an interoperable ERC-7930 address from a chain ID and EVM address.
  """
  @spec interoperable_address(non_neg_integer(), String.t()) ::
          {:ok, ERC7930.t()} | {:error, AgentEns.Error.t()}
  def interoperable_address(chain_id, address) do
    ERC7930.evm(chain_id, address)
  end

  @doc """
  Reads the current state of an ENS name or subname.

  Use this when you want to show who controls the name, which resolver it uses,
  and which records are already present.
  """
  @spec read_name(map()) :: {:ok, Read.NameDetails.t()} | {:error, AgentEns.Error.t()}
  def read_name(input), do: Read.read_name(input)

  @doc """
  Builds a read-only link plan for ENS and ERC-8004.

  This is the best starting point when you want to know what is already done,
  what is missing, and whether the current signer can make the next change.
  """
  @spec plan_link(map()) :: {:ok, Plan.LinkPlan.t()} | {:error, AgentEns.Error.t()}
  def plan_link(input), do: Plan.plan_link(input)

  @doc """
  Checks whether an ENS name already contains the expected ENSIP-25 proof.
  """
  @spec verify(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          keyword()
        ) ::
          {:ok, Verify.verification_status()} | {:error, AgentEns.Error.t()}
  def verify(rpc_url, ens_name, chain_id, registry_address, agent_id, opts \\ []) do
    Verify.verify(rpc_url, ens_name, chain_id, registry_address, agent_id, opts)
  end

  @doc """
  Checks whether an ENS name proves a built-in ERC-8004 network mapping.
  """
  @spec verify_agent(String.t(), atom(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, Verify.verification_status()} | {:error, AgentEns.Error.t()}
  def verify_agent(rpc_url, network, agent_id, ens_name, opts \\ []) do
    Verify.verify_agent(rpc_url, network, agent_id, ens_name, opts)
  end

  @doc """
  Prepares the unsigned request that writes the ENSIP-25 proof record.
  """
  @spec prepare_ensip25_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), tx: AgentEns.TxRequest.t()}}
          | {:error, AgentEns.Error.t()}
  def prepare_ensip25_update(input), do: Link.prepare_ensip25_update(input)

  @doc """
  Prepares the unsigned request that updates the ERC-8004 registration.
  """
  @spec prepare_erc8004_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, AgentEns.Error.t()}
  def prepare_erc8004_update(input), do: Link.prepare_erc8004_update(input)

  @doc """
  Prepares the unsigned request that clears the ENS service entry from the ERC-8004 registration.
  """
  @spec prepare_erc8004_clear(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, AgentEns.Error.t()}
  def prepare_erc8004_clear(input), do: Link.prepare_erc8004_clear(input)

  @doc """
  Plans the link and prepares the next unsigned requests for both sides.
  """
  @spec prepare_bidirectional_link(map()) ::
          {:ok, map()} | {:error, AgentEns.Error.t()}
  def prepare_bidirectional_link(input), do: Link.prepare_bidirectional_link(input)

  @doc """
  Prepares the unsigned request that upgrades a reserved Regent ENS name on Ethereum mainnet.
  """
  @spec prepare_regent_subname_upgrade(map()) ::
          {:ok, AgentEns.TxRequest.t()} | {:error, AgentEns.Error.t()}
  def prepare_regent_subname_upgrade(input), do: Tx.build_regent_subname_upgrade_tx(input)

  @doc """
  Prepares the unsigned request that writes the ENSIP-25 proof through the Regent registrar.
  """
  @spec prepare_regent_ensip25_update(map()) ::
          {:ok, AgentEns.TxRequest.t()} | {:error, AgentEns.Error.t()}
  def prepare_regent_ensip25_update(input), do: Tx.build_regent_ensip25_link_tx(input)

  @doc """
  Prepares the unsigned request that writes the Regent ENS name's ETH address through the Regent registrar.
  """
  @spec prepare_regent_addr_update(map()) ::
          {:ok, AgentEns.TxRequest.t()} | {:error, AgentEns.Error.t()}
  def prepare_regent_addr_update(input), do: Tx.build_regent_addr_tx(input)
end
