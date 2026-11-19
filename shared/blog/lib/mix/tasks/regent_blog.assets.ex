defmodule Mix.Tasks.RegentBlog.Assets do
  @shortdoc "Stage local blog math and repository-owned images into the consuming product"
  use Mix.Task

  @impl Mix.Task
  def run([]) do
    source = Mix.Project.deps_paths() |> Map.fetch!(:regent_blog) |> Path.join("priv/static")
    target = Path.join(File.cwd!(), "priv/static/assets/regent-blog")
    File.mkdir_p!(target)

    for name <- ["katex.mjs", "KATEX-LICENSE.txt"],
        do: File.cp!(Path.join(source, name), Path.join(target, name))

    images = Path.expand("../blog/images", File.cwd!())
    copy_images(images, Path.join(File.cwd!(), "priv/static/images/blog"))
  end

  # Never stage raw Markdown/drafts or follow symlinks into unrelated files.
  defp copy_images(source, target) do
    if File.exists?(source) do
      case File.lstat!(source).type do
        :directory ->
          File.mkdir_p!(target)

          for name <- File.ls!(source),
              do: copy_images(Path.join(source, name), Path.join(target, name))

        :regular ->
          unless String.downcase(Path.extname(source)) in ~w(.svg .png .jpg .jpeg .webp .avif .gif),
            do: raise(ArgumentError, "unsupported blog image: #{source}")

          File.cp!(source, target)

        _ ->
          raise ArgumentError, "blog images must not be symlinks: #{source}"
      end
    end
  end
end
