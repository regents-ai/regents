defmodule RegentsWeb.PrivyPair do
  @moduledoc """
  The sign-in a signed-in read carries: a Privy access token in
  `Authorization: Bearer …` and a Privy identity token in `Privy-Id-Token`,
  verified together. An optional `X-Privy-User-Id` must name the same person.
  """

  import Plug.Conn, only: [get_req_header: 2]

  def verify(conn) do
    with {["Bearer " <> access], [identity]} <-
           {get_req_header(conn, "authorization"), get_req_header(conn, "privy-id-token")},
         true <- byte_size(access) in 1..32_768 and byte_size(identity) in 1..32_768,
         {:ok, actor} <-
           RegentPrivy.Session.verify(
             %{access: access, identity: identity},
             Application.get_env(:regents, :privy, [])
           ),
         true <- get_req_header(conn, "x-privy-user-id") in [[], [actor.privy_user_id]] do
      {:ok, actor}
    else
      {:error, {:configuration, _}} -> {:error, :unconfigured}
      _ -> {:error, :unauthenticated}
    end
  end
end
