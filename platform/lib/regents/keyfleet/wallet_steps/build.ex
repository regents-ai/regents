defmodule Regents.Keyfleet.WalletSteps.Build do
  @moduledoc """
  Builds the steps one wallet button group sends, for one signer, as a
  `RegentChain.Review`: every step's contract and calldata, encoded here and
  never in a page.

  The answer is `%{review: review, figures: figures, problem: problem}`.
  `figures` are what the steps were built from, for the page to show beside
  the buttons. When what was typed can't be put into a call, or the chain
  can't be read, the review has no steps and `problem` names why; otherwise
  `problem` is nil. Vote, Mark present and Claim all are an exception: when
  the chain doesn't answer whether Keys reached the signer since the reader's
  last block (`own_keys/3`), their steps are still built, with the Keys known,
  and `problem` is `:unread`. Asking again for a Key's draw and ending its
  wait are another: their calls need nothing from the chain, so when it
  doesn't answer they are still built, and `problem` is `:unread`.

  `figures.blocked` names each step the chain's own state, read at the latest
  block, makes certain to fail, with why: `%{"claim-0x…" => :nothing_to_claim}`.
  Its button stays in view, can't be pressed, says why in a few words, and
  comes back when a later build no longer names it. Every flow's transactions
  are also named `:no_eth_for_gas` here, in one place, when the signer pays
  its own network fee and holds less ETH than any transaction costs
  (`Regents.Keyfleet.WalletSteps.Reads.short_of_gas?/2`), unless `sending` is false:
  the steps then only show the figures of a wallet no press is sent from, so
  its ETH says nothing about a press. Nothing else holds a press
  back: a pending transaction, a repeat press, or one that only might be
  refused always reaches the wallet, and the contract decides.

  Each group's steps are built by one of `Regents.Keyfleet.WalletSteps.KeySteps`,
  `Regents.Keyfleet.WalletSteps.VoteSteps`, `Regents.Keyfleet.WalletSteps.MoneySteps` and
  `Regents.Keyfleet.WalletSteps.LaunchSteps`, each of which answers `{:ok, steps,
  figures}`, `{:ok, steps, figures, problem}` or `{:problem, problem,
  figures}`. Key sales need a fleet the site has recorded as deployed, which
  is how they stay off: no fleet is recorded on Base yet.
  """
  use Ash.Resource.Actions.Implementation

  alias RegentChain.Review
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Chain.{Logs, OwnershipLog, ShardsLog}
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.WalletSteps
  alias Regents.Keyfleet.WalletSteps.{KeySteps, LaunchSteps, MoneySteps, Reads, VoteSteps}

  @builders %{
    buy: KeySteps,
    reveal: KeySteps,
    claim: KeySteps,
    claim_all: KeySteps,
    club_claim: KeySteps,
    present: KeySteps,
    present_idle: KeySteps,
    issue_shard: KeySteps,
    end_shard: KeySteps,
    agent_voting: KeySteps,
    ballot: VoteSteps,
    propose: VoteSteps,
    cancel: VoteSteps,
    carry_out: VoteSteps,
    run_split: MoneySteps,
    return_advance: MoneySteps,
    send_share: MoneySteps,
    convert: MoneySteps,
    launch_upkeep: LaunchSteps
  }

  @doc "Every group of wallet buttons the site builds steps for."
  def flows, do: Map.keys(@builders)

  @impl true
  def run(input, _opts, _context) do
    %{signer: signer, component_id: component_id} = input.arguments

    with {:ok, request, built} <- build(input.arguments, String.downcase(signer)) do
      {:ok,
       %{
         review:
           Review.new(component_id, request.signer, request.chain, built.steps, request.inputs),
         figures: built.figures,
         problem: built.problem
       }}
    end
  end

  @doc """
  The steps `arguments` name, built for `signer`, or for nil, a visitor, who
  acts for no key: `{:ok, request, %{steps, figures, problem}}`.
  """
  def build(arguments, signer) do
    with {:ok, fleet} <- deployed(arguments.fleet_id),
         {:ok, chain} <- chain(fleet.chain_id) do
      request = %{
        fleet: fleet,
        chain: chain,
        signer: signer,
        inputs: Map.get(arguments, :inputs, %{}),
        proposal: Map.get(arguments, :proposal),
        token_id: Map.get(arguments, :token_id),
        advance_id: Map.get(arguments, :advance_id)
      }

      {steps, figures, problem} =
        case Map.fetch!(@builders, arguments.flow).steps(arguments.flow, request) do
          {:ok, steps, figures} -> {steps, figures, nil}
          {:ok, steps, figures, problem} -> {steps, figures, problem}
          {:problem, problem, figures} -> {[], figures, problem}
        end

      fee_payer = if Map.get(arguments, :sending, true), do: signer
      figures = no_eth_for_gas(steps, fee_payer, Map.put_new(figures, :blocked, %{}))
      {:ok, request, %{steps: steps, figures: figures, problem: problem}}
    end
  end

  # A signer that pays its own fee with less ETH than any transaction costs
  # can send none of the group's transactions. A signature costs nothing, a
  # wallet no press is sent from pays nothing, and a code or balance the chain
  # didn't answer holds nothing back.
  defp no_eth_for_gas(_steps, nil, figures), do: figures

  defp no_eth_for_gas(steps, signer, figures) do
    case for(%{kind: "transaction", step: name} <- steps, do: name) do
      [] -> figures
      sent -> block_if_short(sent, signer, figures)
    end
  end

  defp block_if_short(sent, signer, figures) do
    with {:ok, reads} <- Reads.at_head(),
         {:ok, true} <- Reads.short_of_gas?(reads, signer) do
      # Chain-state and ownership blocks (closed vote, not your Key, etc.) always
      # take precedence over gas so visitors aren't told to fund ETH for an action
      # that cannot succeed regardless of balance.
      gas_blocks = Map.new(sent, &{&1, :no_eth_for_gas})
      %{figures | blocked: Map.merge(gas_blocks, figures.blocked)}
    else
      _not_known_short -> figures
    end
  end

  defp deployed(fleet_id) do
    case Fleets.get_fleet!(fleet_id) do
      %{manager_address: address} = fleet when is_binary(address) -> {:ok, fleet}
      _missing_or_not_on_chain -> {:error, "fleet #{fleet_id} is not on chain"}
    end
  end

  defp chain(chain_id) do
    case WalletSteps.chain(chain_id) do
      nil -> {:error, "no wallet chain is set for chain #{chain_id}"}
      chain -> {:ok, chain}
    end
  end

  @doc """
  A field of the form as typed, read by `read`; a problem with it ends the
  build with `figures` so far.
  """
  def typed(inputs, name, read, figures) do
    case read.(field(inputs, name)) do
      {:ok, value} -> {:ok, value}
      {:error, problem} -> {:problem, problem, figures}
    end
  end

  @doc "A field of the form as typed, or empty."
  def field(inputs, name), do: Map.get(inputs, name, "")

  @doc """
  Every Key of the fleet the signer may hold or hold an active shard of, at
  `reads`' head: those the chain reader recorded, and those that reached the
  signer in the blocks it hasn't read yet, which the chain is asked for in one
  read, of the Key collection's moves and the shards issued from the reader's
  next block to the head. The chain is then asked which of them the signer may
  act for, so a Key that has left since drops out there.

  `{keys, nil}` is every such Key. `{recorded, :unread}` is the recorded ones
  alone, when the chain didn't answer that read: the signer may hold more, so
  no press is held back for want of a Key, and the build says the chain
  couldn't be read.
  """
  def own_keys(reads, fleet, signer) do
    # The reader records Keys and moves its cursor together, so the cursor is
    # read before the Keys: whatever it records in between is in both.
    from = next_block(fleet)
    held = fleet.id |> Keys.keys_held_in_fleet!([signer]) |> Enum.map(& &1.token_id)

    sharded =
      for shard <- Keys.active_shards_held_by!(signer),
          shard.fleet_id == fleet.id,
          do: shard.token_id

    case arrived(reads, fleet, signer, from) do
      {:ok, arrived} -> {Enum.sort(Enum.uniq(held ++ sharded ++ arrived)), nil}
      {:error, _reason} -> {Enum.sort(Enum.uniq(held ++ sharded)), :unread}
    end
  end

  defp next_block(fleet) do
    case Chain.get_cursor!(fleet.id) do
      nil -> fleet.deployed_block
      cursor -> cursor.next_block
    end
  end

  defp arrived(reads, fleet, signer, from) do
    with {:ok, logs} <-
           Reads.logs(
             reads,
             [fleet.keys_address, fleet.shards_address],
             [OwnershipLog.topic(), ShardsLog.issued_topic()],
             from
           ),
         {:ok, records} <- Logs.decode(logs, fleet, nil, from, Reads.block(reads)) do
      {:ok, for(record <- records, key = to_signer(record, signer), do: key)}
    end
  end

  defp to_signer({:ownership, %{owner_wallet: signer, token_id: key}}, signer), do: key
  defp to_signer({:shard, %{kind: :issued, wallet: signer, token_id: key}}, signer), do: key
  defp to_signer(_record, _signer), do: nil
end
