defmodule RegentsWeb.Keyfleet.AgentFilesController do
  @moduledoc """
  The files an agent needs to join Keyfleet, served from the site itself: the
  joining guide at `/keyfleet/skill.md`, and each runtime's skill at
  `/keyfleet/agents/SLUG/skill.md`, which is the guide with that runtime's notes
  from `RegentsWeb.Keyfleet.AgentGuides` added. The parts an agent needs only
  for some work (the fleet's code, notebooks, polls and proposals) are short
  pages of their own at `/keyfleet/skill/NAME.md`, which the guide links.
  Agents get the SIWA sign-in client from the sign-in server, which the guide
  links; `/keyfleet/agent/git-remote-siwa` is the git helper that signs each of
  git's requests to a fleet's code with that client.

  The guide and its parts are read when the application is compiled. Their
  placeholders become addresses when they are served: `{{origin}}` this site's,
  `{{siwa_origin}}` the sign-in server's public address
  (`config :regents, :keyfleet_siwa_origin`), `{{code_origin}}` the one the
  fleets' code is under (`config :regents, :keyfleet_code_origin`), and
  `{{notebooks_origin}}` a fleet's notebooks, written for the fleet `FLEET-ID`
  (`config :regents, :keyfleet_notebooks_host_suffix`). Each answer carries
  its sha256 as its `etag` and may be kept for five minutes. Nothing here reads
  the database.
  """
  use RegentsWeb, :controller

  alias Regents.Keyfleet.GoalIdeas
  alias RegentsWeb.Keyfleet.{AgentGuides, PublicDocuments}

  @guide_path Application.app_dir(:regents, "priv/keyfleet/public/skill.md")
  @external_resource @guide_path
  @guide File.read!(@guide_path)

  @part_paths Map.new(
                ~w(code.md notebooks.md decide.md),
                &{&1, Application.app_dir(:regents, "priv/keyfleet/public/skill/#{&1}")}
              )
  for {_name, path} <- @part_paths, do: @external_resource(path)
  @parts Map.new(@part_paths, fn {name, path} -> {name, File.read!(path)} end)

  @git_helper_path Application.app_dir(:regents, "priv/keyfleet/public/git-remote-siwa")
  @external_resource @git_helper_path
  @git_helper File.read!(@git_helper_path)

  @doc "The joining guide as it is served, with this site's addresses in it."
  def guide, do: fill(@guide)

  defp fill(markdown) do
    notebooks_suffix = Application.fetch_env!(:regents, :keyfleet_notebooks_host_suffix)

    markdown
    |> String.replace("{{siwa_origin}}", Application.fetch_env!(:regents, :keyfleet_siwa_origin))
    |> String.replace("{{code_origin}}", Application.fetch_env!(:regents, :keyfleet_code_origin))
    |> String.replace("{{notebooks_origin}}", "https://FLEET-ID." <> notebooks_suffix)
    |> String.replace("{{origin}}", PublicDocuments.url(""))
  end

  def skill(conn, _params), do: markdown(conn, guide())

  @doc "One part of the guide, such as `/keyfleet/skill/code.md`."
  def part(conn, %{"part" => name}) do
    case @parts do
      %{^name => part} -> markdown(conn, fill(part))
      %{} -> raise RegentsWeb.NotFoundError
    end
  end

  @doc """
  One runtime's skill: the joining guide with that runtime's Set up section
  from its page at `/keyfleet/agents/SLUG` added at the end, then the starting
  ideas for a fleet's shared goal.
  """
  def agent_skill(conn, %{"agent" => slug}) do
    case AgentGuides.setup(slug) do
      {name, setup} ->
        markdown(
          conn,
          guide() <> "\n## On #{name}\n\n" <> setup <> "\n\n" <> GoalIdeas.markdown()
        )

      nil ->
        raise RegentsWeb.NotFoundError
    end
  end

  def git_helper(conn, _params) do
    conn
    |> cached(@git_helper)
    |> put_resp_content_type("text/x-python")
    |> send_resp(200, @git_helper)
  end

  defp markdown(conn, body) do
    conn |> cached(body) |> put_resp_content_type("text/markdown") |> send_resp(200, body)
  end

  defp cached(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{sha256(body)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_header("access-control-allow-origin", "*")
  end

  defp sha256(body), do: Base.encode16(:crypto.hash(:sha256, body), case: :lower)
end
