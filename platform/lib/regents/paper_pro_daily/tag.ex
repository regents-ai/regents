defmodule Regents.PaperProDaily.Tag do
  @moduledoc "The topics a paper on /paper-pro-daily is filed under, in the order the page lists them."
  use Ash.Type.Enum,
    values:
      ~w(Autoresearch Swarms Self-Improvement Harnesses Training Memory Evaluation Safety Economics Science)
end
