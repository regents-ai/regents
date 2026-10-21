defmodule RegentsWeb.ExampleWorkflowsController do
  @moduledoc "The home page's example workflows, as agents read them."
  use RegentsWeb, :controller

  alias RegentsWeb.ExampleWorkflows

  def show(conn, params) when map_size(params) == 0,
    do: json(conn, %{example_workflows: ExampleWorkflows.read()})

  def show(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      error: %{
        code: "invalid_query",
        message: "This read takes no query parameters.",
        hint: "Send the request again without a query string."
      }
    })
  end
end
