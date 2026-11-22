defmodule RegentsWeb.Autolaunch.Blog do
  @moduledoc "This product's repository-owned, release-safe blog catalog."
  use RegentBlog.Catalog, root: Application.app_dir(:regents, "priv/autolaunch/blog")
end
