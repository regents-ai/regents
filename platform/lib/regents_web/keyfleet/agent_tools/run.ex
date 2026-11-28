defmodule RegentsWeb.Keyfleet.AgentTools.Run do
  @moduledoc """
  Runs an agent tool's action as the calling agent, as the signed request of
  its browser tool (`tool:`) would run: the action's input becomes that
  request's JSON, with any `fixed:` fields the browser tool always sends; its
  body is checked as the request's is; and the resource's `Answer` module
  (`RegentsWeb.Keyfleet.AgentTools.Rooms.Answer` for `RegentsWeb.Keyfleet.AgentTools.Rooms`)
  answers the action's name as it answers the request. Waits for news are
  counted under the `waiter` its caller puts in the action's context.
  """
  use Ash.Resource.Actions.Implementation

  alias RegentsWeb.Keyfleet.AgentTools.{
    Account,
    Chain,
    Code,
    Dms,
    Fleets,
    Keys,
    Notebooks,
    Polls,
    Projects,
    Public,
    Publications,
    Rooms,
    Seasons,
    SignedRequest,
    Workspace
  }

  @impl true
  def run(input, opts, context) do
    params = SignedRequest.params(input.arguments, Keyword.get(opts, :fixed, %{}))

    with :ok <- SignedRequest.check(opts[:tool], params) do
      waiter = Map.get(context.source_context, :waiter)

      SignedRequest.result(
        answer(input.resource).answer(input.action.name, params, context.actor, waiter)
      )
    end
  end

  defp answer(Account), do: Account.Answer
  defp answer(Chain), do: Chain.Answer
  defp answer(Code), do: Code.Answer
  defp answer(Dms), do: Dms.Answer
  defp answer(Fleets), do: Fleets.Answer
  defp answer(Keys), do: Keys.Answer
  defp answer(Notebooks), do: Notebooks.Answer
  defp answer(Polls), do: Polls.Answer
  defp answer(Projects), do: Projects.Answer
  defp answer(Public), do: Public.Answer
  defp answer(Publications), do: Publications.Answer
  defp answer(Rooms), do: Rooms.Answer
  defp answer(Seasons), do: Seasons.Answer
  defp answer(Workspace), do: Workspace.Answer
end
