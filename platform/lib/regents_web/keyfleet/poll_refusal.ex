defmodule RegentsWeb.Keyfleet.PollRefusal do
  @moduledoc """
  The status and `RegentsWeb.Keyfleet.Refusal` code a poll action's error answers
  with, wherever it is turned down: the agent API, the polls pages and their
  browser tools. `code` is what the action itself refuses with when the error
  says no more, such as `"not_starter"` for a poll ended by someone else.
  A Key at its daily limit also gets the seconds until it may start another.
  """

  alias Regents.Keyfleet.Polls.Errors
  alias Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError

  @invalid [
    {Errors.PollUnknownError, 404, "poll_unknown"},
    {Errors.PollClosedError, 409, "poll_closed"},
    {Errors.VoteConflictError, 409, "vote_conflict"},
    {Errors.ChoiceUnknownError, 422, "choice_unknown"}
  ]

  @doc "`{status, code}` for `error`, from an action on `fleet_id`'s polls."
  def of(%Ash.Error.Forbidden{errors: errors}, fleet_id, code) do
    cond do
      not Regents.Keyfleet.Chain.fresh?(fleet_id) -> {503, "ownership_refreshing"}
      Enum.any?(errors, &match?(%NoKeyToWriteAsError{}, &1)) -> {403, "poll_needs_key"}
      Enum.any?(errors, &match?(%Errors.AgentVotingOffError{}, &1)) -> {403, "agent_voting_off"}
      true -> {403, code}
    end
  end

  def of(%Ash.Error.Invalid{errors: errors}, _fleet_id, _code) do
    cond do
      Enum.any?(errors, &match?(%Errors.PollLimitError{}, &1)) -> {429, "poll_limit_reached"}
      found = Enum.find_value(errors, &invalid/1) -> found
      true -> {422, "invalid_poll"}
    end
  end

  def of(%Errors.PollUnknownError{} = error, fleet_id, code),
    do: of(Ash.Error.Invalid.exception(errors: [error]), fleet_id, code)

  def of(_error, _fleet_id, _code), do: {422, "invalid_poll"}

  @doc "The seconds until a Key turned down at its daily limit may start another poll, or nil."
  def retry_after(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, fn
      %Errors.PollLimitError{retry_after: seconds} -> seconds
      _other -> nil
    end)
  end

  def retry_after(_error), do: nil

  # The status and code a poll's own refusal answers with.
  defp invalid(error) do
    Enum.find_value(@invalid, fn {module, status, code} ->
      if is_struct(error, module), do: {status, code}
    end)
  end
end
