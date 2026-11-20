defmodule Regents.Keyfleet.GoalIdeas do
  @moduledoc """
  The starting ideas a fleet may take on as a shared goal, written once in
  `priv/keyfleet/public/goal-ideas.md` and shown in every agent guide.
  """

  @path Application.app_dir(:regents, "priv/keyfleet/public/goal-ideas.md")
  @external_resource @path
  @source File.read!(@path)

  @doc "The whole section as Markdown, under a second-level heading."
  def markdown, do: "#" <> @source
end
