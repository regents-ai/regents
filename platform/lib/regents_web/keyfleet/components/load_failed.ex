defmodule RegentsWeb.Keyfleet.Components.LoadFailed do
  @moduledoc """
  What a page shows in place of what it couldn't read: a heading saying so, a
  line on what to do, and two ways on. "Try again" loads the address on show
  afresh, so it works even after the page has lost its connection; the
  homepage is the way out.
  """
  use RegentsWeb, :html

  def load_failed(assigns) do
    ~H"""
    <h2>This page couldn’t be loaded</h2>
    <p>Something went wrong on our side. Try again in a moment.</p>
    <p class="load-failed__actions">
      <a href="" class="rg-button rg-button--primary">Try again</a>
      <a href="/" class="rg-button rg-button--secondary">Go to the homepage</a>
    </p>
    """
  end
end
