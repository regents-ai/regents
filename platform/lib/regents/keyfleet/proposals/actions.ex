defmodule Regents.Keyfleet.Proposals.Actions do
  @moduledoc """
  The calls a proposal can make, both ways: `encode/2` builds the exact
  calls of each kind of proposal the site offers, and `decode/2` reads a
  recorded call back as the action it takes, so a proposal's page can say in
  plain words what carrying it out does.

  The site offers a decision, which makes no call at all, a payment, the
  daily split's rate, restricting a Key's edits, which names the Key by its
  id in the Key collection, and a launch, which calls Autolaunch v2's factory
  and names the fleet's treasury as the launch's treasury. The vote contract
  takes other calls too, made to the chain directly: `decode/2` also reads an
  advance and an approval or revocation of the treasury's own Lit wallet
  request, so voters see what such a proposal does.
  """

  alias RegentChain.{Abi, Call}
  alias Regents.Keyfleet.Fleets.Fleet

  @pay "pay(address,address,uint32)"
  @advance "advance(uint256,address,address,uint32,bytes32)"
  @rate "setDailySplitBps(uint256)"
  @approve_lit "approveLitCreateWallet(uint256)"
  @revoke_lit "revokeLitCreateWallet(uint256)"
  @voted_split "runVotedSplit()"
  @admit_ousd "admitOusd(address)"
  @edits "setEditsRestricted(uint256,bool)"
  @launch "launch((string,string,string,string,string,address))"
  @functions [
               @pay,
               @advance,
               @rate,
               @approve_lit,
               @revoke_lit,
               @voted_split,
               @admit_ousd,
               @edits
             ] ++
               [@launch]

  @doc "The selector of the factory's launch call."
  def launch_selector, do: Call.selector(@launch)

  @doc """
  The calls of one kind of proposal, as `{target, wei, calldata}`:

    * `:decision`, no call;
    * `{:pay, asset, to, share}` from the treasury, `share` in parts per
      million of the treasury's balance of `asset` when the proposal is
      carried out;
    * `{:rate, bps}`, the daily split's rate;
    * `{:edits, token_id, restricted?}`, `token_id` the fleet's Key number;
    * `{:launch, %{name:, symbol:, description:, website:, image:}}`.
  """
  def encode(:decision, _fleet), do: []

  def encode({:pay, asset, to, share}, fleet),
    do: [treasury(fleet, Call.encode(@pay, [asset, to, share]))]

  def encode({:rate, bps}, fleet), do: [treasury(fleet, Call.encode(@rate, [bps]))]

  def encode({:edits, token_id, restricted?}, fleet),
    do: [
      {fleet.votes_address, 0,
       Call.encode(@edits, [Fleet.onchain_token_id(fleet, token_id), restricted?])}
    ]

  def encode({:launch, launch}, fleet) do
    params =
      {launch.name, launch.symbol, launch.description, launch.website, launch.image,
       fleet.treasury_address}

    [{fleet.autolaunch_factory_address, 0, Call.encode(@launch, [params])}]
  end

  defp treasury(fleet, data), do: {fleet.treasury_address, 0, data}

  @doc """
  What one recorded call does, as `encode/2` names it, plus `{:advance, id,
  operator, asset, share, purpose}`, `{:signature, :approve | :revoke,
  issued_at}` for the treasury's own Lit `CreateWallet` request at
  `issued_at`, in seconds, `:voted_split`, `{:admit_ousd, token}` and, for
  any other call, `{:other, target, data}`.
  A call is read as an action only when it is made to the contract that
  action belongs to. The vote contract refuses a proposal whose calls send
  ETH, so no recorded call does.
  """
  def decode(%{target: target, value: 0, data: "0x" <> _hex = data}, fleet) do
    {selector, arguments} = String.split_at(data, 10)

    with {:ok, bytes} <- Abi.bytes("0x" <> arguments),
         {:ok, action} <- action(contract(target, fleet), selector, bytes, fleet) do
      action
    else
      _other -> {:other, target, data}
    end
  end

  @doc """
  Which of the fleet's contracts `target` is: `:treasury`, `:votes`,
  `:manager`, `:autolaunch` for Autolaunch v2's factory, or `:other`.
  """
  def contract(target, fleet) do
    cond do
      target == fleet.treasury_address -> :treasury
      target == fleet.votes_address -> :votes
      target == fleet.manager_address -> :manager
      target == fleet.autolaunch_factory_address -> :autolaunch
      true -> :other
    end
  end

  @doc """
  The signature of the function a call's `data` names, when it is one this
  site's proposals make or read; otherwise nil.
  """
  def function("0x" <> _hex = data) do
    selector = String.slice(data, 0, 10)
    Enum.find(@functions, &(Call.selector(&1) == selector))
  end

  defp action(contract, selector, bytes, fleet) do
    case {contract, selector} do
      {:treasury, selector} ->
        treasury_action(selector, bytes)

      {:votes, selector} ->
        if selector == Call.selector(@edits), do: edits(bytes, fleet), else: :error

      {:autolaunch, selector} ->
        if selector == launch_selector(), do: launch(bytes), else: :error

      _other ->
        :error
    end
  end

  defp treasury_action(selector, bytes) do
    cond do
      selector == Call.selector(@pay) ->
        with {:ok, [asset, to, share]} <- Abi.decode(bytes, [:address, :address, {:uint, 32}]),
             do: {:ok, {:pay, asset, to, share}}

      selector == Call.selector(@advance) ->
        with {:ok, [id, operator, asset, share, purpose]} <-
               Abi.decode(bytes, [{:uint, 256}, :address, :address, {:uint, 32}, :bytes32]),
             do: {:ok, {:advance, id, operator, asset, share, purpose}}

      selector == Call.selector(@rate) ->
        with {:ok, [bps]} <- Abi.decode(bytes, [{:uint, 256}]), do: {:ok, {:rate, bps}}

      selector == Call.selector(@approve_lit) ->
        with {:ok, [issued_at]} <- Abi.decode(bytes, [{:uint, 256}]),
             do: {:ok, {:signature, :approve, issued_at}}

      selector == Call.selector(@revoke_lit) ->
        with {:ok, [issued_at]} <- Abi.decode(bytes, [{:uint, 256}]),
             do: {:ok, {:signature, :revoke, issued_at}}

      selector == Call.selector(@voted_split) ->
        with {:ok, []} <- Abi.decode(bytes, []), do: {:ok, :voted_split}

      selector == Call.selector(@admit_ousd) ->
        with {:ok, [token]} <- Abi.decode(bytes, [:address]), do: {:ok, {:admit_ousd, token}}

      true ->
        :error
    end
  end

  # A Key of another fleet is no action of this one.
  defp edits(bytes, fleet) do
    with {:ok, [token_id, restricted?]} <- Abi.decode(bytes, [{:uint, 256}, :bool]),
         {:ok, key} <- Fleet.key_number(fleet, token_id) do
      {:ok, {:edits, key, restricted?}}
    else
      _other -> :error
    end
  end

  # The launch's one argument is a tuple with strings in it, so its head is
  # the offset of the tuple, and the tuple is read as its own fields.
  defp launch(<<32::256, tuple::binary>>) do
    with {:ok, [name, symbol, description, website, image, treasury]} <-
           Abi.decode(tuple, [:bytes, :bytes, :bytes, :bytes, :bytes, :address]) do
      {:ok,
       {:launch,
        %{
          name: name,
          symbol: symbol,
          description: description,
          website: website,
          image: image,
          treasury: treasury
        }}}
    end
  end

  defp launch(_bytes), do: :error
end
