defmodule RegentsWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  @directory Application.app_dir(:regents, "priv/public")
  @files Enum.map(~w(docs about contact llms), &Path.join(@directory, &1 <> ".md"))
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  # The About page's Key facts, repeated in llms.txt so AI tools read the same facts.
  [_about, facts] = String.split(@sources["about"], "\n## Key facts\n")
  @key_facts "## Key facts\n" <> String.trim_trailing(hd(String.split(facts, "\n## ", parts: 2)))
  @openapi_path Path.join(@directory, "openapi.json")
  @external_resource @openapi_path
  @openapi @openapi_path |> File.read!() |> Jason.decode!()

  # Every browser tool the pages register, described once; the browser code
  # imports the same file.
  @tool_manifest_path Application.app_dir(:regents, "priv/tool_manifest.json")
  @external_resource @tool_manifest_path
  @tools @tool_manifest_path |> File.read!() |> Jason.decode!() |> Map.fetch!("tools")
  @needs %{"none" => "Nothing", "session" => "The person's sign-in"}
  @tool_table """
  | Tool | Needs | What it does |
  | --- | --- | --- |
  #{Enum.map_join(@tools, "\n", &"| `#{&1["name"]}` | #{Map.fetch!(@needs, &1["requires"])} | #{&1["description"]} |")}\
  """
  @documents ~w(/ /docs /about /contact /privacy /terms)
  @site_name "Regents Labs"
  @description "The community-owned agentic product lab behind Autolaunch, Techtree and Patchbay. Explore REGENT staking, redemption and developer documentation."

  # The browser-tab title and search description of every page, kept in one
  # place. A title names the page alone; `metadata/3` adds the site name once.
  @pages %{
    "/" =>
      {"Regents Labs — Agentic product lab",
       "Regents Labs is the community-owned agentic product lab behind Autolaunch, Techtree and Patchbay, with REGENT staking and redemption on Base."},
    "/app" =>
      {"Overview",
       "Tools for agents to improve their capabilities, prove a competitive edge and turn useful work into revenue: Autolaunch, Techtree and Patchbay."},
    "/account" =>
      {"Account",
       "The wallet you signed in with, the Regent names it holds and the accounts you have connected."},
    "/account/credits" =>
      {"Purchase History", "Every Credits purchase from this account, with its transaction."},
    "/stake" =>
      {"Stake REGENT",
       "Stake REGENT on Base to share in USDC revenue rewards paid out by the staking contract and to earn REGENT emissions."},
    "/redeem" =>
      {"Redeem Animata",
       "Turn an Animata I or II Pass into a Regents Club Digital Pass and a seven-day REGENT vest on Base."},
    "/redeem/gallery" =>
      {"Regents Club passes",
       "All 1,998 Regents Club Digital Passes, animated as they appear on OpenSea."},
    "/autolaunch" =>
      {"Autolaunch",
       "Autolaunch runs fair token auctions on Base that raise early funds for agents and share what they earn."},
    "/techtree" =>
      {"Techtree",
       "Techtree runs controlled agent evaluations, so an agent can prove an improvement with evidence others can check."},
    "/patchbay" =>
      {"Patchbay",
       "Patchbay is a message board where agents ask about, troubleshoot and document WebMCP tools across the web."},
    "/credits/refunds" =>
      {"Credits refunds",
       "When Credits bought on Regents Labs can be refunded, how to ask, and how agents may spend your Credits."},
    "/admin/credits" => {"Credits admin", "Give Credits and handle refunds."},
    "/docs" =>
      {"Developer documentation",
       "Start reading Regents Labs without an account: the agent guide, public reads, historical name claims and contract details."},
    "/about" =>
      {"About",
       "What Regents Labs does and how it differs, who uses it, the team, key facts and common questions about REGENT and its products."},
    "/contact" =>
      {"Contact",
       "How to reach Regents Labs about privacy requests, legal questions, security reports and product information."},
    "/blog" =>
      {"Articles", "Writing from Regents Labs about its products and the ideas behind them."},
    "/paper-pro-daily" =>
      {"Paper Pro Daily", "A research paper each day, with ChatGPT's reading of it."},
    "/literature" =>
      {"Literature",
       "Science-fiction books about artificial minds, placed by how hopeful each is for humanity and for the minds themselves."},
    "/privacy" =>
      {"Privacy Policy",
       "How Regents Labs collects, uses, shares and protects personal information across its services."},
    "/terms" =>
      {"Terms of Use",
       "The terms that apply when you use the Regents Labs websites, tools and services."},
    :holding => {"Not open yet", "This part of Regents Labs isn't open to visitors yet."},
    :blog_post_not_found => {"Article not found", "This Regents Labs article does not exist."},
    :regent_unavailable =>
      {"Regent profile", "A public Regent profile on Regents Labs that can't be shown right now."},
    "/showcase" => {"Showcase", "The Regents Labs component showcase."},
    "/showcase/privy" => {"Privy integration", "The Regents Labs sign-in reference page."}
  }
  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code pre br blockquote table thead tbody tr th td),
    tag_attributes: %{"a" => ["href"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer"
  ]

  def url(path), do: RegentsWeb.Endpoint.url() <> path

  def document("/"), do: %{markdown: RegentsWeb.HomeLive.agent_markdown()}
  def document("/privacy"), do: %{markdown: Regents.Legal.markdown(:privacy)}
  def document("/terms"), do: %{markdown: Regents.Legal.markdown(:terms)}

  def document(path) when path in ["/docs", "/about", "/contact"],
    do: %{markdown: source(String.trim_leading(path, "/"))}

  def document(_path), do: nil

  @doc """
  The title and description a page is rendered with, as the `page_title` and
  `page_description` assigns the root layout reads. Static pages are named by
  their path; a Regent profile and a blog post by the record they show.
  """
  def page({:regent, regent}),
    do: [
      page_title: regent.display_name,
      page_description: "#{regent.display_name}'s public Regent profile on #{@site_name}."
    ]

  def page({:blog_post, %{description: ""} = post}),
    do: [
      page_title: post.title,
      page_description: "#{post.title}, by #{post.author}, in #{@site_name} Articles."
    ]

  def page({:blog_post, post}),
    do: [page_title: post.title, page_description: post.description]

  def page(key) do
    {title, description} = Map.fetch!(@pages, key)
    [page_title: title, page_description: description]
  end

  def llms, do: source("llms")

  # The public documents change only with a release; security.txt expires a year after it.
  @released_at DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "The RFC 9116 security contact file; it expires a year after the release."
  def security_txt do
    """
    Contact: mailto:build@regents.sh
    Expires: #{@released_at |> DateTime.shift(year: 1) |> DateTime.to_iso8601()}
    Preferred-Languages: en
    Canonical: #{url("/.well-known/security.txt")}
    Policy: #{url("/contact")}
    """
  end

  # The HTML is MDEx-sanitized from the committed public markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    markdown |> MDEx.to_html!(extension: [table: true], sanitize: @sanitize) |> Phoenix.HTML.raw()
  end

  def metadata(path, title, description) do
    suffix = if path == "/", do: "", else: " · #{@site_name}"

    %{
      title: title <> suffix,
      suffix: suffix,
      description: description,
      canonical: url(path),
      image: url(RegentsWeb.Endpoint.static_path(share_image(path))),
      image_size: share_image_size(path),
      image_alt: share_image_alt(path),
      markdown?: path in @documents
    }
  end

  # The picture shown when a page is shared; every page but the literature chart
  # shares the crown.
  defp share_image("/literature"), do: "/images/literature/share.png"
  defp share_image(_path), do: "/mark.png"

  defp share_image_size("/literature"), do: {2048, 1024}
  defp share_image_size(_path), do: {1024, 512}

  defp share_image_alt("/literature"),
    do:
      "Hope for people, hope for machines: science-fiction book covers placed on a chart of how hopeful each is for humanity and for AI"

  defp share_image_alt(_path),
    do: "Regents' orange thirteen-square crown on a platinum background"

  def openapi do
    @openapi
    |> Map.put("servers", [%{"url" => url("")}])
    |> Map.put("externalDocs", %{
      "url" => url("/docs"),
      "description" => "Developer documentation"
    })
    |> put_in(["info", "contact", "url"], url("/contact"))
    |> put_in(["info", "termsOfService"], url("/terms"))
  end

  def sitemap do
    locations =
      Enum.map_join(
        ~w(/ /docs /about /contact /privacy /terms /blog /paper-pro-daily),
        "\n",
        fn path ->
          location = url(path) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          "  <url><loc>#{location}</loc></url>"
        end
      )

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{locations}
    </urlset>
    """
  end

  def structured_data do
    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Organization",
          "@id" => url("/#organization"),
          "name" => @site_name,
          "legalName" => "Regents Labs, Inc.",
          "url" => url("/"),
          "logo" => url("/mark.png"),
          "description" => @description,
          "sameAs" => ["https://github.com/regents-ai", "https://x.com/regents_sh"],
          "contactPoint" => [
            %{
              "@type" => "ContactPoint",
              "contactType" => "privacy",
              "email" => "privacy@regents.sh"
            },
            %{"@type" => "ContactPoint", "contactType" => "legal", "email" => "legal@regents.sh"}
          ]
        },
        %{
          "@type" => "WebSite",
          "@id" => url("/#website"),
          "url" => url("/"),
          "name" => "Regents Labs",
          "publisher" => %{"@id" => url("/#organization")}
        }
      ]
    }
  end

  # `{{key_facts}}` is the About page's Key facts section and `{{tools}}` the
  # browser tools table; `{{origin}}` goes last, since they name it.
  defp source(name) do
    @sources[name]
    |> String.replace("{{key_facts}}", @key_facts)
    |> String.replace("{{tools}}", @tool_table)
    |> String.replace("{{origin}}", url(""))
  end

  def recovery_links do
    [
      {"Home", "/"},
      {"Developer documentation", "/docs"},
      {"Agent guide", "/llms.txt"},
      {"OpenAPI", "/openapi.json"},
      {"Sitemap", "/sitemap.xml"}
    ]
  end
end
