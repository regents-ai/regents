defmodule RegentsWeb.Autolaunch.ToolErrors do
  @moduledoc """
  What a hosted MCP tool says when its action refuses: the JSON the same refusal
  answers over HTTP, `{"error": {"code", "message", "hint"}}`, as the tool error's
  text (`AshAi.ToToolError`). A connected app's identity refusal takes the site's
  own code and words, the library's `too_many_requests` with `retry_after` when
  it was asked to wait, or, when no answer came, the words every Regent site
  gives it. A covered-call refusal takes the covered-call routes' code and words
  (`RegentsWeb.Autolaunch.CoveredCallsAnswer.body/1`), an Earn refusal the Earn
  routes' (`RegentsWeb.Autolaunch.EarnAnswer.body/1`), an agent bid's refusal the
  agent bid routes' (`RegentsWeb.Autolaunch.AgentBidAnswer.body/1`), an agent
  Robinhood bid's the agent Robinhood bid routes'
  (`RegentsWeb.Autolaunch.AgentRobinhoodBidAnswer.body/1`), an agent launch's the
  agent launch route's (`RegentsWeb.Autolaunch.AgentLaunchAnswer.body/1`), an agent
  finish's the agent finish route's (`RegentsWeb.Autolaunch.AgentFinishAnswer.body/1`),
  and an agent staking action's the agent staking route's
  (`RegentsWeb.Autolaunch.AgentStakeAnswer.body/1`). Every other tool's
  refusal is its route's own (`RegentsWeb.Autolaunch.Refusal`). A failure nobody expected answers
  `internal_error`, as the API does, and is logged by kind alone
  (`Regents.Autolaunch.ReadFailure`).

  Input a tool's action cannot take is refused before AshAi runs it
  (`check_input/3`, the server's `tool_argument_transformer`), with the code the
  same input gets over HTTP: a bid estimate's own route's answer to the same
  body (`invalid_amount` for an amount that is not text, as there), the other
  market reads', the covered calls', Exposure's, Earn's, agent bids', agent
  Robinhood bids', agent launches', agent finishes' and agent staking's
  `invalid_request`, each in its own route's words, a draft save's
  `invalid_draft`, a pairing's
  `invalid_request` in the library's words
  (`RegentMCPAgents.pairing_input_refusal/0`), and another identity tool's
  `identity_request_refused`. As AshAi reads it, a call without `input` sends
  none, which is how a tool listed with no inputs is called; an `input` that is
  not an object, `null` and `false` included, is refused like any other, and so
  is a value of another JSON type than its input takes (the text `"1"` for a
  whole number or `"true"` for true or false, `null` for a text), as the routes
  refuse it: nothing is cast.
  """

  alias Regents.Autolaunch.{AgentPayment, AgentSwap}
  alias RegentsWeb.Autolaunch.{AccountAnswer, Refusal}
  alias RegentsWeb.Autolaunch.AgentTools.{Account, Market}
  alias RegentsWeb.Autolaunch.{ApiError, ExposureAnswer, MarketAnswer}

  @doc """
  Casts a hosted tool's `input` as its action takes it. Input it takes goes on to
  AshAi unchanged; any other is refused as `{:error, text}` with the HTTP code.
  """
  @spec check_input(AshAi.Tool.t(), term(), map()) :: {:ok, term()} | {:error, String.t()}
  def check_input(
        %AshAi.Tool{resource: resource, action: %{name: action, arguments: taken}},
        arguments,
        _context
      ) do
    with {:ok, input} <- input(arguments),
         true <- valid_fields?(input, taken, resource, action),
         %{valid?: true} <- Ash.ActionInput.for_action(resource, action, input) do
      {:ok, arguments}
    else
      _not_taken -> {:error, refused(resource, action, arguments)}
    end
  end

  defp input(%{"input" => %{} = input}), do: {:ok, input}
  defp input(%{} = arguments) when not is_map_key(arguments, "input"), do: {:ok, %{}}
  defp input(_not_an_object), do: :error

  defp valid_fields?(input, arguments, resource, action) do
    strict? =
      resource in [
        Account,
        AgentSwap,
        AgentPayment,
        Market,
        RegentsWeb.AgentTools.Public,
        RegentsWeb.AgentTools.Account,
        RegentsWeb.Techtree.AgentTools.Public,
        RegentsWeb.Techtree.AgentTools.Account,
        RegentsWeb.Patchbay.AgentTools.Forum
      ] or
        action == :read_offer_campaign

    Enum.all?(input, &typed?(&1, arguments, strict?))
  end

  # Each value given has the JSON type its argument takes; a name the action does
  # not take is refused by the action itself.
  defp typed?({name, value}, taken, strict?) do
    case Enum.find(taken, &(Atom.to_string(&1.name) == name)) do
      nil -> not strict?
      %{type: type} -> json_type?(type, value)
    end
  end

  defp json_type?(Ash.Type.Integer, value), do: is_integer(value)
  defp json_type?(Ash.Type.String, value), do: is_binary(value)
  defp json_type?(Ash.Type.Atom, value), do: is_binary(value)
  defp json_type?(Ash.Type.UUID, value), do: is_binary(value)
  defp json_type?(Ash.Type.Boolean, value), do: is_boolean(value)
  # Any other type is the action's own cast to refuse.
  defp json_type?(_type, _value), do: true

  # Use the same refusal as the quote route without loading an auction.
  defp refused(Market, :bid_quote_answer, %{"input" => %{"amount" => amount}})
       when not is_binary(amount),
       do: text(MarketAnswer.invalid_decimal("invalid_amount", "amount"))

  defp refused(Market, :bid_quote_answer, %{"input" => %{"max_price" => price}})
       when not is_binary(price),
       do: text(MarketAnswer.invalid_decimal("invalid_max_price", "max_price"))

  defp refused(resource, action, _arguments), do: refused(resource, action)

  defp refused(Regents.Autolaunch.Earn.Product, _earn),
    do: Jason.encode!(RegentsWeb.Autolaunch.EarnAnswer.body(:invalid_request))

  defp refused(Regents.Autolaunch.AgentBid, _bid),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentBidAnswer.body(:invalid_request))

  defp refused(Regents.Autolaunch.AgentRobinhoodBid, _bid),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentRobinhoodBidAnswer.body(:invalid_request))

  defp refused(Regents.Autolaunch.AgentLaunch, _launch),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentLaunchAnswer.body(:invalid_request))

  defp refused(Regents.Autolaunch.AgentFinish, _finish),
    do:
      Jason.encode!(
        RegentsWeb.Autolaunch.AgentFinishAnswer.body(
          Regents.Autolaunch.AgentFinish.Refused.exception(reason: :invalid_request)
        )
      )

  defp refused(Regents.Autolaunch.AgentStake, _stake),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentStakeAnswer.body(:invalid_request))

  defp refused(AgentSwap, :prepare),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentSwapAnswer.body(:invalid_request))

  defp refused(AgentPayment, :prepare),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentPaymentAnswer.body(:invalid_request))

  defp refused(_resource, covered_call)
       when covered_call in [:book_answer, :quote, :positions_answer, :prepare_answer],
       do: Jason.encode!(RegentsWeb.Autolaunch.CoveredCallsAnswer.body(:invalid_request))

  defp refused(Regents.Autolaunch.Exposure.Series, _exposure),
    do: text(ExposureAnswer.refusal(:invalid_request))

  defp refused(Market, :treasury_answer),
    do: text(MarketAnswer.invalid_treasury())

  defp refused(Account, save)
       when save in [:revstake_draft_save, :memestock_draft_save],
       do: text(AccountAnswer.invalid_draft())

  defp refused(_resource, read)
       when read in [
              :counts,
              :counts_answer,
              :auctions_answer,
              :auction_answer,
              :bid_quote_answer,
              :tokens_answer,
              :token_answer,
              :after_hour_stocks_list,
              :after_hour_stocks_series,
              :revstake_draft,
              :memestock_draft,
              :my_positions,
              :my_after_hour_stocks,
              :after_hour_stocks_prepare,
              :bid_prepare,
              :bid_settlement_prepare,
              :robinhood_bid_prepare,
              :robinhood_bid_settlement_prepare,
              :launch_prepare,
              :finish_prepare,
              :stake_prepare,
              :points
            ],
       do: text(MarketAnswer.invalid_query())

  defp refused(resource, action)
       when resource in [RegentsWeb.AgentTools.Public, RegentsWeb.AgentTools.Account] do
    Jason.encode!(
      ApiError.body(
        "invalid_request",
        "The Regents tool received invalid input.",
        "Use the inputs in the hosted tool schema for #{action}."
      )
    )
  end

  defp refused(resource, action)
       when resource in [
              RegentsWeb.Techtree.AgentTools.Public,
              RegentsWeb.Techtree.AgentTools.Account
            ] do
    Jason.encode!(
      ApiError.body(
        "invalid_request",
        "The Techtree tool received invalid input.",
        "Use the inputs in the hosted tool schema for #{action}."
      )
    )
  end

  defp refused(_resource, :read_offer_campaign) do
    Jason.encode!(
      ApiError.body(
        "invalid_request",
        "A campaign ID is required.",
        "Use the 0x-prefixed lowercase campaign ID from a paid offer."
      )
    )
  end

  defp refused(RegentsWeb.Patchbay.AgentTools.Forum, action) do
    Jason.encode!(
      ApiError.body(
        "invalid_request",
        "The Patchbay tool received invalid input.",
        "Use the inputs in the hosted tool schema for #{action}."
      )
    )
  end

  defp refused(_resource, :pair_identity),
    do: Jason.encode!(%{error: RegentMCPAgents.pairing_input_refusal()})

  defp refused(_resource, _identity), do: Jason.encode!(RegentMCPAgents.Tools.refusal())

  defp text({:error, refusal}), do: text(refusal)

  defp text(%Refusal{code: code, message: message, hint: hint}),
    do: Jason.encode!(ApiError.body(code, message, hint))
