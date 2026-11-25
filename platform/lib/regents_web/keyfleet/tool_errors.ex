defmodule RegentsWeb.Keyfleet.ToolErrors do
  @moduledoc """
  What a Keyfleet hosted MCP tool says when its input doesn't fit or its action
  refuses: the exact JSON its HTTP endpoint returns,
  `{"error": {"code", "message", "hint"}}` (with optional `retry_after` and
  `details`), serialized via `AshAi.ToToolError`.
  """

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Graph.Errors.ComingSoonFleetError
  alias RegentsWeb.Keyfleet.WorkspaceRefusal

  @doc "Returns `true` when `tool` belongs to Keyfleet (`RegentsWeb.Keyfleet.AgentTools` or `Regents.Keyfleet.Graph`)."
  @spec keyfleet_tool?(AshAi.Tool.t()) :: boolean()
  def keyfleet_tool?(%AshAi.Tool{domain: domain})
      when domain in [RegentsWeb.Keyfleet.AgentTools, Regents.Keyfleet.Graph],
      do: true

  def keyfleet_tool?(_tool), do: false

  @doc """
  Validates a Keyfleet MCP tool's `input` against its Ash action before AshAi
  executes it, returning `{:error, json}` in Keyfleet's HTTP refusal shape.
  """
  @spec check_input(AshAi.Tool.t(), term(), map()) :: {:ok, term()} | {:error, String.t()}
  def check_input(%AshAi.Tool{resource: resource, action: %{name: action}}, arguments, context) do
    with %{} <- arguments, %{} = input <- arguments["input"] || %{} do
      resource
      |> Ash.ActionInput.for_action(action, input,
        actor: context[:actor],
        context: Map.put(context[:context] || %{}, :input_check, true)
      )
      |> checked(arguments)
    else
      _not_an_object -> {:error, refused(resource, action, [])}
    end
  end

  defp checked(%Ash.ActionInput{resource: resource, action: %{name: action}} = input, arguments) do
    errors = if shaped?(input), do: opened(input) ++ input.errors, else: input.errors
    if errors == [], do: {:ok, arguments}, else: {:error, refused(resource, action, errors)}
  end

  defp shaped?(%Ash.ActionInput{errors: errors}),
    do: Enum.all?(errors, &WorkspaceRefusal.for_error/1)

  defp opened(%Ash.ActionInput{resource: resource} = input) do
    fleet_id = Ash.ActionInput.get_argument(input, :fleet_id)

    if Ash.Resource.Info.domain(resource) == Regents.Keyfleet.Graph and
         fleet_id in Fleets.catalog_ids() and
         Fleets.coming_soon?(fleet_id, Fleets.get_fleet!(fleet_id)),
       do: [ComingSoonFleetError.exception(fleet_id: fleet_id)],
       else: []
  end

  defp refused(resource, action, errors) do
    {_status, body} =
      Enum.find_value(errors, &WorkspaceRefusal.for_error/1) ||
        WorkspaceRefusal.refusal(422, "invalid_request")

    text(Enum.find_value(errors, body, &too_long(&1, resource, action, body)))
  end

  defp too_long(
         %Ash.Error.Action.InvalidArgument{field: field, value: value, vars: [max: max]},
         resource,
         action,
         %{error: %{code: "invalid_request"}} = body
       )
       when is_binary(value) do
    with %{constraints: constraints} <-
           Enum.find(Ash.Resource.Info.action(resource, action).arguments, &(&1.name == field)) do
      unit = constraints[:length_count] || Ash.Type.String.default_length_count()
      {size, units} = measured(value, unit)

      put_in(
        body.error.hint,
        "#{field} is at most #{max} #{units}; this one has #{size}. Send a shorter one."
      )
    end
  end

  defp too_long(_error, _resource, _action, _body), do: nil

  defp measured(value, :bytes), do: {byte_size(value), "bytes"}
  defp measured(value, :codepoints), do: {length(String.codepoints(value)), "characters"}

  @doc "`body` as a tool error's text, with `retry_after` in seconds when there is one."
  @spec text(map(), String.t() | integer() | nil) :: String.t()
  def text(%{error: error} = body, retry_after \\ nil),
    do: Jason.encode!(%{body | error: with_retry(error, retry_after)})

  defp with_retry(error, seconds) when is_integer(seconds),
    do: Map.put(error, :retry_after, seconds)

  defp with_retry(error, retry_after) when is_binary(retry_after) do
    case Integer.parse(retry_after) do
      {seconds, ""} -> Map.put(error, :retry_after, seconds)
      _not_seconds -> error
    end
  end

  defp with_retry(error, _none), do: error
end

defimpl AshAi.ToToolError,
  for: [
    Regents.Keyfleet.Graph.Errors.RefusedError,
    Regents.Keyfleet.Graph.Errors.UnknownFleetError,
    Regents.Keyfleet.Graph.Errors.ComingSoonFleetError,
    Regents.Keyfleet.Graph.Errors.NotKeyHolderError,
    Regents.Keyfleet.Graph.Errors.EditsRestrictedError,
    Regents.Keyfleet.Graph.Errors.UnavailableError,
    Regents.Keyfleet.Graph.Errors.IndeterminateError,
    Regents.Keyfleet.Graph.Errors.MembersOnlyError,
    Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError,
    Regents.Keyfleet.Projects.Errors.UnknownProjectError
  ] do
  def to_tool_error(error) do
    {_status, body} = RegentsWeb.Keyfleet.WorkspaceRefusal.for_error(error)
    RegentsWeb.Keyfleet.ToolErrors.text(body)
  end
end

defimpl AshAi.ToToolError, for: Regents.Keyfleet.Graph.Errors.WriteLimitError do
  def to_tool_error(%{retry_after: seconds} = error) do
    {_status, body} = RegentsWeb.Keyfleet.WorkspaceRefusal.for_error(error)
    RegentsWeb.Keyfleet.ToolErrors.text(body, seconds)
  end
end

defimpl AshAi.ToToolError, for: RegentsWeb.Keyfleet.AgentTools.Refused do
  def to_tool_error(%{body: body, retry_after: retry_after}),
    do: RegentsWeb.Keyfleet.ToolErrors.text(body, retry_after)
end
