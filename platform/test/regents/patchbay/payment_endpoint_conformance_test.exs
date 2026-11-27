defmodule Regents.Patchbay.Probes.PaymentEndpointConformanceTest do
  use ExUnit.Case, async: true

  alias Regents.Patchbay.Probes.PaymentEndpoint

  @now ~U[2026-11-26 20:00:00Z]

  defp encode_b64_json(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp mpp_header(attrs) do
    pairs =
      attrs
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map_join(", ", fn {k, v} -> ~s(#{k}="#{v}") end)

    "Payment " <> pairs
  end

  describe "x402 v2 wire captures" do
    test "valid x402 v2 challenge + OPTIONS 204 preflight passes with zero failures" do
      payload = %{
        "x402Version" => 2,
        "accepts" => [
          %{
            "scheme" => "exact",
            "network" => "eip155:8453",
            "asset" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "payTo" => "0x1111111111111111111111111111111111111111",
            "maxAmountRequired" => "10000"
          }
        ],
        "extensions" => %{"bazaar" => %{"discoverable" => true}}
      }

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://regents.sh/patchbay/bench/x402-test",
          method: "GET",
          status: 402,
          headers: %{
            "payment-required" => [encode_b64_json(payload)],
            "access-control-allow-origin" => ["*"],
            "access-control-expose-headers" => ["PAYMENT-REQUIRED, PAYMENT-RESPONSE"]
          },
          body: "",
          latency_ms: 42,
          now: @now,
          preflight: %{
            status: 204,
            headers: %{
              "access-control-allow-origin" => ["*"],
              "access-control-allow-headers" => ["Payment-Signature, X-Payment, Content-Type"]
            }
          }
        })

      assert result.verdict == :pass
      assert result.detected_protocols == ["x402"]
      assert result.x402.accepts_valid? == true
      assert result.x402.bazaar_discoverable? == true
      assert result.cors.preflight_ok == true
      assert Enum.all?(result.checks, &(&1.level == :pass))
    end

    test "valid x402 v2 challenge with OPTIONS 404 flags browser CORS preflight warning and report_prefill" do
      payload = %{
        "x402Version" => 2,
        "accepts" => [
          %{
            "scheme" => "exact",
            "network" => "eip155:8453",
            "asset" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "payTo" => "0x1111111111111111111111111111111111111111",
            "amount" => "10000"
          }
        ]
      }

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://api.example.com/v1/pay",
          method: "GET",
          status: 402,
          headers: %{"payment-required" => [encode_b64_json(payload)]},
          body: "",
          latency_ms: 88,
          now: @now,
          preflight: %{status: 404, headers: %{}}
        })

      assert result.verdict == :pass
      assert result.cors.preflight_ok == false
      assert Enum.any?(result.checks, &(&1.code == "cors_preflight_failed" and &1.level == :warn))
      assert Enum.any?(result.checks, &(&1.code == "x402_cors_missing" and &1.level == :warn))
      assert "x402-payment-required-cors" in result.known_fix_ids
      assert String.contains?(result.report_prefill.forum_url, "/patchbay/forum?")
      assert String.contains?(result.report_prefill.body_markdown, "OPTIONS")
    end

    test "malformed PAYMENT-REQUIRED header fails (no false pass or warn)" do
      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://broken.example.com/402",
          method: "GET",
          status: 402,
          headers: %{"payment-required" => ["not-valid-base64-or-json!!!"]},
          body: "",
          latency_ms: 19,
          now: @now
        })

      assert result.verdict == :fail
      assert Enum.any?(result.checks, &(&1.code == "x402_malformed" and &1.level == :fail))
    end

    test "x402 accepts[] missing required payTo or invalid network fails" do
      payload = %{
        "x402Version" => 2,
        "accepts" => [%{"scheme" => "exact", "network" => "not a network", "asset" => "USDC"}]
      }

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://broken.example.com/402",
          method: "GET",
          status: 402,
          headers: %{"payment-required" => [encode_b64_json(payload)]},
          body: "",
          latency_ms: 21,
          now: @now
        })

      assert result.verdict == :fail
      assert result.x402.accepts_valid? == false
      assert Enum.any?(result.checks, &(&1.code == "x402_accepts_invalid" and &1.level == :fail))
    end
  end

  describe "MPP (Tempo) wire captures" do
    test "live Patchbay MPP Tempo charge challenge + OPTIONS 204 passes completely" do
      req =
        encode_b64_json(%{
          "amount" => "10000",
          "currency" => "USDC.e",
          "network" => "eip155:4217",
          "recipient" => "0x1111111111111111111111111111111111111111"
        })

      header =
        mpp_header(%{
          "id" => "mpp_pb_abc123",
          "realm" => "regents.sh",
          "method" => "tempo",
          "intent" => "charge",
          "expires" => "2026-11-26T20:05:00Z",
          "request" => req
        })

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://regents.sh/patchbay/bench/mpp-test",
          method: "GET",
          status: 402,
          headers: %{
            "www-authenticate" => [header],
            "cache-control" => ["no-store"],
            "vary" => ["Authorization"],
            "access-control-allow-origin" => ["*"],
            "access-control-expose-headers" => ["WWW-Authenticate, Payment-Receipt"]
          },
          body: "",
          latency_ms: 35,
          now: @now,
          preflight: %{
            status: 204,
            headers: %{
              "access-control-allow-origin" => ["*"],
              "access-control-allow-headers" => ["Authorization, Content-Type"]
            }
          }
        })

      assert result.verdict == :pass
      assert result.detected_protocols == ["mpp"]
      assert result.mpp.valid? == true
      assert result.cors.preflight_ok == true
      assert Enum.all?(result.checks, &(&1.level == :pass))
    end

    test "expired MPP challenge fails" do
      req = encode_b64_json(%{"amount" => "10000", "currency" => "USDC.e"})

      header =
        mpp_header(%{
          "id" => "mpp_expired",
          "method" => "tempo",
          "intent" => "session",
          "expires" => "2026-11-26T19:50:00Z",
          "request" => req
        })

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://expired.example.com/mpp",
          method: "GET",
          status: 402,
          headers: %{"www-authenticate" => [header]},
          body: "",
          latency_ms: 25,
          now: @now
        })

      assert result.verdict == :fail
      assert result.mpp.valid? == false
      assert Enum.any?(result.checks, &(&1.code == "mpp_malformed" and &1.level == :fail))
    end
  end

  describe "non-402 and dual-rail captures" do
    test "HTTP 200 or 404 without payment challenge fails and builds actionable report_prefill" do
      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://api.exa.ai/search",
          method: "GET",
          status: 404,
          headers: %{"content-type" => ["application/json"]},
          body: ~s({"error":"Not Found"}),
          latency_ms: 60,
          now: @now,
          preflight: %{status: 404, headers: %{}}
        })

      assert result.verdict == :fail
      assert result.detected_protocols == []
      assert Enum.any?(result.checks, &(&1.code == "not_402" and &1.level == :fail))
      assert Enum.any?(result.checks, &(&1.code == "no_payment_challenge" and &1.level == :fail))
      assert result.report_prefill.site == "api.exa.ai"
      assert String.contains?(result.report_prefill.title, "HTTP 404")
    end

    test "dual-rail x402 + MPP response detects both protocols and emits dual_protocol pass" do
      x402_payload = %{
        "x402Version" => 2,
        "accepts" => [
          %{
            "scheme" => "exact",
            "network" => "eip155:8453",
            "asset" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "payTo" => "0x1111111111111111111111111111111111111111",
            "amount" => "10000"
          }
        ]
      }

      mpp_req = encode_b64_json(%{"amount" => "10000", "currency" => "USDC.e"})

      result =
        PaymentEndpoint.analyze_wire(%{
          url: "https://dual.example.com/api",
          method: "POST",
          status: 402,
          headers: %{
            "payment-required" => [encode_b64_json(x402_payload)],
            "www-authenticate" => [
              mpp_header(%{
                "id" => "mpp_dual",
                "method" => "tempo",
                "intent" => "charge",
                "expires" => "2026-11-26T20:10:00Z",
                "request" => mpp_req
              })
            ],
            "cache-control" => ["no-store"],
            "vary" => ["Authorization"],
            "access-control-expose-headers" => ["PAYMENT-REQUIRED, WWW-Authenticate"]
          },
          body: "",
          latency_ms: 50,
          now: @now
        })

      assert result.verdict == :pass
      assert result.detected_protocols == ["x402", "mpp"]
      assert Enum.any?(result.checks, &(&1.code == "dual_protocol" and &1.level == :pass))
    end
  end
end
