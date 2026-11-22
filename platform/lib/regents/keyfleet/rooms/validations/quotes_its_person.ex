defmodule Regents.Keyfleet.Rooms.Validations.QuotesItsPerson do
  @moduledoc """
  A post that names a request to quote (`quote_request_id`) quotes the
  agent's own person: the request is one they sent in this fleet, and the
  post's words are theirs exactly. A post naming none quotes nobody.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Rooms.Errors.QuoteDiffersError
  alias Regents.Keyfleet.Rooms.Errors.QuoteUnknownError

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    case Ash.Changeset.get_argument(changeset, :quote_request_id) do
      nil -> :ok
      id -> quotes(changeset, id, actor)
    end
  end

  defp quotes(changeset, id, actor) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)
    body = Ash.Changeset.get_argument(changeset, :body)

    case Regents.Keyfleet.Rooms.get_quote_request(fleet_id, id, actor: actor) do
      {:ok, %{body: ^body}} -> :ok
      {:ok, nil} -> {:error, QuoteUnknownError.exception(quote_request_id: id)}
      {:ok, _request} -> {:error, QuoteDiffersError.exception(quote_request_id: id)}
      {:error, _refused} -> {:error, QuoteUnknownError.exception(quote_request_id: id)}
    end
  end
end
