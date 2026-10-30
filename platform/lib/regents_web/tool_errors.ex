defmodule RegentsWeb.ToolErrors do
  @moduledoc """
  What a hosted MCP tool says when its action refuses: the JSON the same refusal
  answers over HTTP, `{"error": {"code", "message", "hint"}}`, as the tool error's
  text (`AshAi.ToToolError`). A paired agent's read takes the agent API's words
  (`RegentsWeb.AgentReadsController.refusal/1`); a connected app's identity
  refusal takes the site's own code and words, the library's
  `too_many_requests` with `retry_after` when it was asked to wait, or, when no
  answer came, the words every Regent site gives it.

  Input a tool's action cannot take is refused before AshAi runs it
  (`check_input/3`, the server's `tool_argument_transformer`), with the code the
  same input gets over HTTP: a Credits history read's `invalid_cursor`, a
  pairing's `invalid_request` in the library's words
  (`RegentMCPAgents.pairing_input_refusal/0`), and another identity tool's
  `identity_request_refused`. A read's input that is not an object (null
  included), or names an input the read has not, is `invalid_input`. As AshAi reads it, a call without
  `input` sends none, which is how a tool listed with no inputs is called.
  """

  alias Regents.Agents.AccountReads
  alias RegentsWeb.AgentReadsController

  @doc """
  Casts a hosted tool's `input` as its action takes it. Input it takes goes on to
  AshAi unchanged; any other is refused as `{:error, text}` with the HTTP code.
  """
  @spec check_input(AshAi.Tool.t(), term(), map()) :: {:ok, term()} | {:error, String.t()}
  # The action would take a null cursor as none; HTTP refuses it.
  def check_input(
        %AshAi.Tool{resource: AccountReads, action: %{name: :credits_history}},
        %{"input" => %{"after" => nil}},
        _context
      ),
      do: {:error, read("invalid_cursor")}

  def check_input(%AshAi.Tool{resource: resource, action: %{name: action}}, arguments, _context) do
    with %{} <- arguments,
         %{} = input <- Map.get(arguments, "input", %{}),
         %{valid?: true} <- Ash.ActionInput.for_action(resource, action, input) do
      {:ok, arguments}
    else
      %Ash.ActionInput{errors: errors} -> {:error, refused(resource, action, errors)}
      _not_an_object -> {:error, refused(resource, action, [])}
    end
  end

  defp refused(AccountReads, _read, errors),
    do:
      read(
        if(Enum.any?(errors, &match?(%{field: :after}, &1)),
          do: "invalid_cursor",
          else: "invalid_input"
        )
      )

  defp refused(_identity, :pair_identity, _errors),
    do: Jason.encode!(%{error: RegentMCPAgents.pairing_input_refusal()})

  defp refused(_identity, _action, _errors), do: Jason.encode!(RegentMCPAgents.Tools.refusal())

  @doc "A paired agent's read refusal `code`, as a tool error's text."
  @spec read(String.t()) :: String.t()
  def read(code) do
    {_status, body} = AgentReadsController.refusal(code)
    Jason.encode!(body)
  end
end

defimpl AshAi.ToToolError, for: Regents.Agents.AccountReads.Refused do
  def to_tool_error(%{code: code}), do: RegentsWeb.ToolErrors.read(code)
end

defimpl AshAi.ToToolError, for: Regents.Agents.Connection.Refused do
  def to_tool_error(%{error: %{} = error, retry_after: retry_after}),
    do: Jason.encode!(%{error: with_retry(error, retry_after)})

  def to_tool_error(%{wait: seconds}) when is_integer(seconds) do
    %{error: error} = RegentMCPAgents.Tools.wait(seconds)
    Jason.encode!(%{error: Map.put(error, :retry_after, seconds)})
  end

  def to_tool_error(_no_answer), do: Jason.encode!(RegentMCPAgents.Tools.refusal())

  defp with_retry(error, retry_after) when is_binary(retry_after) do
    case Integer.parse(retry_after) do
      {seconds, ""} -> Map.put(error, "retry_after", seconds)
      _not_seconds -> error
    end
  end

  defp with_retry(error, _none), do: error
end
