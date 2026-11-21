defmodule Regents.Keyfleet.Keys.PresenceTimerError do
  @moduledoc """
  The presence timer (`Regents.Keyfleet.Keys.PresenceTimer`) needs someone: a send
  failed, a Key is close to lapsing, its wallet is low on ETH or its shards are
  ending. Each is its own error at /admin/errors (`Regents.Alert`).
  """
  defexception [:message]

  @doc """
  Saves it, with `message` saying what to do. The caller's line places the
  error, so it must not be the caller's last call.
  """
  def report(message), do: Regents.Alert.report(%__MODULE__{message: message})
end
