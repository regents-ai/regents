defmodule RegentsWeb.AgentDocumentsCacheTest do
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test, only: [conn: 2]

  # Agents fetch these on every visit; a shared cache may keep each for five
  # minutes and ask again with its ETag.
  for path <- ~w(/agents.md /skill.md /llms.txt) do
    test "#{path} is a shared document with its body's ETag" do
      response =
        :get |> conn(unquote(path)) |> RegentsWeb.Endpoint.call(RegentsWeb.Endpoint.init([]))

      assert response.status == 200
      assert get_resp_header(response, "cache-control") == ["public, max-age=300"]

      assert get_resp_header(response, "etag") ==
               [~s("#{Base.encode16(:crypto.hash(:sha256, response.resp_body), case: :lower)}")]
    end
  end
end
