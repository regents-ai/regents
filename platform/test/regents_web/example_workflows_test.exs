defmodule RegentsWeb.ExampleWorkflowsTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.ExampleWorkflows

  # The home page's figure, the agent read and the page's Markdown all come
  # from ExampleWorkflows, so an agent reads the same apps, steps and revenue
  # split a person sees, and none of them claims every fee goes to stakers.

  test "agents read each app's steps and the exact revenue split", %{conn: conn} do
    read =
      conn
      |> get("/api/v1/example-workflows")
      |> json_response(200)
      |> Map.fetch!("example_workflows")

    assert Enum.map(read["workflows"], & &1["id"]) ==
             Enum.map(ExampleWorkflows.workflows(), & &1.id)

    for %{"id" => id, "steps" => steps} <- read["workflows"], id != "staking" do
      assert length(steps) in 4..6, "#{id} has #{length(steps)} steps"
    end

    assert read["staking_revenue"]["split"] == ExampleWorkflows.revenue_split()

    assert Enum.map(read["staking_revenue"]["sources"], & &1["share"]) ==
             Enum.map(ExampleWorkflows.revenue_sources(), & &1.share)

    refute Jason.encode!(read) =~ ~r/all (the )?fees/i
  end

  test "the agent read takes no query", %{conn: conn} do
    assert %{"error" => %{"code" => "invalid_query"}} =
             conn |> get("/api/v1/example-workflows?app=techtree") |> json_response(400)
  end

  test "the home page's Markdown lists every step and the revenue split", %{conn: conn} do
    markdown = conn |> put_req_header("accept", "text/markdown") |> get("/") |> response(200)

    assert markdown =~ "# Agents build together. Useful work creates value."
    assert markdown =~ ExampleWorkflows.revenue_split()

    for workflow <- ExampleWorkflows.workflows(), step <- workflow.steps do
      assert markdown =~ "**#{step.title}.**"
    end

    for source <- ExampleWorkflows.revenue_sources(), do: assert(markdown =~ source.share)
    refute markdown =~ ~r/all (the )?fees/i
  end

  test "the old staking address moves to the home page for good", %{conn: conn} do
    conn = get(conn, "/stake")
    assert conn.status == 301
    assert redirected_to(conn, 301) == "/"
  end
end
