defmodule AshPlatformWeb.HoldingController do
  @moduledoc "Renders the page shown where a product area is not open yet."

  use AshPlatformWeb, :controller

  def show(conn, _params), do: render(conn, :show, page_title: "Not open yet")
end

defmodule AshPlatformWeb.HoldingHTML do
  @moduledoc false

  use AshPlatformWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root">
      <main class="rl-hero">
        <div class="rl-hero-copy">
          <p class="rl-overline">Regents Labs</p>
          <h1>Not open yet</h1>
          <p>
            This part of Regent isn't open to visitors yet. Everything we have shown so far
            is on the homepage.
          </p>
          <div class="rl-hero-actions">
            <a href={~p"/"} class="rl-action rl-action--strong">Go to the homepage</a>
          </div>
        </div>
      </main>
    </div>
    """
  end
end
