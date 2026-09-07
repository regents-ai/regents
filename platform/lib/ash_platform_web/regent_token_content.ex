defmodule AshPlatformWeb.RegentTokenContent do
  @moduledoc """
  The public facts the `$REGENT` page states.

  This is editorial content, not a chain reading. Every figure was checked
  against public sources on the date `reviewed_at/0` names and is copied here
  from the reviewed record described in `docs/regent-token-facts.md`. Nothing on
  the page is fetched, so the page never shows a figure it cannot date.
  """

  @reviewed_at ~U[2026-09-07 04:30:28Z]

  @token %{
    name: "Regent",
    symbol: "REGENT",
    address: "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07",
    decimals: 18,
    genesis_supply: "100000000000",
    chain: "Base",
    chain_id: 8453
  }

  @launch %{
    transaction: "0x5fb374b1cb93e6ca9d02f729cb58a9d5312f003050cbcdcbc8320070a4946ffa",
    block: 37_827_760,
    at: ~U[2025-11-06 16:01:07Z]
  }

  # The genesis split the launch transaction executed, in launch order. The
  # Labs share went through the launch's airdrop mechanism; it is an original
  # allocation, not a statement of what Regents Labs holds today.
  @allocation [
    %{
      id: :liquidity,
      label: "Liquidity",
      percent: 20,
      tokens: "20000000000",
      note: "Placed in the Uniswap v4 pool at launch."
    },
    %{
      id: :labs,
      label: "Labs allocation",
      percent: 40,
      tokens: "40000000000",
      note: "Sent to Regents Labs through the launch airdrop mechanism."
    },
    %{
      id: :vault,
      label: "Vault",
      percent: 40,
      tokens: "40000000000",
      note: "Locked in the Clanker vault contract on a fixed release schedule."
    }
  ]

  @vault %{
    address: "0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C",
    tokens: "40000000000",
    lock_seconds: 31_536_000,
    vesting_seconds: 63_072_000,
    funded_at: ~U[2025-11-06 16:01:07Z],
    unlock_at: ~U[2026-11-06 16:01:07Z],
    midway_at: ~U[2027-11-06 16:01:07Z],
    fully_vested_at: ~U[2028-11-05 16:01:07Z]
  }

  @treasury %{
    address: "0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e",
    threshold: 2,
    owners: [
      "0x8C172cA4b5Dd9449217C636A953727eACD690e37",
      "0x978BDbECb54C54800D01055Df5A8f6af600BfaCe",
      "0x1d0dcABAeb941823E51935F795Be184aBeBf76dF"
    ],
    version: "1.4.1+L2"
  }

  @staking %{address: "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5"}

  @redemption %{
    address: "0x71065b775a590c43933F10c0055dc7d74AfAbb0e",
    regent_per_redemption: "5000000",
    usdc_price: "80",
    vesting_seconds: 604_800
  }

  # Indexed balances at `reviewed_at`, largest first, as exact token amounts
  # (atomic balance over 10^18). The page shortens them on screen and keeps
  # the exact figure for assistive technology and hover.
  @holders [
    %{
      address: "0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C",
      label: "Clanker vault",
      description:
        "Contract-enforced time release of the 40 billion vault allocation. The shared vault holds REGENT separately from other tokens.",
      tokens: "40000000000"
    },
    %{
      address: "0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e",
      label: "Regents Labs Treasury",
      description:
        "Safe treasury; the owner-signing threshold was 2 of 3 when checked. Its balance is separate from the time-locked vault allocation.",
      tokens: "14796504503.504863237545574501"
    },
    %{
      address: "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5",
      label: "REGENT staking contract",
      description:
        "Includes customers' staked principal and the funded reward inventory. The whole balance is neither treasury nor available rewards.",
      tokens: "12601015521.393597867938800072"
    },
    %{
      address: "0x498581fF718922c3f8e6A244956aF099B2652b2b",
      label: "Uniswap v4 PoolManager",
      description:
        "The shared liquidity contract for many pools, not one wallet or a single REGENT pool.",
      tokens: "11370610519.952098010140379445"
    },
    %{
      address: "0x0cb27e883E207905AD2A94F9B6eF0C7A99223C37",
      label: "Token launch administrator",
      description:
        "The address recorded as administrator and creator-buy recipient in the launch. Separate from the Treasury.",
      tokens: "7034023608.342838907856226374"
    },
    %{
      address: "0x71065b775a590c43933F10c0055dc7d74AfAbb0e",
      label: "Animata redemption contract",
      description:
        "Holds REGENT for redemptions and their seven-day vesting claims. Separate from the long-term vault.",
      tokens: "2859857607.163533118952566772"
    }
  ]

  # The allocation plan Regents Labs published when the token launched, as
  # policy. It is not an onchain rule and not a statement of current balances.
  @original_policy %{
    labs: [
      "10% Animata program",
      "10% agent-coin fee rewards",
      "10% protocol growth and agent API support",
      "10% ecosystem fund"
    ],
    vault: ["20% treasury", "20% sovereign-agent incentives"]
  }

  @sources %{
    launch_record: "https://www.clanker.world/clanker/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07",
    launch_transaction:
      "https://base.blockscout.com/tx/0x5fb374b1cb93e6ca9d02f729cb58a9d5312f003050cbcdcbc8320070a4946ffa",
    vault_source:
      "https://base.blockscout.com/address/0x8E845EAd15737bF71904A30BdDD3aEE76d6ADF6C?tab=contract",
    holders:
      "https://base.blockscout.com/token/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07?tab=holders",
    safe: "https://app.safe.global/home?safe=base:0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e",
    token_basescan: "https://basescan.org/token/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07",
    token_blockscout:
      "https://base.blockscout.com/token/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"
  }

  def reviewed_at, do: @reviewed_at
  def token, do: @token
  def launch, do: @launch
  def allocation, do: @allocation
  def vault, do: @vault
  def treasury, do: @treasury
  def staking, do: @staking
  def redemption, do: @redemption
  def holders, do: @holders
  def original_policy, do: @original_policy
  def sources, do: @sources

  @doc """
  The vault's release, as the moments a visitor can check: funding, the end of
  the lock, the midway point and full vesting. Each amount is the cumulative
  quantity eligible to be claimed by then, not a claimed or sold balance.
  """
  def release_timeline do
    [
      %{
        at: @vault.funded_at,
        title: "Vault funded",
        eligible_tokens: "0",
        detail:
          "40 billion REGENT locked at launch. Nothing can be claimed during the first year."
      },
      %{
        at: @vault.unlock_at,
        title: "Release begins",
        eligible_tokens: "0",
        detail: "The lock ends and a linear release over 730 days starts from zero."
      },
      %{
        at: @vault.midway_at,
        title: "Halfway",
        eligible_tokens: "20000000000",
        detail: "20 billion REGENT cumulatively eligible to claim, whether or not any has been."
      },
      %{
        at: @vault.fully_vested_at,
        title: "Fully vested",
        eligible_tokens: "40000000000",
        detail: "The whole 40 billion is eligible. Eligibility is not a sale or circulation."
      }
    ]
  end

  @doc "Share of the 100 billion genesis supply, to one decimal, never rounded up."
  def percent_of_genesis(tokens) do
    tokens
    |> Decimal.new()
    |> Decimal.mult(100)
    |> Decimal.div(Decimal.new(@token.genesis_supply))
    |> Decimal.round(1, :down)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  @doc "A moment written the way the page reads it: 6 Nov 2026, 16:01:07 UTC."
  def written(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y, %H:%M:%S UTC")

  @doc "The day alone: 6 Nov 2026."
  def written_day(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y")

  def explorer_address(address), do: "https://base.blockscout.com/address/#{address}"
end
