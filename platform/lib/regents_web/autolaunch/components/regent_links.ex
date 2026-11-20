defmodule RegentsWeb.Autolaunch.Components.RegentLinks do
  @moduledoc "The footer's X and GitHub links."
  use Phoenix.Component

  import RegentsWeb.Autolaunch.Components.LinkIcon

  def social_links(assigns) do
    ~H"""
    <nav class="regent-social-links" aria-label="Regents social links">
      <a
        href="https://x.com/regents_sh"
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Regents on X"
      >
        <.link_icon kind={:x} />
      </a>
      <a
        href="https://github.com/regents-ai"
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Regents on GitHub"
      >
        <.link_icon kind={:github} />
      </a>
    </nav>
    """
  end
end
