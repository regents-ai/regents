defmodule RegentsWeb.HoldingController do
  @moduledoc "Renders the page shown where a product area is not open yet."

  use RegentsWeb, :controller

  def show(conn, _params),
    do: render(conn, :show, RegentsWeb.PublicDocuments.page(:holding))
end

defmodule RegentsWeb.HoldingHTML do
  @moduledoc false

  use RegentsWeb, :html

  def show(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root">
      <main class="rl-hero rg-inset">
        <div class="rl-hero-copy">
          <p class="rl-overline">Regents Labs</p>
          <h1 class="rg-hero-title">Not open yet</h1>
          <p>
            This part of Regent isn't open to visitors yet. Our articles are open to read.
          </p>
          <div class="rl-hero-actions">
            <a href={~p"/articles"} class="rg-button"><span class="rg-button__label">Read the articles</span></a>
          </div>
        </div>
      </main>
    </Regent.Structure.frame>
    """
  end
end
