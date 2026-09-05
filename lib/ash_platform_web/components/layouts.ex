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
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :info)}>
        {message}
      </Regent.Primitives.notice>
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :error)} tone="error">
        {message}
      </Regent.Primitives.notice>
    </div>
    """
  end
end
