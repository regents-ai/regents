defmodule AshPlatformWeb.AgentLinkController do
  use AshPlatformWeb, :controller

  alias AshPlatform.Accounts.VerifiedSession
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.AgentAuth.{ClaimRateLimiter, VerificationClient}
  alias AshPlatform.Formation

  @maximum_code_bytes 128

  def index(conn, %{"regent_id" => regent_id} = params) when map_size(params) == 1 do
    with {:ok, normalized_regent_id} <- Ash.Type.UUID.cast_input(regent_id, []),
         {:ok, actor} <- current_human(conn),
         {:ok, %{id: ^normalized_regent_id}} <- Formation.get_my_regent(actor: actor),
         {:ok, links} <- Formation.list_my_agent_links(normalized_regent_id, actor: actor) do
      json(conn, %{data: Enum.map(links, &public_link/1)})
    else
      {:error, :authentication_required} -> unauthorized(conn)
      _error -> not_found(conn)
    end
  end

  def index(conn, _params), do: not_found(conn)

  def claim(conn, %{"regent_id" => regent_id} = params) when map_size(params) == 1 do
    with {:ok, normalized_regent_id} <- Ash.Type.UUID.cast_input(regent_id, []),
         true <- plain_text?(conn),
         {:ok, code, conn} <- read_code(conn),
         true <- valid_code?(code),
         :ok <- ClaimRateLimiter.admit(conn.remote_ip) do
      verify_and_claim(conn, normalized_regent_id, code)
    else
      {:error, :rate_limited} -> rate_limited(conn)
      _error -> pairing_failed(conn)
    end
  end

  def claim(conn, _params), do: pairing_failed(conn)

  defp verify_and_claim(conn, regent_id, code) do
    envelope = %{
      method: conn.method,
      path: conn.request_path,
      headers: Map.new(conn.req_headers),
      body: code
    }

    case VerificationClient.verify(envelope) do
      {:ok, identity} -> create_link(conn, regent_id, code, identity)
      {:error, _reason} -> verification_failed(conn)
    end
  end

  defp create_link(conn, regent_id, code, identity) do
    case Formation.claim_agent_link(regent_id, String.trim(code), identity, actor: %System{}) do
      {:ok, link} -> conn |> put_status(:created) |> json(%{data: public_link(link)})
      {:error, _error} -> pairing_failed(conn)
    end
  end

  defp read_code(conn) do
    case Plug.Conn.read_body(conn,
           length: @maximum_code_bytes + 1,
           read_length: @maximum_code_bytes + 1
         ) do
      {:ok, code, conn} -> {:ok, code, conn}
      {:more, _partial, _conn} -> {:error, :code_too_long}
      {:error, _reason} -> {:error, :body_unavailable}
    end
  end

  defp valid_code?(code),
    do:
      is_binary(code) and byte_size(code) <= @maximum_code_bytes and String.valid?(code) and
        String.trim(code) != ""

  defp plain_text?(conn) do
    Enum.any?(get_req_header(conn, "content-type"), &String.starts_with?(&1, "text/plain"))
  end

  defp current_human(conn) do
    with id when is_integer(id) <- get_session(conn, :human_account_id),
         actor = %Human{human_account_id: id},
         {:ok, account} when not is_nil(account) <-
           AshPlatform.Accounts.get_human_account(id, actor: actor),
         true <- VerifiedSession.current?(account) do
      {:ok, actor}
    else
      _ -> {:error, :authentication_required}
    end
  end

  defp public_link(link) do
    %{
      id: link.id,
      regent_id: link.regent_id,
      agent_id: link.agent_id,
      registry_address: link.registry_address,
      token_id: link.token_id,
      wallet: link.wallet,
      paired_at: DateTime.to_iso8601(link.paired_at)
    }
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "The Regent was not found."}})
  end

  defp pairing_failed(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{code: "pairing_failed", message: "The pairing code could not be used."}
    })
  end

  defp verification_failed(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      error: %{
        code: "verification_failed",
        message: "The signed agent request could not be verified."
      }
    })
  end

  defp rate_limited(conn) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{
      error: %{
        code: "rate_limited",
        message: "Too many pairing attempts. Please wait and try again."
      }
    })
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "unauthorized"})
  end
end
