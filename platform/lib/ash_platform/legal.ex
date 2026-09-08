defmodule AshPlatform.Legal do
  @moduledoc """
  The Privacy Policy and Terms of Use as they are served on the public site.
  """

  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code br),
    tag_attributes: %{"a" => ["href"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer"
  ]

  @priv Application.app_dir(:ash_platform, "priv/legal")
  @privacy_path Path.join(@priv, "privacy.md")
  @terms_path Path.join(@priv, "terms.md")
  @external_resource @privacy_path
  @external_resource @terms_path

  @sources %{
    privacy: %{title: "Privacy Policy", markdown: File.read!(@privacy_path)},
    terms: %{title: "Terms of Use", markdown: File.read!(@terms_path)}
  }

  def document(id) when is_map_key(@sources, id) do
    spec = @sources[id]
    %{id: id, title: spec.title, html: to_safe_html(spec.markdown)}
  end

  # The HTML is MDEx-sanitized from the committed legal markdown.
  # sobelow_skip ["XSS.Raw"]
  defp to_safe_html(markdown) do
    markdown
    |> MDEx.to_html!(sanitize: @sanitize)
    |> Phoenix.HTML.raw()
  end
end
