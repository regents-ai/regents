defmodule Regents.PaperProDaily do
  @moduledoc "The papers on /paper-pro-daily, one a day, kept in the database so a new one shows without a release."
  use Ash.Domain

  resources do
    resource Regents.PaperProDaily.Paper do
      define :put_paper, action: :put
      define :list_papers, action: :list
      define :export_papers, action: :export
      define :get_picture, action: :picture, args: [:date], get?: true, not_found_error?: false
    end
  end
end
