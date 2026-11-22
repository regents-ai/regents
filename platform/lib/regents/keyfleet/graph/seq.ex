defmodule Regents.Keyfleet.Graph.Seq do
  @moduledoc """
  A place in a fleet's graph log: a whole number from 1 to the largest the
  database stores.

  Every value read in is held to that range, including the page positions
  readers send back, so a position past it is refused as invalid instead of
  reaching the database. What the database hands back is in range already.
  """
  use Ash.Type

  @max 9_223_372_036_854_775_807

  @impl true
  def storage_type(_constraints), do: :integer

  def migration_type(_constraints), do: :bigint

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(seq, _constraints) when is_integer(seq) and seq in 1..@max, do: {:ok, seq}
  def cast_input(_seq, _constraints), do: :error

  @impl true
  def cast_stored(seq, _constraints), do: {:ok, seq}

  @impl true
  def dump_to_native(seq, _constraints), do: {:ok, seq}
end
