defmodule Regents.Techtree.Release do
  @moduledoc """
  Techtree's release commands. `Regents.Release` runs each on the release login,
  with only the database connection started.

  Importing the catalog and moving the pointer that selects the published
  installation contract are separate commands on purpose: booting the site never
  imports and never republishes anything (spec section 8.10), so a release that
  starts is a release serving exactly what it was serving before.
  """

  alias Regents.Techtree.Catalog.Error
  alias Regents.Techtree.Catalog.Publication

  @doc """
  Import and activate the immutable catalog snapshot for a full source revision.
  """
  @spec import_catalog(String.t()) :: :ok
  def import_catalog(revision) do
    path =
      case Regents.Techtree.Catalog.snapshot_path(revision) do
        {:ok, path} -> path
        {:error, error} -> raise error
      end

    release = Regents.Techtree.Catalog.Importer.import!(path)

    IO.puts("imported catalog #{release.catalog_digest} on channel #{release.channel}")
    :ok
  end

  @doc """
  Publish one already-staged bootstrap release on its channel.

  This is the rollback command: releases are immutable, and which one a channel
  publishes is a pointer. Moving it forward and moving it back are the same
  operation, and neither deletes, rewrites, or reaches anything a participant
  holds locally.
  """
  @spec publish_bootstrap(String.t(), String.t() | nil) :: :ok
  def publish_bootstrap(digest, channel \\ nil) do
    case Publication.publish(digest, channel: channel) do
      {:ok, switch} ->
        IO.puts("""
        channel #{switch.channel}
        published #{switch.published}
        previously #{switch.previous || "nothing"}\
        """)

        :ok

      {:error, %Error{} = error} ->
        IO.puts(:stderr, Error.summary(error))
        exit({:shutdown, 1})
    end
  end

  @doc """
  Every bootstrap release a channel has staged, newest first, marking the one it
  publishes now.
  """
  @spec list_bootstrap_releases(String.t() | nil) :: :ok
  def list_bootstrap_releases(channel \\ nil) do
    [channel: channel]
    |> Publication.list()
    |> Enum.each(fn release ->
      IO.puts(
        "#{marker(release)} #{release.payload_digest} #{release.published_at} " <>
          "cli #{release.cli_version} plugin #{release.plugin_revision}"
      )
    end)
  end

  defp marker(%{active: true}), do: "*"
  defp marker(%{active: false}), do: " "
end
