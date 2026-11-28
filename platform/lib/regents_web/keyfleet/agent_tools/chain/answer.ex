defmodule RegentsWeb.Keyfleet.AgentTools.Chain.Answer do
  @moduledoc """
  Unsigned on-chain transaction steps built by `Regents.Keyfleet.WalletSteps`
  for the calling paired agent's own wallet, shared identically between
  Keyfleet's signed HTTP endpoints (`RegentsWeb.Keyfleet.AgentChainController`)
  and hosted MCP tools (`RegentsWeb.Keyfleet.AgentTools.Chain`).

  Nothing here signs or broadcasts any transaction; the agent's wallet sends
  the returned calldata and the contract decides.
  """

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Proposals.Errors.WordsLimitError
  alias Regents.Keyfleet.WalletSteps
  alias RegentsWeb.Keyfleet.AgentChainJSON
  alias RegentsWeb.Keyfleet.Refusal
  alias RegentsWeb.Keyfleet.WalletWords

  @max_id 9_223_372_036_854_775_807

  @doc "Builds unsigned transaction steps for `op` as `{status, body, nil}`."
  @spec answer(atom(), map(), term(), term()) :: {pos_integer(), map(), nil}
  def answer(:presence, %{"fleet_id" => fleet_id}, actor, _waiter),
    do: build(fleet_id, :present, %{}, actor)

  def answer(:split, %{"fleet_id" => fleet_id}, actor, _waiter),
    do: build(fleet_id, :run_split, %{}, actor)

  def answer(:send_share, %{"fleet_id" => fleet_id}, actor, _waiter),
    do: build(fleet_id, :send_share, %{}, actor)

  def answer(:convert, %{"fleet_id" => fleet_id, "inputs" => inputs}, actor, _waiter)
      when is_map(inputs),
      do: build(fleet_id, :convert, %{inputs: inputs}, actor)

  def answer(:convert, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:propose, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    inputs = Map.delete(params, "fleet_id")

    build(fleet_id, :propose, %{inputs: inputs}, actor, fn built ->
      if built.figures.governs?,
        do: keep_words(built, fleet_id, inputs["text"], actor),
        else: built
    end)
  end

  def answer(
        :vote,
        %{"fleet_id" => fleet_id, "number" => number, "choice" => choice},
        actor,
        _waiter
      ) do
    with_id(number, fn id ->
      build(fleet_id, :ballot, %{proposal: id}, actor, &only(&1, choice))
    end)
  end

  def answer(:vote, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:cancel, %{"fleet_id" => fleet_id, "number" => number}, actor, _waiter),
    do: with_id(number, &build(fleet_id, :cancel, %{proposal: &1}, actor))

  def answer(:cancel, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:carry_out, %{"fleet_id" => fleet_id, "number" => number}, actor, _waiter),
    do: with_id(number, &build(fleet_id, :carry_out, %{proposal: &1}, actor))

  def answer(:carry_out, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:claim, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter),
    do: with_id(token_id, &build(fleet_id, :claim, %{token_id: &1}, actor))

  def answer(:claim_all, %{"fleet_id" => fleet_id}, actor, _waiter),
    do: build(fleet_id, :claim_all, %{}, actor)

  def answer(:buy, %{"fleet_id" => fleet_id}, actor, _waiter),
    do: build(fleet_id, :buy, %{}, actor)

  def answer(:issue_shard, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    build(fleet_id, :issue_shard, %{inputs: Map.take(params, ~w(keys wallet days))}, actor)
  end

  def answer(:end_shard, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter),
    do: with_id(token_id, &build(fleet_id, :end_shard, %{token_id: &1}, actor))

  def answer(
        :agent_voting,
        %{"fleet_id" => fleet_id, "keys" => keys, "voting" => voting},
        actor,
        _waiter
      ),
      do: build(fleet_id, :agent_voting, %{inputs: %{"keys" => keys}}, actor, &only(&1, voting))

  def answer(:agent_voting, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:club_claim, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter),
    do: with_id(token_id, &build(fleet_id, :club_claim, %{token_id: &1}, actor))

  def answer(:reveal, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with_id(token_id, fn id ->
      build(fleet_id, :reveal, %{token_id: id}, actor, &only(&1, "reveal"))
    end)
  end

  def answer(:expire_reveal, %{"fleet_id" => fleet_id, "token_id" => token_id}, actor, _waiter) do
    with_id(token_id, fn id ->
      build(fleet_id, :reveal, %{token_id: id}, actor, &only(&1, "expire_reveal"))
    end)
  end

  def answer(
        :return_advance,
        %{"fleet_id" => fleet_id, "advance_id" => id, "amount" => amount},
        actor,
        _waiter
      ) do
    with_id(id, fn advance_id ->
      build(
        fleet_id,
        :return_advance,
        %{advance_id: advance_id, inputs: %{"amount" => amount}},
        actor
      )
    end)
  end

  def answer(:return_advance, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  def answer(:launch_upkeep, %{"fleet_id" => fleet_id, "step" => step}, actor, _waiter),
    do: build(fleet_id, :launch_upkeep, %{}, actor, &only(&1, step))

  def answer(:launch_upkeep, _params, _actor, _waiter), do: refusal(422, "invalid_request")

  defp build(fleet_id, flow, params, agent, shape \\ &Function.identity/1) do
    with {:ok, fleet} <- on_chain(fleet_id),
         :ok <- known(fleet_id, params) do
      built =
        WalletSteps.build_steps!(fleet_id, flow, agent.wallet_address, "agent", params,
          actor: agent
        )

      case built.problem do
        nil -> shaped(flow, fleet, shape.(built))
        problem -> refuse(flow, built, problem, Map.get(params, :inputs, %{}))
      end
    else
      {:refuse, status, code} -> refusal(status, code)
      {:key_unknown, token_id} -> {404, Refusal.key_unknown(fleet_id, token_id), nil}
    end
  end

  defp with_id(id, fun) when is_integer(id) and id >= 0 and id <= @max_id, do: fun.(id)

  defp with_id(text, fun) when is_binary(text) do
    case Integer.parse(text) do
      {id, ""} when id >= 0 and id <= @max_id -> fun.(id)
      _ -> refusal(422, "invalid_request")
    end
  end

  defp with_id(_other, _fun), do: refusal(422, "invalid_request")

  defp only(built, name) do
    case Enum.filter(built.review.steps, &(&1.step == name)) do
      [] -> {:refuse, 422, "invalid_request"}
      steps -> put_in(built.review.steps, steps)
    end
  end

  defp shaped(_flow, _fleet, {:refuse, status, code}), do: refusal(status, code)
  defp shaped(flow, fleet, built), do: {200, AgentChainJSON.answer(flow, fleet, built), nil}

  defp keep_words(built, fleet_id, text, agent) do
    case Proposals.save_words(fleet_id, text, agent) do
      {:ok, _words} ->
        built

      {:error, %Ash.Error.Forbidden{}} ->
        {:refuse, 403, "agent_not_paired"}

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        cond do
          Regents.Keyfleet.Agents.unpaired?(error) -> {:refuse, 403, "agent_not_paired"}
          Enum.any?(errors, &match?(%WordsLimitError{}, &1)) -> built
          true -> reported(built, error)
        end

      {:error, error} ->
        if is_exception(error), do: reported(built, error), else: built
    end
  end

  defp reported(built, error) do
    Regents.Alert.report(error)
    built
  end

  defp on_chain(fleet_id) do
    case Fleets.get_fleet!(fleet_id) do
      nil -> {:refuse, 404, "fleet_unknown"}
      %{manager_address: nil} -> {:refuse, 409, "fleet_not_on_chain"}
      fleet -> {:ok, fleet}
    end
  end

  defp known(fleet_id, %{proposal: number}) do
    if Proposals.get_proposal!(fleet_id, number),
      do: :ok,
      else: {:refuse, 404, "proposal_unknown"}
  end

  defp known(fleet_id, %{token_id: token_id}) do
    if Keys.current_key!(fleet_id, token_id), do: :ok, else: {:key_unknown, token_id}
  end

  defp known(_fleet_id, _params), do: :ok

  defp refuse(_flow, _built, :unread, _inputs), do: refusal(503, "chain_unavailable")
  defp refuse(_flow, _built, :not_recorded, _inputs), do: refusal(404, "proposal_unknown")
  defp refuse(:buy, _built, :not_for_sale, _inputs), do: refusal(409, "keys_not_for_sale")
  defp refuse(:buy, _built, :sold_out, _inputs), do: refusal(409, "keys_sold_out")
  defp refuse(:club_claim, _built, :not_club, _inputs), do: refusal(409, "not_club_key")

  defp refuse(:return_advance, _built, :advance_unknown, _inputs),
    do: refusal(404, "advance_unknown")

  defp refuse(:launch_upkeep, _built, :no_launch, _inputs), do: refusal(409, "no_launch")

  defp refuse(:propose, built, _problem, inputs),
    do: unreadable("invalid_proposal", WalletWords.line(:propose, built, inputs))

  defp refuse(flow, built, _problem, inputs) when flow in [:issue_shard, :agent_voting],
    do: unreadable("invalid_shard", WalletWords.line(flow, built, inputs))

  defp refuse(flow, built, _problem, inputs) when flow in [:convert, :return_advance],
    do: unreadable("invalid_amount", WalletWords.line(flow, built, inputs))

  defp unreadable(code, problem),
    do: {422, put_in(Refusal.body(code), [:error, :details], %{problem: problem}), nil}

  defp refusal(status, code), do: {status, Refusal.body(code), nil}
end
