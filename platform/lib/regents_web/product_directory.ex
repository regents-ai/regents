defmodule RegentsWeb.ProductDirectory do
  @moduledoc """
  The Regents product directory: what the /keyfleet, /patchbay, /techtree and
  /cloak pages show, read from the same content those pages render, and
  Autolaunch's entry from its own copy (`RegentsWeb.AutolaunchLive.content/0`).
  """

  alias RegentsWeb.{AutolaunchLive, ProductLive, PublicDocuments}

  @slugs ~w(keyfleet autolaunch patchbay techtree cloak)
  @listed [:slug, :name, :summary, :site, :page, :github]
  # A card's words and where it goes; its picture and colour are the page's own.
  @card_words [:name, :headline, :line, :action, :href]

  def slugs, do: @slugs

  @doc "Every product, in the order the site lists them."
  def list, do: Enum.map(@slugs, &(&1 |> product() |> Map.take(@listed)))

  @doc "Everything one product's page shows."
  def fetch(slug) when slug in @slugs, do: {:ok, product(slug)}
  def fetch(_slug), do: :error

  defp product("autolaunch"), do: with_page(AutolaunchLive.content(), "autolaunch")
  defp product("techtree"), do: with_page(ProductLive.content(:techtree), "techtree")
  defp product("patchbay"), do: with_page(ProductLive.content(:patchbay), "patchbay")
  defp product("keyfleet"), do: with_page(ProductLive.content(:keyfleet), "keyfleet")
  defp product("cloak"), do: with_page(cloak_content(), "cloak")

  defp cloak_content do
    page_url = PublicDocuments.url("/cloak")
    install_url = PublicDocuments.url("/cloak/install")
    docs_url = PublicDocuments.url("/docs/cloak/reference")

    %{
      name: "Cloak",
      domain: "regents.sh/cloak",
      site: page_url,
      github: "https://github.com/regents-ai/cloak",
      kicker: "regents.sh/cloak · Private AI for macOS",
      headline: "Choose what leaves your Mac.",
      summary:
        "Native macOS app for running AI locally on Apple Silicon or choosing explicitly how prompts reach remote models — with local prompt rewriting, Tor routing, hardware-verified NEAR enclaves, Token Inference, Anon V (zkAPI), a sealed Linux Pi coding agent, and a local OpenAI-compatible API.",
      cards: [
        %{
          name: "Local Mode",
          headline: "100% on this Mac",
          line:
            "Fast Apple Silicon MLX (Inkling 2 Mini) and Metal llama.cpp GGUF models with optional offline-only Local Access.",
          action: "Explore Cloak",
          href: page_url <> "#modes"
        },
        %{
          name: "NEAR AI Gateway",
          headline: "Hardware-verified cloud enclaves",
          line:
            "Verifies Intel TDX quotes and NVIDIA GPU verdicts on-device before E2EE v2 encryption to Qwen3.8-27B.",
          action: "Read docs",
          href: docs_url
        },
        %{
          name: "Token Inference",
          headline: "Tor + local prompt rewriting",
          line:
            "Pay per request via Venice AI (Base USDC x402 or API key) or Boundless on Tempo over per-conversation Tor circuits.",
          action: "Explore Cloak",
          href: page_url <> "#modes"
        },
        %{
          name: "Anon V (zkAPI)",
          headline: "Unlinkable one-time payment keys",
          line:
            "Pays each prompt over Tor with a fresh zero-knowledge credential from an Ethereum Mainnet ETH deposit.",
          action: "Explore Cloak",
          href: page_url <> "#modes"
        },
        %{
          name: "Local Agent Box",
          headline: "Sealed Linux microVM Pi agent",
          line:
            "Runs multi-step coding tasks inside a NIC-less Linux arm64 microVM with zero macOS file access and Tor-forced web egress.",
          action: "See Agent mode",
          href: page_url <> "#agent"
        },
        %{
          name: "Connected Apps",
          headline: "Local OpenAI-compatible gateway",
          line:
            "Point Cursor, Cline, Aider, or Python at 127.0.0.1:8742/v1 to rewrite user prompts locally and pay via Anon V over Tor.",
          action: "Read docs",
          href: docs_url
        }
      ],
      what_it_does: [
        %{
          title: "Four isolated chat modes",
          copy:
            "Every chat thread is self-contained and locks its mode on turn 1: Local, NEAR AI Gateway, Token Inference (Venice or Boundless), or Anon V (zkAPI).",
          status: "live",
          link: %{label: "Install Cloak", href: install_url}
        },
        %{
          title: "Local prompt rewriting, Tor & live cover traffic",
          copy:
            "Rephrases user text locally with Qwen 3.5 9B before leaving your Mac, routes cloud traffic through isolated Tor circuits, and toggles live cover traffic with zero restart.",
          status: "live",
          link: %{label: "Read Cloak docs", href: docs_url}
        },
        %{
          title: "Sealed Local Agent Box & Connected Apps",
          copy:
            "Run the built-in Pi coding agent inside a throwaway NIC-less Linux microVM, or connect existing Mac coding clients to http://127.0.0.1:8742/v1.",
          status: "live",
          link: %{label: "See Agent mode", href: page_url <> "#agent"}
        }
      ],
      about: [
        "Cloak lets you choose where an AI conversation runs, see what leaves your Mac, and understand what can link one request to another.",
        "It combines on-device Apple Silicon inference, client-verified NEAR hardware enclaves, Tor-routed Token Inference (Venice AI and Boundless), unlinkable Anon V (zkAPI) payments, opt-in offline Local Access, and a sealed Linux microVM agent in one native macOS app."
      ],
      audience: [
        "Mac users who want fast local AI with optional offline context that never touches a cloud provider.",
        "Developers and researchers who want Tor routing, local prompt rewriting, hardware-verified enclaves, or unlinkable zero-knowledge API payments.",
        "Teams running coding agents or OpenAI-compatible tools who want explicit privacy and sandbox boundaries."
      ],
      family:
        "Cloak is Regents Labs' native macOS private AI client. Its source code and signed releases are open on GitHub, and its privacy protections have not yet been independently audited.",
      agent_line:
        "Read regents.sh/docs/cloak/reference as Markdown and help me choose the right Cloak mode for my Mac.",
      launch_notice:
        "Signed, notarized builds for Apple Silicon Macs (macOS 26+). Privacy protections have not yet been independently audited.",
      tech_stack: [],
      start: %{label: "Install Cloak", href: install_url}
    }
  end

  defp with_page(content, slug) do
    Map.merge(content, %{
      slug: slug,
      page: PublicDocuments.url("/" <> slug),
      cards: Enum.map(content.cards, &Map.take(&1, @card_words))
    })
  end
end
