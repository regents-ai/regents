defmodule Regents.Patchbay.WrittenPages do
  @moduledoc """
  The pages written once as Markdown and built into the release: About
  (`priv/patchbay/public/`), the Terms of Use (`priv/patchbay/legal/`) and the
  long-form agent guide (`priv/patchbay/public/docs_agents.md`). Each page answers
  both as HTML and as its Markdown, and the HTML starts below the first heading,
  since the page's own header carries the title.

  patchbay.help serves the Regents Labs Terms of Use, the text regents.sh serves,
  copied word for word from the Regents repository's `platform/priv/legal/terms.md`
  as it stood when patchbay.help took it.
  """

  @about_path Application.app_dir(:regents, "priv/patchbay/public/about.md")
  @guide_path Application.app_dir(:regents, "priv/patchbay/public/docs_agents.md")
  @terms_path Application.app_dir(:regents, "priv/patchbay/legal/terms.md")

  @external_resource @about_path
  @external_resource @guide_path
  @external_resource @terms_path

  # The document below its first heading.
  below_title = fn markdown, options ->
    document = MDEx.parse_document!(markdown, options)
    %{document | nodes: Enum.reject(document.nodes, &match?(%MDEx.Heading{level: 1}, &1))}
  end

  about = File.read!(@about_path)

  about_options = [
    extension: [table: true, inline_code_attributes: false],
    render: [unsafe: false]
  ]

  # The About page's text has its addresses cut out (`Regents.Patchbay.AddressText.html/1`).
  @about %{
    html: Regents.Patchbay.AddressText.html(below_title.(about, about_options)),
    markdown: about
  }

  terms = File.read!(@terms_path)
  terms_body = below_title.(terms, extension: [inline_code_attributes: false])
  @terms %{html: MDEx.to_html!(terms_body, render: [unsafe: false]), markdown: terms}

  @guide File.read!(@guide_path)

  @guide_options [
    extension: [table: true, header_id_prefix: "", inline_code_attributes: false],
    render: [unsafe: false]
  ]

  @type page :: %{html: term(), markdown: String.t()}

  @doc "About, its HTML as `Regents.Patchbay.AddressText` pieces."
  @spec about() :: page()
  def about, do: @about

  @doc "The Terms of Use."
  @spec terms() :: page()
  def terms, do: @terms

  @doc """
  The long-form agent guide the developers page carries, as Markdown without
  its title line, its addresses (`{{origin}}` in the file) starting with `origin`.
  """
  @spec agent_guide_markdown(String.t()) :: String.t()
  def agent_guide_markdown(origin) do
    @guide
    |> String.split("\n", parts: 2)
    |> List.last()
    |> String.trim()
    |> String.replace("{{origin}}", origin)
  end

  @doc "The same guide as HTML below its title, its addresses starting with `origin`."
  @spec agent_guide_html(String.t()) :: String.t()
  def agent_guide_html(origin) do
    document =
      @guide |> String.replace("{{origin}}", origin) |> MDEx.parse_document!(@guide_options)

    %{document | nodes: Enum.reject(document.nodes, &match?(%MDEx.Heading{level: 1}, &1))}
    |> MDEx.to_html!(@guide_options)
  end
end
