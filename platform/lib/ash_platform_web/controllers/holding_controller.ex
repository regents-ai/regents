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
    <Regent.Structure.frame class="rl-root">
      <main class="rl-hero rg-inset">
        <div class="rl-hero-copy">
          <p class="rl-overline">Regents Labs</p>
          <h1 class="rg-hero-title">Not open yet</h1>
          <p>
            This part of Regent isn't open to visitors yet. Everything we have shown so far
            is on the homepage.
          </p>
          <div class="rl-hero-actions">
            <a href={~p"/"} class="rg-button"><span class="rg-button__label">Go to the homepage</span></a>
          </div>
        </div>
      </main>
    </Regent.Structure.frame>
    """
  end
end
