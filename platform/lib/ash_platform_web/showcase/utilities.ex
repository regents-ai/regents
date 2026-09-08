defmodule AshPlatformWeb.Showcase.Utilities do
  @moduledoc false
  alias AshPlatform.WalletActions.{Abi, Address, Rpc}

  def address(value) do
    case Address.decode(value) do
      {:ok, bytes} -> %{canonical: Address.canonical(bytes), checksum: Address.format(bytes)}
      :error -> %{error: "Enter a non-zero EVM address with a valid checksum."}
    end
  end

  def amount(value, decimals) do
    with true <- byte_size(value) <= 78,
         {number, ""} when number >= 0 <- Integer.parse(value),
         {places, ""} when places in 0..36 <- Integer.parse(decimals),
         true <- byte_size(decimals) <= 2 do
      %{formatted: Rpc.format_units(number, places)}
    else
      _ -> %{error: "Use a non-negative integer (up to 78 digits) and 0–36 decimals."}
    end
  end

  def calldata(value, amount) do
    with true <- byte_size(amount) <= 78,
         {:ok, canonical} <- Address.normalize(value),
         {number, ""} when number >= 0 <- Integer.parse(amount),
         true <- number < Integer.pow(2, 256) do
      %{
        method: "ERC20 approve(address,uint256)",
        data: Abi.encode_erc20("approve", [canonical, number]),
        execution: "Encoded locally; not submitted"
      }
    else
      _ -> %{error: "A valid spender and uint256 amount are required."}
    end
  end

  def privy(scenario) when scenario in [:valid, :expired, :audience] do
    now = 1_750_000_000
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, public_pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()

    claims = %{
      "iss" => "privy.io",
      "aud" => if(scenario == :audience, do: "another-app", else: "showcase-fixture"),
      "sub" => "did:privy:showcase-fixture",
      "iat" => now - 10,
      "exp" => if(scenario == :expired, do: now - 1, else: now + 3600)
    }

    {_, token} = key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()

    case RegentPrivy.verify_token(token,
           app_id: "showcase-fixture",
           verification_key: public_pem,
           now: now
         ) do
      {:ok, verified} ->
        %{result: "Verified fixture", identity: verified.privy_user_id, session_created: false}

      {:error, reason} ->
        %{result: "Rejected fixture", reason: reason, session_created: false}
    end
  end

  def database do
    config = AshPlatform.Repo.config()
    database = config[:database] || ""

    if is_nil(config[:url]) and config[:hostname] in ["127.0.0.1", "localhost"] and
         Regex.match?(~r/\Aash_platform_[0-9a-f]{12}_test\z/, database) do
      case Ecto.Adapters.SQL.query(AshPlatform.Repo, "SELECT current_database(), 1", [],
             timeout: 2_000
           ) do
        {:ok, %{rows: [[name, 1]]}} -> %{database: name, result: "SELECT 1 passed", writes: 0}
        {:error, _} -> %{error: "Local database unavailable."}
      end
    else
      %{error: "This diagnostic requires a prepared isolated local test database."}
    end
  catch
    :exit, _ -> %{error: "Local database process unavailable."}
  end
end
