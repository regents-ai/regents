defmodule AshPlatformWeb.Layouts do
  @moduledoc "Root document layout for the public page and persistent shell."

  use AshPlatformWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :inner_content, :any, required: true

  def app(assigns) do
    ~H"""
    {@inner_content}
    <div id="flash-region" aria-live="polite">
      <p :if={message = Phoenix.Flash.get(@flash, :info)} role="status">{message}</p>
      <p :if={message = Phoenix.Flash.get(@flash, :error)} role="alert">{message}</p>
    </div>
    """
  end
end
