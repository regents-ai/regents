defmodule RegentsWeb.Techtree.BlogHTML do
  @moduledoc """
  Techtree's blog: its list of posts under the marketing opening band, and each
  post and the missing-post page in the design system's blog layout.
  """
  use RegentsWeb, :html

  import RegentsWeb.Techtree.Components.Marketing, only: [opening: 1]

  alias RegentsWeb.Techtree.Layouts

  def index(assigns) do
    ~H"""
    <Layouts.page wide flush>
      <.opening
        eyebrow="News"
        title="Blog"
        line="Findings from our own tests."
        shape={0}
        icon="pen-line"
      >
        <:actions>
          <a href={~p"/techtree/changelog"} class="rg-button rg-button--primary">Changelog</a>
        </:actions>
      </.opening>
      <section class="mk-section" aria-label="Posts">
        <ul class="mk-news mk-news--posts">
          <li :for={post <- @posts}>
            <a href={~p"/techtree/blog/#{post.slug}"} class="mk-news__card">
              <img
                class="mk-news__picture"
                src={post.image}
                alt={post.image_alt}
                width="1600"
                height="900"
                loading="lazy"
                decoding="async"
              />
              <span class="mk-news__meta">
                <span>{post.author}</span>
                <time datetime={Date.to_iso8601(post.date)}>
                  {Calendar.strftime(post.date, "%-d %b %Y")}
                </time>
              </span>
              <h2 class="mk-news__title">{post.title}</h2>
              <span :if={post.description != ""} class="mk-news__line">{post.description}</span>
              <span class="mk-news__more">Read <Regent.Icons.icon name="arrow-right" /></span>
            </a>
          </li>
        </ul>
      </section>
    </Layouts.page>
    """
  end

  def show(assigns), do: page(Map.put(assigns, :view, :show))
  def not_found(assigns), do: page(Map.put(assigns, :view, :not_found))

  defp page(assigns) do
    ~H"""
    <Layouts.page wide>
      <Regent.Blog.article :if={@view == :show} post={@post} name="Blog" path="/techtree/blog" />
      <Regent.Blog.not_found :if={@view == :not_found} name="Blog" path="/techtree/blog" />
    </Layouts.page>
    """
  end
end
