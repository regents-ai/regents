defmodule RegentsWeb.Blog do
  @moduledoc "Public database posts projected for the shared blog components."

  def all, do: Enum.map(Regents.Blog.list_posts!(), &present/1)

  def get(slug) do
    case Regents.Blog.get_post!(slug) do
      nil ->
        nil

      post ->
        {html, toc} = RegentBlog.markdown(post.markdown)
        post |> present() |> Map.merge(%{html: html, toc: toc})
    end
  end

  defp present(post) do
    post
    |> Map.from_struct()
    |> Map.put(
      :image,
      "/blog/covers/#{post.slug}?v=#{DateTime.to_unix(post.updated_at, :microsecond)}"
    )
    |> Map.put(:image_alt, post.cover_alt)
  end
end
