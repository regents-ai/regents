defmodule RegentsWeb.Autolaunch.PublicPagesHTML do
  @moduledoc "An Autolaunch written page: its committed Markdown as HTML."

  use RegentsWeb, :html

  attr :document, :any, required: true

  def show(assigns) do
    ~H"""
    <div class="fact-page document-page">{@document}</div>
    """
  end
end
