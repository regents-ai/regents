defmodule RegentsWeb.Account.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of every body the API takes, so the sign-in service can
  check them against the request's signature (`RegentsWeb.Account.PairedAgent`,
  `RegentAgents.HTTP`): any of them may come from an agent. The pages' own form
  bodies are read as before.
  """

  # Ordinary signed bodies use the same limit as RegentIdentity.BodyReader.
  @limit 8192
  # These routes accept a 64 KiB field and additional JSON and signature data.
  @patchbay_limit 128 * 1024
  @mcp_limit 512 * 1024
  # A 2 MiB picture expands to this size in base64, plus the draft's text.
  @draft_limit 4 * div(2 * 1024 * 1024 + 2, 3) + @limit

  def read_body(conn, opts) do
    cond do
      techtree_publication_post?(conn) ->
        publication_body(conn, opts)

      techtree_model_climb_post?(conn) ->
        Siwa.AgentAuthPlug.read_body(
          conn,
          opts,
          Regents.Techtree.ModelClimb.Proof.maximum_bytes()
        )

      autolaunch_draft_patch?(conn) ->
        Siwa.AgentAuthPlug.read_body(conn, opts, @draft_limit)

      limit = signed_limit(conn) ->
        Siwa.AgentAuthPlug.read_body(conn, opts, limit)

      true ->
        RegentIdentity.BodyReader.read_body(conn, opts)
    end
  end

  defp publication_body(conn, opts) do
    case Siwa.AgentAuthPlug.read_body(conn, opts, Regents.Techtree.Network.maximum_body_bytes()) do
      {:ok, body, conn} -> {:ok, body, Plug.Conn.assign(conn, :submitted_bytes, body)}
      other -> other
    end
  end

  defp techtree_publication_post?(%{
         method: "POST",
         path_info: ["api", "v1", "techtree", "publications"]
       }),
       do: true

  defp techtree_publication_post?(_conn), do: false

  defp techtree_model_climb_post?(%{
         method: "POST",
         path_info: ["api", "v1", "techtree", "model-climb", "reports"]
       }),
       do: true

  defp techtree_model_climb_post?(_conn), do: false

  defp autolaunch_draft_patch?(%{
         method: "PATCH",
         path_info: ["api", "agent", "v1", "autolaunch", "drafts", kind]
       })
       when kind in ["revstake", "memestock"],
       do: true

  defp autolaunch_draft_patch?(_conn), do: false

  defp signed_limit(%{method: "POST", path_info: ["mcp"]}), do: @mcp_limit

  defp signed_limit(%{
         method: "POST",
         path_info: [
           "api",
           "v1",
           "keyfleet",
           "agent",
           "fleets",
           _,
           "projects",
           _,
           "notebooks",
           _,
           "files",
           operation
         ]
       })
       when operation in ["add", "write"],
       do: Application.fetch_env!(:regents, :keyfleet_notebooks)[:max_request_bytes]

  defp signed_limit(%{method: "POST", path_info: ["patchbay", "known-fixes", _]}),
    do: @patchbay_limit

  defp signed_limit(%{method: method, path_info: ["api", "v1", "patchbay" | _]})
       when method in ["POST", "PATCH"],
       do: @patchbay_limit

  defp signed_limit(%{method: method, path_info: ["api", "agent", "v1", "patchbay" | _]})
       when method in ["POST", "PATCH"],
       do: @patchbay_limit

  defp signed_limit(%{method: method, path_info: ["api" | _]}) when method in ["POST", "PATCH"],
    do: @limit

  defp signed_limit(_conn), do: nil
end
