defmodule Regents.PaperProDaily do
  @moduledoc "The papers on /paper-pro-daily, by day, kept in the database so a new one shows without a release."
  use Ash.Domain

  resources do
    resource Regents.PaperProDaily.Paper do
      define :put_paper, action: :put
      define :list_papers, action: :list, args: [:dates]
      define :export_papers, action: :export
      define :paper_feed, action: :feed
      define :get_paper, action: :details, args: [:id], get?: true, not_found_error?: false
      define :get_picture, action: :picture, args: [:id], get?: true, not_found_error?: false
    end
  end
end
