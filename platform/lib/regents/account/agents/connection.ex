defmodule Regents.Account.Agents.Connection do
  @moduledoc """
  The one Regents identity an app keeps when a person connects it to their
  account here, such as Claude: the identity tools of the unified hosted MCP
  server at `/mcp`.
  """

  use Ash.Resource,
    domain: Regents.Account.Agents,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Account.Actors.{Agent, ConnectedApp}
  alias Regents.Account.Agents.Connection.{Caller, Refused}

  actions do
    action :register_identity, :map do
      description "Prepares the connection's identity for the account its token names."
      run fn _input, context -> answer(RegentMCPAgents.register(principal(context))) end
    end

    action :get_identity, :map do
      description "Reads whether the connection's identity is paired."
      run fn _input, context -> answer(RegentMCPAgents.status(principal(context))) end
    end

    action :pair_identity, :map do
      description "Pairs the connection's identity with the account's own pairing code."

      argument :code, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 128, trim?: false],
        description: "Your person's one-use pairing code, 1 to 128 characters."

      argument :name, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 100, trim?: false],
        description: "The name your person will see for you, 1 to 100 characters."

      argument :harness, :atom,
        allow_nil?: false,
        constraints: [one_of: [:claude]],
        description: "The app you are."

      run fn %{arguments: %{code: code, name: name, harness: harness}}, context ->
        args = %{"code" => code, "name" => name, "harness" => Atom.to_string(harness)}
        answer(RegentMCPAgents.pair(principal(context), args))
      end
    end

    action :check_in, :map do
      description "Checks in as the paired identity and reads the account it is paired with."
      run fn _input, context -> answer(RegentMCPAgents.check_in(principal(context))) end
    end
  end

  policies do
    policy always() do
      authorize_if Caller
    end
  end

  defp principal(%{actor: %ConnectedApp{principal: principal}}), do: principal
  defp principal(%{actor: %Agent{connection: %{} = principal}}), do: principal

  defp answer({:ok, answer}), do: {:ok, answer}

  defp answer({:answer, _status, %{"error" => %{} = error}, retry_after}),
    do: {:error, Refused.exception(error: error, retry_after: retry_after)}

  defp answer({:refused, _status, error}), do: {:error, Refused.exception(error: error)}
  defp answer({:error, {:rate_limited, seconds}}), do: {:error, Refused.exception(wait: seconds)}
  defp answer(_no_answer), do: {:error, Refused.exception([])}
end
