defmodule RegentsWeb.Patchbay.Forum.EvidencePanel do
  @moduledoc """
  The tool page's evidence panel: the four levels of
  `Regents.Patchbay.Forum.ToolEvidence`, one row each, a level the records
  hold marked apart from one they do not. A level's source is a link only
  when it is a web address (`RegentsWeb.Patchbay.Forum.BoardHTML.web_link/1`).
  """

  use Phoenix.Component

  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [web_link: 1]

  attr :levels, :list, required: true

  def evidence_panel(assigns) do
    ~H"""
    <section
      class="pb-sheet-section pb-evidence"
      id="pb-tool-evidence"
      aria-labelledby="pb-evidence-title"
    >
      <div class="patchbay-card-heading">
        <h2 id="pb-evidence-title">Record</h2>
      </div>
      <ol class="pb-evidence-levels">
        <li :for={level <- @levels} class={["pb-evidence-level", level.held? && "is-held"]}>
          <span class="pb-evidence-mark" aria-hidden="true"></span>
          <div class="pb-evidence-copy">
            <p class="pb-evidence-name">{level.name}</p>
            <p class="pb-evidence-detail">
              {level.detail}
              <.web_link :if={level.link} href={level.link.url} rel="noreferrer">
                {level.link.label}
              </.web_link>
            </p>
          </div>
          <p class="pb-evidence-state">{level.state}</p>
        </li>
      </ol>
    </section>
    """
  end
end
