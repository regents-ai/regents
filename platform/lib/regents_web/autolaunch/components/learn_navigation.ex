defmodule RegentsWeb.Autolaunch.Components.LearnNavigation do
  @moduledoc """
  The same Learn heading and links on every Learn page, in autolaunch.sh's
  order, each once its page is here. Privacy and Terms are the site's own.
  """
  use RegentsWeb, :html

  attr :current_path, :string, required: true

  def navigation(assigns) do
    assigns = assign(assigns, :pages, pages())

    ~H"""
    <header :if={learn?(@pages, @current_path)} class="learn-navigation">
      <p class="learn-navigation__title">Learn</p>
      <nav aria-label="Learn pages">
        <a
          :for={{label, path} <- @pages}
          href={path}
          aria-current={if current?(@current_path, path), do: "page"}
        >
          {label}
        </a>
      </nav>
    </header>
    """
  end

  defp pages do
    [
      {"How it works", ~p"/autolaunch/how-it-works"},
      {"About", ~p"/autolaunch/about"},
      {"Changelog", ~p"/autolaunch/changelog"},
      {"Privacy", ~p"/privacy"},
      {"Terms", ~p"/terms"}
    ]
  end

  defp learn?(pages, path), do: Enum.any?(pages, fn {_label, page} -> current?(path, page) end)
  defp current?(path, page), do: path == page or String.starts_with?(path, page <> "/")
end
