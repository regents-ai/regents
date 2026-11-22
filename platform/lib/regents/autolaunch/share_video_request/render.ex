defmodule Regents.Autolaunch.ShareVideoRequest.Render do
  @moduledoc """
  Ash change that delegates share video rendering to the web-side renderer
  configured under `:regents, :autolaunch_share_video_renderer`, keeping
  `Regents.Autolaunch` free of a compile-time dependency on `RegentsWeb`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    renderer = Application.fetch_env!(:regents, :autolaunch_share_video_renderer)
    renderer.change(changeset, opts, context)
  end
end
