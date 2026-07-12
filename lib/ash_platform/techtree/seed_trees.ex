defmodule AshPlatform.Techtree.SeedTrees do
  @moduledoc false

  @trees [
    %{
      slug: "genebench-pro-reference-lab",
      name: "GeneBench-Pro Reference Lab",
      description: "Reference evidence and methods for rigorous GeneBench-Pro work.",
      position: 1
    },
    %{
      slug: "question-forge-metaskills",
      name: "Question Forge Metaskills",
      description: "Reusable skills for generating and improving research questions.",
      position: 2
    },
    %{
      slug: "new-question-candidates",
      name: "New Question Candidates",
      description: "Candidate questions awaiting evidence, review, and refinement.",
      position: 3
    },
    %{
      slug: "bixbench-capsule-lab",
      name: "BixBench Capsule Lab",
      description: "Benchmark capsules and reference corpora, including the BBH training corpus.",
      position: 4
    },
    %{
      slug: "skill-training-lab",
      name: "Skill Training Lab",
      description: "Receipt-backed skill training, evaluation, and measured improvement.",
      position: 5
    }
  ]

  def all, do: @trees
end
