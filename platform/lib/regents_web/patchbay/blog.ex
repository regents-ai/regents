defmodule RegentsWeb.Patchbay.Blog do
  @moduledoc """
  Patchbay's blog catalog: the posts in `priv/patchbay/blog`, built into the
  release. Their pictures are under `blog/images/patchbay` at the repository
  root, which `mix regent_blog.assets` stages as `/images/blog/patchbay/…`.
  """
  use RegentBlog.Catalog, root: Application.app_dir(:regents, "priv/patchbay/blog")
end
