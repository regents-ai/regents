defmodule RegentIdentity.BodyReaderTest do
  use ExUnit.Case, async: true

  test "profile body limits apply before upstream JSON parsing, including equivalent slashes" do
    parser =
      Plug.Parsers.init(
        parsers: [:json],
        json_decoder: Jason,
        body_reader: {RegentIdentity.BodyReader, :read_body, []}
      )

    for path <- [
          "/api/v1/profile",
          "/api/v1/profile/",
          "/api/v1/profile/sync/",
          "/api//v1/profile"
        ] do
      conn =
        Plug.Test.conn(:patch, path, Jason.encode!(%{display_name: String.duplicate("a", 9000)}))
        |> Plug.Conn.put_req_header("content-type", "application/json")

      assert_raise Plug.Parsers.RequestTooLargeError, fn -> Plug.Parsers.call(conn, parser) end
    end
  end
end
