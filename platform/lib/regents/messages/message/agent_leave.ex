defmodule Regents.Messages.Message.AgentLeave do
  @moduledoc """
  A paired agent's message: `%{receipt: Message.receipt/1, replayed: boolean}`.

  The agent's `operation_id` names one message (the `agent_operation` identity).
  A reuse with the same topic, text and reply_to answers that message's receipt
  (`replayed: true`) and leaves nothing; a reuse with any other is refused as
  `idempotency_conflict`. Of two calls with one key at once, the second's write
  meets the identity, finds the first's message, and answers as a reuse.

  Every caller passes the client address tag as `context: %{client_key: tag}`,
  which the message's allowance counts (`SpendAllowance`).
  """

  use Ash.Resource.Actions.Implementation

  alias Regents.Actors.{Agent, System}
  alias Regents.Messages
  alias Regents.Messages.{Message, Refused}

  @impl true
  def run(input, _opts, %{actor: %Agent{} = actor}) do
    %{operation_id: key} = arguments = input.arguments
    wallet = String.downcase(actor.wallet_address)

    case left(wallet, key) do
      {:ok, nil} -> leave(arguments, wallet, key, actor, input.context)
      {:ok, message} -> reuse(message, arguments)
      {:error, error} -> {:error, error}
    end
  end

  defp leave(arguments, wallet, key, actor, context) do
    Message
    |> Ash.Changeset.for_create(:leave, Map.take(arguments, [:topic, :body, :reply_to]),
      actor: actor,
      context: %{client_key: Map.fetch!(context, :client_key)}
    )
    |> Ash.Changeset.force_change_attribute(:operation_id, key)
    |> Ash.create()
    |> case do
      {:ok, message} ->
        {:ok, %{receipt: Message.receipt(message), replayed: false}}

      # A call with the same key may have written first while this one ran.
      {:error, error} ->
        case left(wallet, key) do
          {:ok, %Message{} = message} -> reuse(message, arguments)
          _none -> {:error, error}
        end
    end
  end

  defp left(wallet, key), do: Messages.get_agent_message(wallet, key, actor: %System{})

  defp reuse(message, arguments) do
    if {message.topic, message.body, message.reply_to} ==
         {arguments.topic, arguments.body, arguments[:reply_to]},
       do: {:ok, %{receipt: Message.receipt(message), replayed: true}},
       else: {:error, Refused.exception(code: "idempotency_conflict")}
  end
end
