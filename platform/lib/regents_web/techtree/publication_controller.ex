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
  alias Regents.Techtree.Network
  alias Regents.Techtree.Network.Document
  alias Regents.Techtree.Network.Error
  alias Regents.Techtree.Network.Ingest
  alias Regents.Techtree.Network.Key
  alias Regents.Techtree.Network.Projection
  alias Regents.Techtree.Network.Query
  alias RegentsWeb.Techtree.ExactResponse
  alias RegentsWeb.Techtree.PublicationRate

  # Every answer here is data, never a page, as on techtree.sh's API.
  plug :put_api_headers
  plug :limit_agent when action == :create

  @doc """
  Publish one finished run, or withdraw one already published.
  """
  def create(conn, _params) do
    case conn.assigns[:submitted_bytes] do
      bytes when is_binary(bytes) -> received(conn, bytes)
      nil -> refuse_content_type(conn)
    end
  end

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

  defp limit_agent(conn, _options) do
    PublicationRate.admit(
      conn,
      "publication-agent",
      {:publication_agent, conn.assigns.actor.wallet_address},
      Network.agent_rate_limit()
    )
  end

  defp received(conn, bytes) do
    case Document.kind(bytes) do
      {:ok, :submission} -> record(conn, bytes, Key.load())
      {:ok, :withdrawal} -> withdraw(conn, bytes, Key.load())
      {:error, %Error{} = error} -> refuse(conn, error)
    end
  end

  defp record(conn, bytes, loaded) do
    options = [
      actor: conn.assigns.actor,
      contributor_address: volunteered(conn),
      skill_name: header(conn, "x-techtree-skill-name"),
      skill_github_url: header(conn, "x-techtree-skill-github-url"),
      origin: origin()
    ]

    accepted =
      case loaded do
        {:ok, key} -> Ingest.accept(bytes, key, options)
        :error -> Ingest.recall(bytes, options)
      end

    case accepted do
      {:ok, entry, :recorded} -> receipt(conn, entry, 201)
      {:ok, entry, :existing} -> receipt(conn, entry, 200)
      :unrecorded -> refuse_uncountersignable(conn)
      {:error, %Error{} = error} -> refuse(conn, error)
    end
  end

  defp withdraw(conn, bytes, loaded) do
    withdrawn =
      case loaded do
        {:ok, key} -> Ingest.withdraw(bytes, key, origin(), actor: conn.assigns.actor)
        :error -> Ingest.recall_withdrawal(bytes, actor: conn.assigns.actor)
      end

    case withdrawn do
      {:ok, entry, _outcome} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, entry.withdrawal_receipt_bytes)

      :unrecorded ->
        refuse_uncountersignable(conn)

      {:error, %Error{} = error} ->
        refuse(conn, error)
    end
  end

  defp receipt(conn, entry, status) do
    location = "/api/v1/techtree/publications/" <> entry.bundle_digest

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("location", location)
    |> send_resp(status, entry.receipt_bytes)
  end

  defp volunteered(conn) do
    case get_req_header(conn, "x-techtree-contributor-address") do
      [address | _rest] -> address
      [] -> nil
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value] -> value
      [] -> nil
      _values -> :multiple
    end
  end

  defp refuse(conn, %Error{} = error) do
    ExactResponse.send_error(
      conn,
      Error.status_for(error.code),
      error.code,
      error.message,
      hint(Error.status_for(error.code))
    )
  end

  defp hint(404), do: find_a_run()

  defp hint(409),
    do:
      "This log already holds a different document for this run; " <>
        "read it at #{url(~p"/api/v1/techtree/publications")}."

  defp hint(_status),
    do:
      "Correct what the message names and send it again; " <>
        "#{url(~p"/techtree/docs/publish")} shows how to publish and withdraw a Result."

  defp refuse_uncountersignable(conn) do
    ExactResponse.send_error(
      conn,
      503,
      :network_key_unavailable,
      "this site signs a receipt for every run it publishes or withdraws and " <>
        "cannot sign one right now, so nothing was recorded; the same document " <>
        "can be sent again unchanged",
      "Send the same document again later."
    )
  end

  defp refuse_content_type(conn) do
    ExactResponse.send_error(
      conn,
      400,
      :submission_malformed,
      "what this address takes is sent as application/json, at most " <>
        "#{Network.maximum_body_bytes()} bytes: the files of one proof " <>
        "bundle, or a signed request to withdraw one already published",
      hint(400)
    )
  end

  defp origin, do: RegentsWeb.Endpoint.url()

  defp find_a_run, do: "Use a fingerprint listed at #{url(~p"/api/v1/techtree/publications")}."
end
