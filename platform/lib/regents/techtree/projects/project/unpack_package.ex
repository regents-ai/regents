defmodule Regents.Techtree.Projects.Project.UnpackPackage do
  @moduledoc """
  Verifies a delivered `uplift-package/1` or `uplift-package/2` archive inside
  the `:deliver` action and populates every stored Project attribute solely
  from the verified bytes.
  """

  use Ash.Resource.Change

  alias Regents.Techtree.Projects.{Manifest, Package}

  @impl true
  def change(changeset, _opts, _context) do
    bytes = Ash.Changeset.get_argument(changeset, :package_bytes)
    expected_sha = Ash.Changeset.get_argument(changeset, :expected_sha256)

    with {:ok, unpacked} <- Package.read(bytes),
         :ok <- verify_expected_sha(unpacked.sha256, expected_sha) do
      stored_manifest =
        if is_map(unpacked.rerun_test),
          do: Map.put(unpacked.manifest, "rerun_test", unpacked.rerun_test),
          else: unpacked.manifest

      changeset
      |> Ash.Changeset.force_change_attribute(:title, unpacked.manifest["title"])
      |> Ash.Changeset.force_change_attribute(:line, Manifest.line(unpacked.manifest))
      |> Ash.Changeset.force_change_attribute(:verdict, Manifest.verdict(unpacked.manifest))
      |> Ash.Changeset.force_change_attribute(:manifest, stored_manifest)
      |> Ash.Changeset.force_change_attribute(:report_md, unpacked.report)
      |> Ash.Changeset.force_change_attribute(:package, bytes)
      |> Ash.Changeset.force_change_attribute(:package_sha256, unpacked.sha256)
      |> Ash.Changeset.force_change_attribute(:package_size, unpacked.size)
    else
      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :package_bytes, message: message)
    end
  end

  defp verify_expected_sha(_actual, nil), do: :ok
  defp verify_expected_sha(actual, expected) when actual == expected, do: :ok

  defp verify_expected_sha(_actual, _expected),
    do: {:error, "The package bytes do not match the declared sha256."}
end
