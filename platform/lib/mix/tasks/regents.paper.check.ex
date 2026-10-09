defmodule Mix.Tasks.Regents.Paper.Check do
  @shortdoc "Checks a paper folder without saving it"
  @moduledoc "Run `mix regents.paper.check ../Papers/<folder>` before uploading a paper."
  use Mix.Task

  def run([folder]) do
    Mix.Task.run("compile")

    attributes = Regents.PaperProDaily.PaperFile.read!(folder)

    changeset =
      Ash.Changeset.for_create(Regents.PaperProDaily.Paper, :put, attributes,
        actor: %Regents.Actors.System{}
      )

    unless changeset.valid?,
      do: Mix.raise(Exception.message(Ash.Error.to_error_class(changeset.errors)))

    RegentsWeb.PaperProDaily.Reading.render(attributes.answer)

    Mix.shell().info(
      "Paper Pro Daily #{attributes.date}: \"#{attributes.title}\" checked; nothing saved."
    )
  rescue
    error in [ArgumentError, File.Error] -> Mix.raise(Exception.message(error))
  end

  def run(_args), do: Mix.raise("usage: mix regents.paper.check <folder>")
end
