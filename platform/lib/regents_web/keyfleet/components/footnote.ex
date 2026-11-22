defmodule RegentsWeb.Keyfleet.Components.Footnote do
  @moduledoc """
  A line of small print with an "i" tip at its end. The tip stays beside the
  line's last word, so on a narrow screen it never wraps onto a line alone.
  """
  use RegentsWeb, :html

  attr :class, :string, required: true
  attr :text, :string, required: true
  attr :tip_id, :string, required: true
  attr :tip_label, :string, required: true
  slot :inner_block, required: true, doc: "what the tip explains"

  def footnote(assigns) do
    {head, last} =
      case String.split(assigns.text, ~r/\s+(?=\S+$)/) do
        [head, last] -> {head <> " ", last}
        [last] -> {"", last}
      end

    assigns = assign(assigns, head: head, last: last)

    ~H"""
    <p class={@class}>
      {@head}<span class="footnote__end">{@last}
      <Regent.Primitives.tip
        id={@tip_id}
        label={@tip_label}
      >
        {render_slot(@inner_block)}
      </Regent.Primitives.tip></span>
    </p>
    """
  end
end
