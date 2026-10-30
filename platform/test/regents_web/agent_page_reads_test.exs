defmodule RegentsWeb.AgentPageReadsTest do
  use RegentsWeb.ConnCase, async: true

  @about "priv/tool_manifest.json"
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("tools")
         |> Enum.find(&(&1["name"] == "regents_about"))

  test "every page regents_about reads answers Markdown and says so in its head" do
    paths = @about["route"] |> String.split(", ") |> Enum.map(&String.trim_leading(&1, "GET "))
    assert length(paths) == length(@about["input_schema"]["properties"]["page"]["enum"])

    for path <- paths do
      markdown = build_conn() |> put_req_header("accept", "text/markdown") |> get(path)
      assert response(markdown, 200) =~ ~r/\A# /, path
      assert [type] = get_resp_header(markdown, "content-type")
      assert type =~ "text/markdown", path

      assert build_conn()
             |> get(path)
             |> html_response(200)
             |> Floki.parse_document!()
             |> Floki.find(~s(link[rel=alternate][type="text/markdown"])) != [],
             path
    end
  end
end
