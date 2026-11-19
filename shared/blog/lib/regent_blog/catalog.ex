defmodule RegentBlog.Catalog do
  @moduledoc "Compile a product-owned blog directory into a release-safe catalog."
  defmacro __using__(opts) do
    quote do
      @blog_root unquote(Keyword.fetch!(opts, :root))
      @blog_paths RegentBlog.paths(@blog_root)
      for path <- @blog_paths, do: @external_resource(path)
      @blog_posts RegentBlog.load!(@blog_root)

      def all, do: RegentBlog.published(@blog_posts)
      def get(slug) when is_binary(slug), do: Enum.find(all(), &(&1.slug == slug))
      def get(_), do: nil
      def __mix_recompile__?, do: RegentBlog.paths(@blog_root) != @blog_paths
    end
  end
end
