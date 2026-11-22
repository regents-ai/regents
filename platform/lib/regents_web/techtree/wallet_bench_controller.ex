defmodule RegentsWeb.Techtree.WalletBenchController do
  @moduledoc """
  The Wallet Bench for agents and other sites: `/techtree/wallet-bench.md`, the
  page's grids and list as Markdown (`RegentsWeb.Techtree.WalletBenchMD`), and
  `/techtree/wallet-bench.json`, the page's score grids as data, each score
  linked to its result on the page (`RegentsWeb.Techtree.WalletBenchScores`).
  Both are public and may be kept for 30 seconds. When the database can't be
  read each answers 503 asking to try again (`RegentsWeb.Techtree.Outage`).
  """

  use RegentsWeb, :controller

  alias Regents.Techtree.WalletBench
  alias RegentsWeb.Techtree.{ExactResponse, Outage, WalletBenchScores}
  alias RegentsWeb.Techtree.WalletBenchCopy, as: Copy

  def markdown(conn, _params) do
    case Outage.read(fn -> WalletBench.list_attempts!(load: [:turns, :model_spend_usd]) end) do
      {:ok, attempts} ->
        generated_at = DateTime.utc_now() |> DateTime.truncate(:second)

        conn
        |> put_resp_header("cache-control", "public, max-age=30")
        |> put_resp_content_type("text/markdown", "utf-8")
        |> send_resp(200, RegentsWeb.Techtree.WalletBenchMD.render(attempts, generated_at))

      :database_down ->
        conn
        |> put_resp_header("retry-after", "30")
        |> put_resp_content_type("text/markdown", "utf-8")
        |> send_resp(503, Copy.unreadable() <> "\n")
    end
  end

  @doc """
  The score grids as data (`RegentsWeb.Techtree.WalletBenchScores`). When the
  database can't be read the answer is a 503 asking to try again; any other
  failure is the site's plain JSON 500.
  """
  def scores(conn, _params) do
    case Outage.read(&WalletBenchScores.read/0) do
      {:ok, scores} ->
        conn
        |> put_resp_header("cache-control", "public, max-age=30")
        |> json(scores)

      :database_down ->
        conn
        |> put_resp_header("retry-after", "30")
        |> ExactResponse.send_error(
          503,
          :scores_unavailable,
          "the Wallet Bench scores can't be read right now; try again shortly",
          "Wait the seconds in the Retry-After header, then ask again."
        )
    end
  end
end
