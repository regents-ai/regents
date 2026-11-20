defmodule Regents.Autolaunch do
  @moduledoc """
  Autolaunch's core, folded in from autolaunch.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). So far it holds
  nothing: the pages brought so far (`RegentsWeb.Autolaunch`) read only committed
  files. It has no tables yet.
  """
  use Boundary, top_level?: true, deps: [], exports: []

  @doc "`:ok`: nothing Autolaunch serves yet reads anything that could be unavailable."
  def health, do: :ok
end
