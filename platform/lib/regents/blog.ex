defmodule Regents.Blog do
  @moduledoc "Folder-authored posts saved in the database and published at /articles."
  use Ash.Domain

  resources do
    resource Regents.Blog.Post do
      define :put_post, action: :put
      define :publish_post, action: :publish
      define :list_posts, action: :list
      define :get_post, action: :post, args: [:slug], get?: true, not_found_error?: false
      define :get_cover, action: :cover, args: [:slug], get?: true, not_found_error?: false
    end
  end

  @doc "Articles uses the same verified Privy accounts as Credits administration."
  defdelegate admin?(account), to: Regents.Credits
end
