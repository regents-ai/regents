defmodule RegentsWeb.Techtree.ChangelogLive do
  @moduledoc "Techtree's release notes, compiled from its committed changelog."
  use RegentsWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  alias RegentsWeb.Techtree.Layouts

  import RegentsWeb.Techtree.Components.Marketing, only: [opening: 1]

  @external_resource Application.app_dir(:regents, "priv/techtree/changelog.md")
  @html @external_resource
        |> File.read!()
        |> String.replace_prefix("# Changelog\n", "")
        |> RegentBlog.markdown()
        |> elem(0)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Changelog", changelog_html: @html)}
  end

  @impl true
  # @html is rendered from the committed changelog at compile time, never request data.
  # sobelow_skip ["XSS.Raw"]
  def render(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening
        eyebrow="News"
        title="Changelog"
        line="What changed, what you can use, and what comes next."
        shape={5}
        icon="newspaper"
      >
        <:actions>
          <.link navigate={~p"/techtree/docs/install"} class="rg-button rg-button--primary">
            Install
          </.link>
        </:actions>
      </.opening>
      <section class="mk-section">
        <article id="changelog" class="rg-blog__prose" aria-label="Release history">
          {raw(@changelog_html)}
        </article>
      </section>
    </Layouts.page>
    """
  end
end
