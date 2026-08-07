defmodule AshPlatform.AgentAuth.VerifiedEnvelopeBodyReaderTest do
  use ExUnit.Case, async: true

  alias AshPlatform.AgentAuth.VerifiedEnvelopeBodyReader

  @publication_path "/api/techtree/v1/nodes"
  @evidence_path "/api/techtree/v1/nodes/00000000-0000-0000-0000-000000000000/evidence-state"
  @notebook_path "/api/techtree/v1/nodes/00000000-0000-0000-0000-000000000000/notebook-artifact"

  for {path, limit} <- [
        {@publication_path, 65_536},
        {@evidence_path, 65_536},
        {@notebook_path, 4_194_304}
      ] do
    test "captures a body below the limit for #{path}" do
      assert {:ok, body, conn} = read(unquote(path), unquote(limit) - 1)
      assert byte_size(body) == unquote(limit) - 1
      assert conn.assigns.verified_envelope_raw_body == body
      refute Map.has_key?(conn.assigns, :verified_envelope_body_error)
    end

    test "captures a body at the limit for #{path}" do
      assert {:ok, body, conn} = read(unquote(path), unquote(limit))
      assert byte_size(body) == unquote(limit)
      assert conn.assigns.verified_envelope_raw_body == body
      refute Map.has_key?(conn.assigns, :verified_envelope_body_error)
    end

    test "marks a body over the limit for #{path} without capturing it" do
      assert {:ok, "{}", conn} = read(unquote(path), unquote(limit) + 1)
      assert conn.assigns.verified_envelope_body_error == :too_large
      refute Map.has_key?(conn.assigns, :verified_envelope_raw_body)
    end
  end

  test "other paths retain Plug.Conn body-reader behavior" do
    body = String.duplicate("x", 65_537)
    conn = Plug.Test.conn(:post, "/api/other", body)

    assert {:ok, ^body, conn} =
             VerifiedEnvelopeBodyReader.read_body(conn,
               length: byte_size(body),
               read_length: byte_size(body)
             )

    refute Map.has_key?(conn.assigns, :verified_envelope_raw_body)
    refute Map.has_key?(conn.assigns, :verified_envelope_body_error)
  end

  defp read(path, size) do
    body = String.duplicate("x", size)
    conn = Plug.Test.conn(:post, path, body)

    VerifiedEnvelopeBodyReader.read_body(conn, length: size + 1, read_length: size + 1)
  end
end
