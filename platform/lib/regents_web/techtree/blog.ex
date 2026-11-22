defmodule RegentsWeb.Techtree.Blog do
  @moduledoc "Techtree's repository-owned, release-safe blog catalog."
  use RegentBlog.Catalog, root: Application.app_dir(:regents, "priv/techtree/blog")
end
