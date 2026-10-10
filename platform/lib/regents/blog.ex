defmodule Regents.Blog do
  @moduledoc "Folder-authored posts saved in the database and published at /blog."
  use Ash.Domain

  resources do
    resource Regents.Blog.Post do
      define :put_post, action: :put
      define :list_posts, action: :list
      define :get_post, action: :post, args: [:slug], get?: true, not_found_error?: false
      define :get_cover, action: :cover, args: [:slug], get?: true, not_found_error?: false
    end
  end
end
