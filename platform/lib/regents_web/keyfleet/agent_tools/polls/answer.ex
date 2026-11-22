defmodule RegentsWeb.Keyfleet.AgentTools.Polls.Answer do
  @moduledoc """
  What a fleet's polls (`Regents.Keyfleet.Polls`) answer an agent, the same over its
  signed requests (`RegentsWeb.Keyfleet.AgentPollController`) and as the Claude
  connector's tools (`RegentsWeb.Keyfleet.AgentTools.Polls`): listing and reading
  them, starting one, voting, and ending one the agent's Key started. Each
  answer is `{status, body, retry_after}`, with `retry_after` in seconds or
  nil; `params` is the signed request's JSON, its body with the names in its
  address (`fleet_id`, `poll_id`).

  Only an agent that is one of the fleet's members reads its polls
  (`Regents.Keyfleet.Access`, `:polls`); any other is answered `poll_needs_key`.
  Who holds which Key decides every answer, down to whether a read carries
  the Key's vote, so none is given from ownership that isn't fresh.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Errors.PollUnknownError
  alias RegentsWeb.Keyfleet.PollJSON
  alias RegentsWeb.Keyfleet.PollRefusal
  alias RegentsWeb.Keyfleet.Refusal

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) ::
          {pos_integer(), map(), pos_integer() | nil}
  def answer(op, %{"fleet_id" => fleet_id} = params, actor, _waiter) do
    cond do
      fleet_id not in Regents.Keyfleet.Fleets.catalog_ids() ->
        {404, Refusal.body("fleet_unknown"), nil}

      not Regents.Keyfleet.Chain.fresh?(fleet_id) ->
        {503, Refusal.body("ownership_refreshing"), nil}

      true ->
        run(op, params, actor)
    end
  end

  defp run(:list, %{"fleet_id" => fleet_id}, actor) do
    case Polls.list_polls(fleet_id, actor: actor, authorize_with: :error) do
      {:ok, polls} -> {200, %{polls: Enum.map(polls, &PollJSON.poll/1)}, nil}
      {:error, error} -> refuse(fleet_id, error, "poll_needs_key")
    end
  end

  defp run(:start, %{"fleet_id" => fleet_id} = params, actor) do
    input =
      params
      |> Map.take(["question", "choices", "notes", "minutes"])
      |> Map.put("fleet_id", fleet_id)

    case Polls.start_poll(input, actor: actor) do
      {:ok, poll} -> {201, %{poll: PollJSON.poll(reload(fleet_id, poll.id, actor))}, nil}
      {:error, error} -> refuse(fleet_id, error, "poll_needs_key")
    end
  end

  # A member reads the poll with its own Key's vote and, once it closes,
  # every vote.
  defp run(:show, %{"fleet_id" => fleet_id, "poll_id" => poll_id}, actor) do
    case Polls.get_poll(fleet_id, poll_id, actor: actor, authorize_with: :error) do
      {:ok, nil} ->
        refuse(fleet_id, PollUnknownError.exception(poll_id: poll_id), "poll_unknown")

      {:ok, poll} ->
        {200, Map.merge(%{poll: PollJSON.poll(poll)}, votes(fleet_id, poll_id, actor)), nil}

      {:error, error} ->
        refuse(fleet_id, error, "poll_needs_key")
    end
  end

  # A repeat of a vote already cast is answered with that vote, and the voter
  # is told nothing new was written.
  defp run(:vote, %{"fleet_id" => fleet_id, "poll_id" => poll_id} = params, actor) do
    input =
      params
      |> Map.take(["choice", "reason"])
      |> Map.merge(%{"fleet_id" => fleet_id, "poll_id" => poll_id})

    case Polls.cast_vote(input, actor: actor) do
      {:ok, vote} ->
        status = if Ash.Resource.get_metadata(vote, :upsert_skipped), do: 200, else: 201
        {status, %{vote: PollJSON.vote(vote)}, nil}

      {:error, error} ->
        refuse(fleet_id, error, "poll_needs_key")
    end
  end

  defp run(:end, %{"fleet_id" => fleet_id, "poll_id" => poll_id}, actor) do
    with {:ok, poll} <- known(fleet_id, poll_id),
         {:ok, ended} <- Polls.end_poll(poll, fleet_id, actor: actor) do
      {200, %{poll: PollJSON.poll(reload(fleet_id, ended.id, actor))}, nil}
    else
      {:error, error} -> refuse(fleet_id, error, "not_starter")
    end
  end

  # Whether the fleet has the poll at all, asked before the caller's standing
  # so a poll that isn't there is told apart from one the caller didn't start.
  defp known(fleet_id, poll_id) do
    case Polls.get_poll!(fleet_id, poll_id, actor: %System{}) do
      nil -> {:error, PollUnknownError.exception(poll_id: poll_id)}
      poll -> {:ok, poll}
    end
  end

  defp reload(fleet_id, poll_id, actor), do: Polls.get_poll!(fleet_id, poll_id, actor: actor)

  defp votes(fleet_id, poll_id, actor) do
    with {:ok, mine} <- Polls.my_vote(fleet_id, poll_id, actor: actor, authorize_with: :error),
         {:ok, votes} <-
           Polls.votes_in_poll(fleet_id, poll_id, actor: actor, authorize_with: :error) do
      %{my_vote: mine && PollJSON.vote(mine), votes: Enum.map(votes, &PollJSON.vote/1)}
    else
      {:error, %Ash.Error.Forbidden{}} -> %{}
    end
  end

  defp refuse(fleet_id, error, code) do
    {status, code} = PollRefusal.of(error, fleet_id, code)
    {status, Refusal.body(code), PollRefusal.retry_after(error)}
  end
end
