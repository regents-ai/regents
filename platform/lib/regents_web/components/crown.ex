defmodule RegentsWeb.Components.Crown do
  @moduledoc """
  The glass crown: thirteen cubes and three beams of light, drawn behind the
  stage it decorates.

  The server renders a still picture, and that picture is the whole crown
  wherever it cannot be drawn live: no WebGPU, no JavaScript, or a visitor who
  asked for less motion. Where it can, the `Crown` hook draws it on the canvas
  and the still picture steps aside.

  Put it first inside a positioned stage. It fills that stage, sits behind what
  follows it and takes no pointer events; the pointer over the stage turns it.
  `:look` names one of the looks in `assets/js/crown_looks.ts`, and a new name
  restyles the crown already on screen.
  """

  use Phoenix.Component
  use RegentsWeb, :verified_routes

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :look, :string, required: true

  def crown(assigns) do
    ~H"""
    <div
      id={@id}
      class="crown"
      phx-hook="Crown"
      phx-mounted={JS.ignore_attributes(["data-crown-ready"])}
      data-crown-look={@look}
      aria-hidden="true"
    >
      <img
        class="crown__still"
        src={~p"/images/home/hero-bg-dark.svg"}
        width="1700"
        height="1200"
        alt=""
        fetchpriority="high"
      />
      <canvas id={"#{@id}-canvas"} phx-update="ignore" data-crown-canvas></canvas>
    </div>
    """
  end
end