end

defimpl AshAi.ToToolError, for: Regents.Account.Agents.Connection.Refused do
  def to_tool_error(%{error: %{} = error, retry_after: retry_after}) do
    body = if retry_after, do: %{error: error, retry_after: retry_after}, else: %{error: error}
    Jason.encode!(body)
  end

  def to_tool_error(%{wait: seconds}) when is_integer(seconds),
    do: Jason.encode!(RegentMCPAgents.Tools.wait(seconds))

  def to_tool_error(_refused), do: Jason.encode!(RegentMCPAgents.Tools.refusal())
end

defimpl AshAi.ToToolError, for: RegentsWeb.Autolaunch.Refusal do
  def to_tool_error(%{code: code, message: message, hint: hint}),
    do: Jason.encode!(RegentsWeb.Autolaunch.ApiError.body(code, message, hint))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.CoveredCalls.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.CoveredCallsAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.Earn.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.EarnAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentBid.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentBidAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentRobinhoodBid.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentRobinhoodBidAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentLaunch.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentLaunchAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentFinish.Refused do
  def to_tool_error(refused),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentFinishAnswer.body(refused))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentStake.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentStakeAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentSwap.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentSwapAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Regents.Autolaunch.AgentPayment.Refused do
  def to_tool_error(%{reason: reason}),
    do: Jason.encode!(RegentsWeb.Autolaunch.AgentPaymentAnswer.body(reason))
end

defimpl AshAi.ToToolError, for: Ash.Error.Unknown.UnknownError do
  def to_tool_error(error) do
    Regents.Autolaunch.ReadFailure.log("hosted tool", error)

    Jason.encode!(
      RegentsWeb.Autolaunch.ApiError.body("internal_error", "The request could not be completed.")
    )
  end
end
