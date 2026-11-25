defmodule RegentsWeb.Account.AgentBodyReader do
  @moduledoc """
  Keeps the exact bytes of every body the API takes, so the sign-in service can
  check them against the request's signature (`RegentsWeb.Account.PairedAgent`,
  `RegentAgents.HTTP`): any of them may come from an agent. The pages' own form
  bodies are read as before.
  """

  # Ordinary signed bodies use the same limit as RegentIdentity.BodyReader.
  @limit 8192
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

      signed?(conn) ->
        Siwa.AgentAuthPlug.read_body(conn, opts, @limit)

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

  defp signed?(%{method: "POST", path_info: ["mcp"]}), do: true

  defp signed?(%{method: method, path_info: ["api" | _rest]}) when method in ["POST", "PATCH"],
    do: true

  defp signed?(_conn), do: false
end
