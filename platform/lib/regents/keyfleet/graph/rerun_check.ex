defmodule Regents.Keyfleet.Graph.RerunCheck do
  @moduledoc """
  Whether a task carries everything someone else needs to run its work again
  and compare the result: an exact commit (`commit_ref` ending in a full
  commit hash, never a branch or a short hash) and a `rerun` with its
  command, a lockfile with its digest, a role and digest for each input and
  at least one output with its digest.

  It reads only the task's own fields. It never fetches the commit, a file
  or a digest, and never installs or runs anything: a task that passes is
  complete, not proven to reproduce. That is for a review's `reproduction`
  to say.
  """

  @doc """
  What the task `data` is missing, in the order a rerun needs it, each as
  `%{field: path, need: words}`; `[]` when nothing is.
  """
  @spec missing(map()) :: [%{field: String.t(), need: String.t()}]
  def missing(data) do
    commit(data["commit_ref"]) ++ rerun(data["rerun"])
  end

  defp commit(nil), do: [need("commit_ref", "the exact commit the work is in")]

  defp commit(uri) do
    hash = Path.basename(URI.parse(uri).path || "")

    if Regents.Keyfleet.Code.full_hash?(hash),
      do: [],
      else: [need("commit_ref", "a commit's full hash, not a branch or a short hash")]
  end

  defp rerun(nil),
    do: [need("rerun", "the command, lockfile, inputs and outputs that run the work again")]

  defp rerun(rerun) do
    lockfile(rerun["lockfile"]) ++
      files("rerun.inputs", rerun["inputs"], ~w(role digest)) ++
      outputs(rerun["outputs"])
  end

  defp lockfile(nil), do: [need("rerun.lockfile", "the lockfile that pins its environment")]
  defp lockfile(%{"digest" => digest}) when is_binary(digest), do: []
  defp lockfile(_file), do: [need("rerun.lockfile.digest", "the lockfile's digest")]

  defp outputs(outputs) when outputs in [nil, []],
    do: [need("rerun.outputs", "at least one output a rerun is compared on")]

  defp outputs(outputs), do: files("rerun.outputs", outputs, ~w(digest))

  defp files(_list, nil, _wanted), do: []

  defp files(list, files, wanted) do
    for {file, index} <- Enum.with_index(files),
        field <- wanted,
        not is_binary(file[field]),
        do: need("#{list}[#{index}].#{field}", "a #{field} for #{file["path"]}")
  end

  defp need(field, words), do: %{field: field, need: words}
end
