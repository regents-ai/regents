defmodule RegentsWeb.CloakHardeningTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn
  import Plug.Test

  alias RegentsWeb.{Cloak, Docs, Endpoint, ProductDirectory, PublicDocuments, SearchLive}
  alias RegentsWeb.Cloak.CloakLive

  setup_all do
    {:ok, _} = Application.ensure_all_started(:phoenix)

    children =
      if(Process.whereis(Regents.PubSub), do: [], else: [{Phoenix.PubSub, name: Regents.PubSub}]) ++
        if(Process.whereis(Regents.RateLimiter), do: [], else: [Regents.RateLimiter]) ++
        if(Process.whereis(RegentsWeb.Endpoint),
          do: [],
          else: [{RegentsWeb.Endpoint, server: false}]
        )

    case children do
      [] ->
        :ok

      list ->
        {:ok, sup} = Supervisor.start_link(list, strategy: :one_for_one)
        on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)
        :ok
    end
  end

  describe "A1: Immutable release tag & checksums" do
    test "fallback release pins DMG, SHA256SUMS.txt, release page, and hash to one immutable tag" do
      rel = Cloak.release_checksums()

      assert is_binary(rel.tag) and rel.tag != ""
      refute String.contains?(String.downcase(rel.tag), "latest")

      assert rel.dmg_url ==
               "https://github.com/regents-ai/cloak/releases/download/#{rel.tag}/#{rel.dmg_filename}"

      assert rel.sums_url ==
               "https://github.com/regents-ai/cloak/releases/download/#{rel.tag}/SHA256SUMS.txt"

      assert rel.release_url == "https://github.com/regents-ai/cloak/releases/tag/#{rel.tag}"
      assert Cloak.download_url(rel) == rel.dmg_url
      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, rel.dmg_sha256)

      refute String.contains?(rel.dmg_url, "/releases/latest/")
      refute String.contains?(rel.sums_url, "/releases/latest/")
      refute String.contains?(rel.release_url, "/releases/latest/")
    end

    test "parse_release_checksums/1 accepts valid immutable tag metadata and rejects moving/malformed payloads" do
      valid_hash = String.duplicate("a", 64)

      assert {:ok, parsed} =
               Cloak.parse_release_checksums(%{
                 "tag" => "0.2.8-310",
                 "release" => "0.2.8",
                 "dmg_filename" => "Regents-Cloak-0.2.8-310.dmg",
                 "dmg_sha256" => String.upcase(valid_hash),
                 "team_id" => "367G3Z7G3J"
               })

      assert parsed.dmg_url ==
               "https://github.com/regents-ai/cloak/releases/download/0.2.8-310/Regents-Cloak-0.2.8-310.dmg"

      assert parsed.sums_url ==
               "https://github.com/regents-ai/cloak/releases/download/0.2.8-310/SHA256SUMS.txt"

      assert parsed.release_url == "https://github.com/regents-ai/cloak/releases/tag/0.2.8-310"
      assert parsed.dmg_sha256 == valid_hash

      assert :error =
               Cloak.parse_release_checksums(%{
                 "tag" => "latest",
                 "release" => "0.2.8",
                 "dmg_filename" => "Regents-Cloak-0.2.8.dmg",
                 "dmg_sha256" => valid_hash
               })

      assert :error =
               Cloak.parse_release_checksums(%{
                 "tag" => "../evil",
                 "release" => "0.2.8",
                 "dmg_filename" => "Regents-Cloak-0.2.8.dmg",
                 "dmg_sha256" => valid_hash
               })

      assert :error =
               Cloak.parse_release_checksums(%{
                 "tag" => "0.2.8-310",
                 "release" => "0.2.8",
                 "dmg_filename" => "../../bad.dmg",
                 "dmg_sha256" => valid_hash
               })

      assert :error =
               Cloak.parse_release_checksums(%{
                 "tag" => "0.2.8-310",
                 "release" => "0.2.8",
                 "dmg_filename" => "Regents-Cloak-0.2.8-310.dmg",
                 "dmg_sha256" => "not-a-sha256"
               })
    end

    test "Cloak Markdown and install Markdown never emit /releases/latest/ links" do
      rel = Cloak.release_checksums()
      cloak_md = Cloak.markdown()
      install_md = Cloak.install_markdown()

      refute String.contains?(cloak_md, "/releases/latest/")
      refute String.contains?(install_md, "/releases/latest/")
      assert String.contains?(cloak_md, rel.dmg_url)
      assert String.contains?(cloak_md, rel.sums_url)
      assert String.contains?(install_md, rel.dmg_url)
      assert String.contains?(install_md, rel.sums_url)
      assert String.contains?(install_md, rel.dmg_sha256)
    end
  end

  describe "A2: /app Markdown 200" do
    test "GET /app with Accept: text/markdown returns 200 public Markdown directory" do
      original = Application.get_env(:regents, :app_surfaces)
      Application.put_env(:regents, :app_surfaces, true)

      on_exit(fn ->
        if is_nil(original),
          do: Application.delete_env(:regents, :app_surfaces),
          else: Application.put_env(:regents, :app_surfaces, original)
      end)

      conn =
        conn(:get, "/app")
        |> put_req_header("accept", "text/markdown")
        |> Endpoint.call(Endpoint.init([]))

      assert conn.status == 200
      assert [content_type | _] = get_resp_header(conn, "content-type")
      assert String.starts_with?(content_type, "text/markdown")

      assert Enum.any?(
               get_resp_header(conn, "vary"),
               &String.contains?(String.downcase(&1), "accept")
             )

      assert String.contains?(conn.resp_body, "# Regents Labs — App Overview")
      assert String.contains?(conn.resp_body, "Cloak")
      assert String.contains?(conn.resp_body, "/api/v1/products")

      meta = PublicDocuments.metadata("/app", "Overview", "Test")
      assert meta.markdown? == true
    end
  end

  describe "A3 & A5: Shared Cloak taxonomy, version sync, and honest privacy boundaries" do
    test "/api/v1/products/cloak derives the 3 pillars and live version from RegentsWeb.Cloak and conforms to OpenAPI Product schema" do
      rel = Cloak.release_checksums()
      {:ok, entry} = ProductDirectory.fetch("cloak")

      assert entry.slug == "cloak"
      assert entry.headline == Enum.join(Cloak.heading(), " ")
      assert entry.summary == Cloak.subtitle()
      assert String.contains?(entry.kicker, Cloak.version_label(rel))
      assert String.contains?(entry.launch_notice, rel.tag)

      assert Enum.map(entry.cards, & &1.name) == [
               "Local AI",
               "Private Cloud Inference",
               "Inference Serving"
             ]

      schema =
        PublicDocuments.openapi()
        |> get_in(["components", "schemas", "Product"])

      allowed_keys = schema |> Map.fetch!("properties") |> Map.keys() |> MapSet.new()
      required_keys = schema |> Map.fetch!("required") |> MapSet.new()
      entry_keys = entry |> Map.keys() |> Enum.map(&Atom.to_string/1) |> MapSet.new()

      assert MapSet.subset?(required_keys, entry_keys)
      assert MapSet.subset?(entry_keys, allowed_keys)

      # Verify HTTP JSON endpoint returns the exact synchronized payload
      conn =
        conn(:get, "/api/v1/products/cloak")
        |> put_req_header("accept", "application/json")
        |> Endpoint.call(Endpoint.init([]))

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      product_json = Map.fetch!(body, "product")

      assert Enum.map(product_json["cards"], & &1["name"]) == [
               "Local AI",
               "Private Cloud Inference",
               "Inference Serving"
             ]

      assert String.contains?(product_json["kicker"], Cloak.version_label(rel))
    end

    test "CloakLive HTML renders pinned tag links, CopyCommand fallback hooks, and honest privacy layers" do
      rel = Cloak.release_checksums()

      page_html = render_component(&CloakLive.page/1, %{})

      download_html =
        render_component(&CloakLive.download/1, %{
          subscribe_status: :idle,
          subscribe_error: nil,
          subscribe_email: "",
          release_tag: rel.tag
        })

      install_html = render_component(&CloakLive.install/1, %{})

      for html <- [page_html, download_html, install_html] do
        refute String.contains?(html, "/releases/latest/")
        assert String.contains?(html, rel.sums_url)
        assert String.contains?(html, rel.dmg_sha256)
        assert String.contains?(html, ~s(phx-hook="CopyCommand"))
        refute String.contains?(html, ~s(phx-hook=".CopyCommand"))
        refute String.contains?(html, ~s(phx-hook=".CopyDownloadCommand"))
      end

      assert String.contains?(download_html, ~s(data-download-url="#{rel.dmg_url}"))
      assert String.contains?(download_html, ~s(href="#{rel.dmg_url}"))
      assert String.contains?(page_html, "Local Rewriter")
      assert String.contains?(page_html, "CloakDoor Privacy Shield")
      assert String.contains?(page_html, "not yet neural NER")
      assert String.contains?(page_html, "Local Mode only")
    end

    test "Cloak landing Markdown, docs reference, wallets doc, and product directory separate privacy layers honestly" do
      rel = Cloak.release_checksums()
      version = Cloak.version_label(rel)
      cloak_md = Cloak.markdown()
      ref_md = Docs.markdown(Docs.Pages.page("/docs/cloak/reference"))
      wallets_md = Docs.markdown(Docs.Pages.page("/docs/cloak/wallets"))
      {:ok, product} = ProductDirectory.fetch("cloak")

      for text <- [cloak_md, ref_md] do
        assert String.contains?(text, "Local Rewriter")
        assert String.contains?(text, "CloakDoor Privacy Shield")
        assert String.contains?(text, "not yet neural NER")
        assert String.contains?(text, "Local Mode only")
      end

      assert String.contains?(ref_md, version)
      assert String.contains?(ref_md, rel.tag)
      assert String.contains?(ref_md, rel.sums_url)
      assert String.contains?(wallets_md, version)
      assert String.contains?(wallets_md, rel.tag)
      refute String.contains?(ref_md, "v0.2.6 Beta")
      refute String.contains?(wallets_md, "v0.2.6 Beta")

      joined_product = Jason.encode!(product)
      assert String.contains?(joined_product, "Local Rewriter")
      assert String.contains?(joined_product, "CloakDoor Privacy Shield")
      assert String.contains?(joined_product, "not yet neural NER")
      assert String.contains?(joined_product, "Local Mode only")
    end
  end

  describe "A6: Search ranking and /capabilities.json private_write_available parity" do
    test "searching Cloak from /app ranks /cloak first ahead of generic docs" do
      {:ok, docs_hits} = Docs.search_matches("Cloak")
      ranked = SearchLive.rank("Cloak", "regents", docs_hits)

      assert [first | _rest] = ranked
      assert first.path == "/cloak"
      assert first.label == "Cloak"

      top_four_products = ranked |> Enum.take(4) |> Enum.map(& &1.product)
      assert Enum.all?(top_four_products, &(&1 == "cloak"))
    end

    test "GET /capabilities.json private_write_available matches actual tool flags" do
      conn =
        conn(:get, "/capabilities.json")
        |> put_req_header("accept", "application/json")
        |> Endpoint.call(Endpoint.init([]))

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)

      has_private_write? =
        Enum.any?(body["tools"], fn tool ->
          (tool["state_changing"] == true or tool["effect"] == "write") and
            tool["authentication"] != "public"
        end)

      assert has_private_write? == true
      assert body["private_write_available"] == true
    end
  end
end
