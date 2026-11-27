defmodule Regents.Techtree.Projects.Package do
  @moduledoc """
  Hardened in-memory reader and verifier for Techtree project archives:

  - Delivery packages (`read/1`): one gzipped tar produced by Uplift Factory
    (`uplift-package/1` for Skills, `uplift-package/2` for Evals, Environments,
    and Models), up to 128 MiB compressed / 256 MiB unpacked, one gzip stream
    with verified CRC-32/length trailer, at most 2,000 entries, plain files and
    folders inside one top-level lowercase-hyphenated directory (no links,
    devices, root paths, `..`, or duplicate paths), strict `manifest.json`
    verification, exact per-file size + SHA-256 verification, UTF-8 `report.md`
    (<= 1 MiB), and parsed `rerun/test.json` for `uplift-package/2`.
  - Intake material archives (`check_intake_archive/1`): bounded <= 5 MiB
    compressed / <= 25 MiB unpacked single-stream `.tar.gz` uploaded with a
    Factory order before `OrderBridge` claims it.
  """

  alias Regents.Techtree.Projects.Manifest

  # 128 MiB compressed / 256 MiB unpacked for 4B–8B LoRA adapter handovers.
  @max_bytes 134_217_728
  @max_unpacked 268_435_456
  @max_intake_bytes 5_242_880
  @max_intake_unpacked 26_214_400
  @max_entries 2_000
  @max_report 1_048_576
  @max_rerun_test 524_288
  @folder ~r/\A[a-z0-9-]+\z/

  @type t :: %{
          manifest: map(),
          rerun_test: map() | nil,
          report: String.t(),
          sha256: String.t(),
          size: pos_integer()
        }

  @doc "The maximum compressed size of a delivered project package, in bytes (128 MiB)."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The maximum compressed size of an order intake archive, in bytes (5 MiB)."
  @spec max_intake_bytes() :: pos_integer()
  def max_intake_bytes, do: @max_intake_bytes

  @doc "Reads and strictly verifies a delivered `uplift-package/1` or `uplift-package/2` tarball."
  @spec read(binary()) :: {:ok, t()} | {:error, String.t()}
  def read(bytes) when not is_binary(bytes), do: {:error, "The package must be binary."}

  def read(bytes) when byte_size(bytes) > @max_bytes,
    do: {:error, "The package is over 128 MB."}

  def read(bytes) do
    with {:ok, tar} <- gunzip(bytes, @max_unpacked),
         {:ok, entries} <- entries(tar),
         {:ok, folder} <- folder(entries),
         {:ok, files} <- files(tar, entries, folder),
         {:ok, json} <- fetch(files, "manifest.json"),
         {:ok, manifest} <- Manifest.parse(json),
         :ok <- listed(manifest["files"], Map.delete(files, "manifest.json")),
         {:ok, report} <- report(files["report.md"]),
         {:ok, rerun_test} <- rerun_test(manifest, files) do
      {:ok,
       %{
         manifest: manifest,
         rerun_test: rerun_test,
         report: report,
         sha256: sha256(bytes),
         size: byte_size(bytes)
       }}
    end
  end

  @doc "Validates a customer material archive uploaded with a Factory order (<= 5 MiB)."
  @spec check_intake_archive(binary()) ::
          {:ok, %{sha256: String.t(), size: pos_integer()}} | {:error, String.t()}
  def check_intake_archive(bytes) when not is_binary(bytes) or byte_size(bytes) == 0,
    do: {:error, "The material archive is empty."}

  def check_intake_archive(bytes) when byte_size(bytes) > @max_intake_bytes,
    do: {:error, "The material archive is over 5 MB."}

  def check_intake_archive(bytes) do
    with {:ok, tar} <- gunzip(bytes, @max_intake_unpacked),
         {:ok, entries} <- entries(tar),
         true <- Enum.any?(entries, fn {_path, kind} -> kind == :file end) do
      {:ok, %{sha256: sha256(bytes), size: byte_size(bytes)}}
    else
      false -> {:error, "The material archive holds no files."}
      {:error, _reason} = error -> error
    end
  end

  @doc "The sha256 of `bytes`, in lowercase hex."
  @spec sha256(binary()) :: String.t()
  def sha256(bytes), do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  defp gunzip(bytes, _max_unpacked) when byte_size(bytes) < 18,
    do: {:error, "The package isn't a gzipped file, or it is cut short."}

  defp gunzip(bytes, max_unpacked) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, 31)

      with {:ok, tar} <- inflate(z, :zlib.safeInflate(z, bytes), [], 0, max_unpacked),
           :ok <- ends_with(bytes, tar) do
        {:ok, tar}
      end
    rescue
      ErlangError -> {:error, "The package isn't a gzipped file, or it is cut short."}
    after
      :zlib.close(z)
    end
  end

  defp inflate(z, {state, out}, pieces, size, max_unpacked) do
    size = size + IO.iodata_length(out)

    cond do
      size > max_unpacked ->
        {:error, "The package unpacks past its size limit."}

      state == :finished ->
        :ok = :zlib.inflateEnd(z)
        {:ok, IO.iodata_to_binary(Enum.reverse([out | pieces]))}

      true ->
        inflate(z, :zlib.safeInflate(z, []), [out | pieces], size, max_unpacked)
    end
  end

  defp ends_with(bytes, tar) do
    crc = :erlang.crc32(tar)
    length = rem(byte_size(tar), 4_294_967_296)

    case binary_part(bytes, byte_size(bytes), -8) do
      <<^crc::little-32, ^length::little-32>> -> :ok
      _more -> {:error, "The package has more after the end of its gzip stream."}
    end
  end

  defp entries(tar) do
    case :erl_tar.table({:binary, tar}, [:verbose]) do
      {:ok, entries} when length(entries) > @max_entries ->
        {:error, "The package holds more than 2,000 entries."}

      {:ok, entries} ->
        Enum.reduce_while(entries, {:ok, %{}}, &entry/2)

      {:error, _reason} ->
        {:error, "The package isn't a tar file."}
    end
  end

  defp entry({name, type, _size, _mtime, _mode, _uid, _gid}, {:ok, entries}) do
    with {:ok, path} <- validate_entry_path(path(name)),
         {:ok, updated} <- record_entry(entries, path, type) do
      {:cont, {:ok, updated}}
    else
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp validate_entry_path(nil),
    do: {:error, "The package holds a name that isn't UTF-8."}

  defp validate_entry_path(""), do: {:ok, ""}

  defp validate_entry_path(path) do
    cond do
      String.starts_with?(path, "/") ->
        {:error, "The package holds #{path}, a path from the root of a disk."}

      String.contains?(path, "\\") ->
        {:error, "The package holds #{path}, which uses a backslash."}

      ".." in String.split(path, "/") ->
        {:error, "The package holds #{path}, a path that leaves the package."}

      true ->
        {:ok, path}
    end
  end

  defp record_entry(entries, "", _type), do: {:ok, entries}
  defp record_entry(entries, path, :directory), do: {:ok, Map.put(entries, path, :folder)}

  defp record_entry(_entries, path, type) when type in [:symlink, :hard_link],
    do: {:error, "The package holds a link, #{path}. Only files are allowed."}

  defp record_entry(_entries, path, type) when type != :regular,
    do: {:error, "The package holds #{path}, which isn't a file."}

  defp record_entry(entries, path, :regular) do
    if Map.has_key?(entries, path),
      do: {:error, "The package holds #{path} twice."},
      else: {:ok, Map.put(entries, path, :file)}
  end

  defp path(name) do
    case :unicode.characters_to_binary(name) do
      path when is_binary(path) -> String.trim_trailing(path, "/")
      _not_utf8 -> nil
    end
  end

  defp folder(entries) do
    paths = entries |> Map.keys() |> Enum.sort()

    case Enum.find(paths, &(entries[&1] == :file and top(&1) == &1)) do
      nil ->
        paths |> Enum.map(&top/1) |> Enum.uniq() |> one_folder()

      loose ->
        {:error,
         "The package holds #{loose} outside a folder. Everything in it sits in one folder."}
    end
  end

  defp one_folder([]), do: {:error, "The package is empty."}

  defp one_folder([first, second | _more]) do
    {:error,
     "The package holds #{first} and #{second} at its top level. Everything in it sits in one folder."}
  end

  defp one_folder([folder]) do
    if folder =~ @folder,
      do: {:ok, folder},
      else:
        {:error,
         "The package's folder is #{folder}. Its name may use only lower-case letters, digits and hyphens."}
  end

  defp top(path), do: path |> String.split("/", parts: 2) |> hd()

  defp files(tar, entries, folder) do
    paths = for {path, :file} <- entries, into: MapSet.new(), do: path

    case :erl_tar.extract({:binary, tar}, [:memory]) do
      {:ok, files} ->
        files = Map.new(files, fn {name, bytes} -> {path(name), bytes} end)

        if MapSet.equal?(MapSet.new(Map.keys(files)), paths),
          do: {:ok, Map.new(files, fn {path, bytes} -> {inside(path, folder), bytes} end)},
          else: unreadable()

      {:error, _reason} ->
        unreadable()
    end
  end

  defp inside(path, folder), do: String.replace_prefix(path, folder <> "/", "")

  defp unreadable, do: {:error, "The package's files couldn't be read."}

  defp fetch(files, path) do
    case Map.fetch(files, path) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "The package has no #{path}."}
    end
  end

  defp listed(listed, files) do
    by_path = Map.new(listed, &{&1["path"], &1})

    cond do
      unlisted = files |> Map.keys() |> Enum.sort() |> Enum.find(&(not Map.has_key?(by_path, &1))) ->
        {:error, "The package holds #{unlisted}, which manifest.json doesn't list."}

      missing = Enum.find(listed, &(not Map.has_key?(files, &1["path"]))) ->
        {:error, "manifest.json lists #{missing["path"]}, which the package doesn't hold."}

      other = Enum.find(listed, &(byte_size(files[&1["path"]]) != &1["size_bytes"])) ->
        {:error, "#{other["path"]} isn't the size manifest.json gives."}

      other = Enum.find(listed, &(sha256(files[&1["path"]]) != &1["sha256"])) ->
        {:error, "#{other["path"]} doesn't match its sha256 in manifest.json."}

      true ->
        :ok
    end
  end

  defp report(bytes) when byte_size(bytes) > @max_report, do: {:error, "report.md is over 1 MB."}

  defp report(bytes) do
    if String.valid?(bytes), do: {:ok, bytes}, else: {:error, "report.md isn't UTF-8 text."}
  end

  defp rerun_test(%{"schema" => "uplift-package/2"}, files) do
    case Map.get(files, "rerun/test.json") do
      nil ->
        {:error, "The package has no rerun/test.json."}

      bytes when byte_size(bytes) > @max_rerun_test ->
        {:error, "rerun/test.json is over 512 KB."}

      bytes ->
        case Jason.decode(bytes) do
          {:ok, %{} = test_config} -> {:ok, test_config}
          _other -> {:error, "rerun/test.json isn't a valid JSON object."}
        end
    end
  end

  defp rerun_test(_manifest, _files), do: {:ok, nil}
end
