defmodule RegentsWeb.AboutLive do
  @moduledoc "The About page inside the product shell: its Markdown, read as a document."

  use RegentsWeb, :html

  alias RegentsWeb.PublicDocuments

  def page(assigns) do
    ~H"""
    <div id="about-page" class="rl-root public-document">
      <article class="legal-page">
        {PublicDocuments.html(PublicDocuments.document("/about").markdown)}
      </article>
    </div>
    """
  end
end
