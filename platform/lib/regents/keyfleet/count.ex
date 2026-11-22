defmodule Regents.Keyfleet.Count do
  @moduledoc """
  A count a page shows. `Ash.count/2` hands back its own errors, but a
  database that refuses the count raises `Postgrex.Error` or
  `DBConnection.ConnectionError` instead of answering (Ash 3.33.11). Both come
  back here as `{:error, failure}`, and are logged, so the page shows that it
  couldn't count rather than crashing.
  """

  require Logger

  @spec of(Ash.Query.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def of(query) do
    with {:error, failure} <- Ash.count(query), do: failed(query, failure)
  rescue
    failure in [Postgrex.Error, DBConnection.ConnectionError] -> failed(query, failure)
  end

  defp failed(query, failure) do
    Logger.warning(
      "Counting #{inspect(query.resource)} (#{query.action.name}) failed: " <>
        Exception.message(failure)
    )

    {:error, failure}
  end
end
