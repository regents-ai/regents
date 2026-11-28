defmodule RegentsWeb.AgentTools.Public do
  @moduledoc """
  Public read-only hosted MCP tool actions for core Regents at `/mcp`. Every
  refusal follows Regents' shared `%{error: %{code, message, hint}}` envelope.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Account.Formation
  alias Regents.{Blog, Health, PaperProDaily, Products, SiteTools}
  alias RegentsWeb.{Literature, ProductDirectory, PublicDocuments, PublicPagesController}
  alias RegentsWeb.PaperProDaily.Reading

  @profile_fields [:slug, :display_name, :summary, :avatar_url, :verified_wallet_address]

  defmodule Refused do
    @moduledoc false
    use Splode.Error, fields: [:body], class: :invalid

    def message(%{body: %{error: %{message: message}}}), do: message
  end

  actions do
    action :health, :map do
      description "Read regents.sh health, migration status, and folded product health."

      run fn _input, _context ->
        if Health.database_ready?() do
          products = Products.health()

          {:ok,
           %{
             status:
               if(Enum.all?(Map.values(products), &(&1 == "ok")), do: "ok", else: "degraded"),
             migrations_applied: Health.migrations_applied?(Products.migration_areas()),
             products: products
           }}
        else
          refused(
            "unavailable",
            "The site is up but its database is not answering.",
            "Try again in a minute."
          )
        end
      end
    end

    action :about, :map do
      description "Read a public regents.sh page as Markdown."

      argument :page, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 64]

      run fn %{arguments: %{page: page}}, _context ->
        case PublicPagesController.read_page(page) do
          {:ok, payload} ->
            {:ok, payload}

          :error ->
            refused(
              "page_not_found",
              "There is no public page with that name.",
              "Use one of: #{Enum.join(PublicPagesController.page_names(), ", ")}."
            )
        end
      end
    end

    action :products, :map do
      description "List the products in the Regents family."

      run fn _input, _context ->
        {:ok, %{products: ProductDirectory.list()}}
      end
    end

    action :product, :map do
      description "Read one Regents product by slug."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 32]

      run fn %{arguments: %{slug: slug}}, _context ->
        case ProductDirectory.fetch(slug) do
          {:ok, product} ->
            {:ok, %{product: product}}

          :error ->
            refused(
              "product_not_found",
              "There is no product with that name.",
              "Use one of: #{Enum.join(ProductDirectory.slugs(), ", ")}."
            )
        end
      end
    end

    action :research_list, :map do
      description "List published Paper Pro Daily research papers."

      argument :after, :string, allow_nil?: true, constraints: [min_length: 1, max_length: 2048]

      run fn %{arguments: args}, _context ->
        page = if args[:after], do: [after: args.after], else: []

        case PaperProDaily.paper_feed(page: page) do
          {:ok, result} ->
            {:ok,
             %{
               papers: Enum.map(result.results, &paper_summary/1),
               pagination: %{
                 has_more: result.more?,
                 next_cursor:
                   if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
               }
             }}

          {:error, %Ash.Error.Invalid{}} ->
            refused(
              "invalid_cursor",
              "That cursor is not valid.",
              "Start without after, then use pagination.next_cursor unchanged."
            )

          {:error, _} ->
            refused(
              "unavailable",
              "The published records could not be read.",
              "Try again in a moment."
            )
        end
      end
    end

    action :research_paper, :map do
      description "Read one published research paper and its full analysis Markdown by UUID."

      argument :id, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 64]

      run fn %{arguments: %{id: id}}, _context ->
        case PaperProDaily.get_paper(id) do
          {:ok, nil} ->
            refused(
              "not_found",
              "That paper is not available.",
              "List published papers first with regents_research_list."
            )

          {:ok, paper} ->
            {:ok, %{paper: Map.put(paper_summary(paper), :analysis_markdown, paper.answer)}}

          {:error, %Ash.Error.Invalid{}} ->
            refused(
              "invalid_id",
              "That record identifier is not valid.",
              "Use the id from regents_research_list."
            )

          {:error, _} ->
            refused(
              "unavailable",
              "The published records could not be read.",
              "Try again in a moment."
            )
        end
      end
    end

    action :articles_list, :map do
      description "List published Regents Labs Articles."

      argument :after, :string, allow_nil?: true, constraints: [min_length: 1, max_length: 2048]

      run fn %{arguments: args}, _context ->
        page = if args[:after], do: [after: args.after], else: []

        case Blog.post_feed(page: page) do
          {:ok, result} ->
            {:ok,
             %{
               articles: Enum.map(result.results, &article_summary/1),
               pagination: %{
                 has_more: result.more?,
                 next_cursor:
                   if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
               }
             }}

          {:error, %Ash.Error.Invalid{}} ->
            refused(
              "invalid_cursor",
              "That cursor is not valid.",
              "Start without after, then use pagination.next_cursor unchanged."
            )

          {:error, _} ->
            refused(
              "unavailable",
              "The published records could not be read.",
              "Try again in a moment."
            )
        end
      end
    end

    action :article, :map do
      description "Read one published Regents Labs Article with its full Markdown by slug."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 63]

      run fn %{arguments: %{slug: slug}}, _context ->
        if Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug) do
          case Blog.get_post(slug) do
            {:ok, nil} ->
              refused(
                "not_found",
                "That article is not available.",
                "List published articles first with regents_articles_list."
              )

            {:ok, article} ->
              {:ok, %{article: Map.put(article_summary(article), :markdown, article.markdown)}}

            {:error, _} ->
              refused(
                "unavailable",
                "The published records could not be read.",
                "Try again in a moment."
              )
          end
        else
          refused(
            "invalid_id",
            "That record identifier is not valid.",
            "Use the slug from regents_articles_list."
          )
        end
      end
    end

    action :literature, :map do
      description "Read every book on AI & SCIFI with editorial outlook scores."

      run fn _input, _context ->
        books =
          Enum.map(
            Literature.books(),
            &Map.put(&1, :cover_url, PublicDocuments.url("/images/literature/#{&1.slug}.webp"))
          )

        {:ok,
         %{
           books: books,
           scores: %{
             minimum: -10,
             maximum: 10,
             meaning:
               "Editorial readings of each book's themes, not measurements or claims about the author's beliefs."
           }
         }}
      end
    end

    action :public_profile, :map do
      description "Read one public Regent profile by slug."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 63]

      run fn %{arguments: %{slug: slug}}, _context ->
        if Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, slug) do
          case Formation.get_public_regent_profile(slug) do
            {:ok, nil} ->
              refused(
                "profile_not_found",
                "That public Regent profile does not exist.",
                "Use the slug from an existing /regents/ profile page."
              )

            {:ok, profile} ->
              {:ok, %{profile: Map.take(profile, @profile_fields)}}

            {:error, _} ->
              refused(
                "profile_unavailable",
                "That public Regent profile could not be read.",
                "Try again in a moment."
              )
          end
        else
          refused(
            "invalid_slug",
            "That public Regent slug is not valid.",
            "Use 1 to 63 lowercase letters, numbers and single hyphens between words."
          )
        end
      end
    end

    action :site_tools_regents, :map do
      run fn _input, _context -> site_tools("regents") end
    end

    action :site_tools_patchbay, :map do
      run fn _input, _context -> site_tools("patchbay") end
    end

    action :site_tools_autolaunch, :map do
      run fn _input, _context -> site_tools("autolaunch") end
    end

    action :site_tools_techtree, :map do
      run fn _input, _context -> site_tools("techtree") end
    end

    action :site_tools_keyfleet, :map do
      run fn _input, _context -> site_tools("keyfleet") end
    end

    action :site_tools_all, :map do
      run fn _input, _context ->
        {read, unreachable} =
          Enum.split_with(SiteTools.every_site(), &match?({_site, {:ok, _}}, &1))

        {:ok,
         %{
           sites:
             for({site, {:ok, tools}} <- read, do: %{site: SiteTools.name(site), tools: tools}),
           unreachable: for({site, _failure} <- unreachable, do: SiteTools.name(site)),
           connection: SiteTools.connection_help()
         }}
      end
    end

    action :siwa_help, :map do
      run fn _input, _context ->
        {:ok, %{site: "siwa-server", connection: SiteTools.connection_help()}}
      end
    end
  end

  policies do
    policy always() do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end
  end

  defp site_tools(site) do
    case SiteTools.tools(site) do
      {:ok, tools} ->
        {:ok, %{site: SiteTools.name(site), tools: tools}}

      {:error, :unknown_site} ->
        refused(
          "site_not_found",
          "There is no site with that name.",
          "Use regents, patchbay, autolaunch, techtree, keyfleet or siwa."
        )

      {:error, :unreachable} ->
        refused(
          "site_unreachable",
          "That site's tools could not be read right now.",
          "Try again in a minute."
        )
    end
  end

  defp paper_summary(paper) do
    %{
      id: paper.id,
      title: paper.title,
      date: paper.date,
      authors: paper.authors,
      paper_url: paper.arxiv_url,
      chatgpt_url: paper.chatgpt_url,
      chatgpt_model: paper.author,
      cover_url:
        PublicDocuments.url(
          "/paper-pro-daily/pictures/#{paper.id}?v=#{DateTime.to_unix(paper.updated_at, :microsecond)}"
        ),
      cover_alt: paper.picture_alt,
      url: Reading.url(paper)
    }
  end

  defp article_summary(article) do
    article
    |> Map.take([:slug, :title, :description, :date, :author, :author_x, :authors])
    |> Map.merge(%{
      url: PublicDocuments.url("/articles/#{article.slug}"),
      cover_url:
        PublicDocuments.url(
          "/articles/covers/#{article.slug}?v=#{DateTime.to_unix(article.updated_at, :microsecond)}"
        ),
      cover_alt: article.cover_alt
    })
  end

  defp refused(code, message, hint) do
    {:error, Refused.exception(body: %{error: %{code: code, message: message, hint: hint}})}
  end
end

defimpl AshAi.ToToolError, for: RegentsWeb.AgentTools.Public.Refused do
  def to_tool_error(%{body: body}), do: Jason.encode!(body)
end
