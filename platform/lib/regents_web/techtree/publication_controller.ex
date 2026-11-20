defmodule RegentsWeb.Techtree.PublicationController do
  @moduledoc """
  The addresses that read the public run log back.

  A `GET` here is the log, or one entry of it, as a **verified projection**.
  Every member of it was recomputed from bytes that verified or copied out of a
  document whose signature was checked first. It is not the submitted bytes.

  Those have an address of their own, one level down: `.../bundle` answers with
  the exact document this site was handed, byte for byte. It is never parsed
  and written out again on the way, because a re-encoding would be our
  rendering of what somebody signed rather than the thing they signed, and the
  signatures inside it are checked against those bytes. A reader who wants to
  check a published run without taking our word for any of it downloads that
  and verifies it on their own machine.

  Once a participant withdraws their run, that address answers `410 Gone` and
  the entry keeps everything else it had: its place on the log, its metadata,
  the appended event that says it was withdrawn, and its receipt. Withdrawal
  stops this site from handing the bundle out; it cannot reach the copies
  somebody already has, and those go on verifying, which is what a signature is
  for.

  The list is newest first by log sequence and by nothing else, one keyset page
  at a time — `?before_sequence=…&limit=…`, twenty-five by default and at most
  a hundred. There is no sort control, no offset, and no ordering a caller
  could ask for. A **log sequence** is not a position and not a rank: it is
  handed out in arrival order and it may have gaps.

  A withdrawn entry is still on the log and still at its own address, with
  `withdrawn_at` set. It was published and it is marked withdrawn, which is a
  different thing from never having existed and a different thing from being
  gone.
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.Catalog.Digest
  alias Regents.Techtree.Network.Projection
  alias Regents.Techtree.Network.Query
  alias RegentsWeb.Techtree.ExactResponse

  # Every answer here is data, never a page, as on techtree.sh's API.
  plug :put_api_headers

  @doc """
  One page of the log, newest arrival first.
  """
  def index(conn, params) do
    case Query.read_page_options(params) do
      {:ok, options} ->
        bytes = Projection.log(Query.page(options), origin())

        ExactResponse.send_exact(
          conn,
          bytes,
          "application/json",
          Digest.hash_bytes(bytes),
          :no_store
        )

      {:error, message} ->
        ExactResponse.send_error(
          conn,
          400,
          :publication_query_invalid,
          message,
          "#{url(~p"/openapi.json")} lists the query parameters this address takes."
        )
    end
  end

  @doc """
  One published run, as everything this site is willing to say about it.
  """
  def show(conn, %{"bundle_digest" => digest}) do
    if Digest.valid?(digest) do
      show_valid_digest(conn, digest)
    else
      ExactResponse.send_error(
        conn,
        400,
        :publication_digest_invalid,
        "the publication fingerprint in the path is not a digest",
        find_a_run()
      )
    end
  end

  defp show_valid_digest(conn, digest) do
    case Query.get_entry(digest) do
      {:ok, entry} ->
        bytes = Projection.entry(entry, Query.runs_behind(entry), origin())

        ExactResponse.send_exact(
          conn,
          bytes,
          "application/json",
          Digest.hash_bytes(bytes),
          :no_store
        )

      :error ->
        ExactResponse.send_error(
          conn,
          404,
          :publication_missing,
          "no run is published under that fingerprint",
          find_a_run()
        )
    end
  end

  @doc """
  The exact bytes one published run was submitted as, while it stands.
  """
  def bundle(conn, %{"bundle_digest" => digest}) do
    if Digest.valid?(digest) do
      serve_bundle(conn, digest)
    else
      ExactResponse.send_error(
        conn,
        400,
        :publication_digest_invalid,
        "the publication fingerprint in the path is not a digest",
        find_a_run()
      )
    end
  end

  # The bytes go out as they came in. Nothing here decodes them, and nothing
  # re-encodes them: what a caller checks the participant's signatures against
  # has to be what the participant signed, and a document written out a second
  # time is a different string of bytes that means the same thing — which is
  # exactly the difference a signature can see.
  defp serve_bundle(conn, digest) do
    case Query.get_entry(digest) do
      {:ok, entry} ->
        if Query.withdrawn?(entry) do
          refuse_withdrawn(conn, entry)
        else
          ExactResponse.send_exact(
            conn,
            entry.submission_bytes,
            "application/json",
            Digest.hash_bytes(entry.submission_bytes),
            :no_store
          )
        end

      :error ->
        ExactResponse.send_error(
          conn,
          404,
          :publication_missing,
          "no run is published under that fingerprint",
          find_a_run()
        )
    end
  end

  # `410` rather than `404`: the run was published, it is still on the log, and
  # saying it was never here would be this site disagreeing with its own record
  # and with every copy of the bundle already in somebody's hands.
  defp refuse_withdrawn(conn, entry) do
    ExactResponse.send_error(
      conn,
      410,
      :publication_withdrawn,
      "the participant withdrew this run, so this site no longer hands out the " <>
        "bytes they submitted; the entry, the event that withdrew it and its " <>
        "receipt are still at /api/v1/techtree/publications/" <> entry.bundle_digest,
      "Read the entry and its receipt at #{url(~p"/api/v1/techtree/publications/#{entry.bundle_digest}")}."
    )
  end

  defp put_api_headers(conn, _options), do: ExactResponse.put_api_headers(conn)

  defp origin, do: RegentsWeb.Endpoint.url()

  defp find_a_run, do: "Use a fingerprint listed at #{url(~p"/api/v1/techtree/publications")}."
end
