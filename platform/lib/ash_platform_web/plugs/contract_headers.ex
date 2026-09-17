defmodule AshPlatformWeb.Plugs.ContractHeaders do
  @moduledoc """
  The Regents CLI reads two response headers from the served HTTP contract
  before it changes anything, and compares them with the values it was built
  against. Both values are derived from the contract file itself, so a change
  to the contract moves the headers and the CLI's expectation together.
  """

  @behaviour Plug

  import Plug.Conn

  @path "/api-contract.openapiv3.yaml"
  @file Application.app_dir(:ash_platform, "priv/static/api-contract.openapiv3.yaml")
  @external_resource @file
  @contract File.read!(@file)
  @major (case Regex.run(~r/^  version:\s*(\d+)\./m, @contract) do
            [_, major] -> major
          end)
  @digest "sha256:" <> Base.encode16(:crypto.hash(:sha256, @contract), case: :lower)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{request_path: @path} = conn, _opts) do
    conn
    |> put_resp_header("x-regents-contract-major", @major)
    |> put_resp_header("x-regents-contract-digest", @digest)
  end

  def call(conn, _opts), do: conn
end
