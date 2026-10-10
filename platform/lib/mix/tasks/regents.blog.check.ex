defmodule Mix.Tasks.Regents.Blog.Check do
  @shortdoc "Checks a blog folder without saving it"
  use Mix.Task

  def run([folder]) do
    Mix.Task.run("compile")
    attributes = Regents.Blog.PostFile.read!(folder)

    changeset =
      Ash.Changeset.for_create(Regents.Blog.Post, :put, attributes,
        actor: %Regents.Actors.System{}
      )

    unless changeset.valid?,
      do: Mix.raise(Exception.message(Ash.Error.to_error_class(changeset.errors)))

    RegentBlog.markdown(attributes.markdown)

    Mix.shell().info(
      "Article #{attributes.slug}: \"#{attributes.title}\" checked; nothing saved."
    )
  rescue
    error in [ArgumentError, File.Error] -> Mix.raise(Exception.message(error))
  end

  def run(_), do: Mix.raise("usage: mix regents.blog.check <folder>")
end
