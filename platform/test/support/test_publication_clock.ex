defmodule Regents.TestPublicationClock do
  @moduledoc false

  def utc_now do
    case Application.get_env(:regents, :test_publication_time) do
      nil ->
        DateTime.utc_now()

      {:fixed, now} ->
        now

      {:advancing, now, started_at} ->
        DateTime.add(now, System.monotonic_time(:microsecond) - started_at, :microsecond)
    end
  end

  def freeze(now), do: Application.put_env(:regents, :test_publication_time, {:fixed, now})

  def advance(now) do
    Application.put_env(
      :regents,
      :test_publication_time,
      {:advancing, now, System.monotonic_time(:microsecond)}
    )
  end

  def reset, do: Application.delete_env(:regents, :test_publication_time)
end
