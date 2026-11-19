# Fails unless every shared library this site uses comes from where it must and
# every required security fix is present.
#
# This is ash-template's platform/scripts/check_required_fixes.exs for this
# repository's layout. The twelve elixir-utils packages in `copied` are this
# repository's own folders under shared/, each at the folder it has in elixir-utils
# (regent_identity at shared/ash_components/identity): each folder must exist and
# platform/mix.exs must name it as a path dependency. shared/SOURCE.json records the
# library repository and commit the copies come from, and that repository must be
# the one the registry names for each of them. Every other library the registry lists
# (siwa, regent_chain, regent_ui, ash_postgres) must be a git dependency on exactly
# its repository URL and folder, pinned with `ref:` to a full commit whose history is
# fetched, and libraries from one repository share one commit. Any other local
# folder, and any unlisted library from a shared repository, fails.
#
# A "hex" fix sets the Hex versions a package may be locked at, as an Elixir version
# requirement (">= 3.34.3"). A "git" fix must be in the pinned history of each listed
# app that is a git pin, and, when it names a copied package, in the history of
# shared/SOURCE.json's commit, as GitHub's compare answers it. Dependencies of every
# environment are checked, not only the one the check runs in.
#
# Reads the required-fixes registry (ash-template's security/required-fixes.json) on
# standard input. The first argument names the registry revision for the report; the
# second is the source file, shared/SOURCE.json. Run from the platform folder after
# `mix deps.get` (the Makefile's check-required-fixes fetches the registry from
# ash-template's main branch); needs `gh auth login`:
#
#     elixir ../scripts/check-required-fixes.exs REVISION ../shared/SOURCE.json < required-fixes.json

copied =
  ~w(ens_elixir regent_privy regent_identity regent_payments regent_agents regent_blog
     regent_agent_access regent_format regent_points regent_http regent_sprites credo_ash)

[revision, source_file] = System.argv()
Mix.start()
Mix.Hex.start()
Code.compile_file("mix.exs")

%{"managed" => managed, "fixes" => fixes} = JSON.decode!(IO.read(:stdio, :eof))
managed = Map.new(managed, &{&1["app"], &1})

{:ok, quoted} = Code.string_to_quoted(File.read!("mix.lock"), emit_warnings: false)
{lock, _binding} = Code.eval_quoted(quoted)
lock = Map.new(lock, fn {app, entry} -> {Atom.to_string(app), entry} end)

deps = Map.new(Mix.Dep.Converger.converge(env: nil), &{Atom.to_string(&1.app), &1})
shared = Path.expand("../shared")

same_repository = fn url ->
  url
  |> String.downcase()
  |> String.replace(
    ~r{^(git@github\.com:|ssh://git@github\.com/|git://github\.com/|http://github\.com/)},
    "https://github.com/"
  )
  |> String.trim_trailing("/")
  |> String.trim_trailing(".git")
end

source =
  with {:ok, text} <- File.read(source_file),
       {:ok, %{"repository" => "https://github.com/" <> _ = repository, "commit" => commit}}
       when is_binary(commit) <- JSON.decode(text),
       true <- commit =~ ~r/\A[0-9a-f]{40}\z/ do
    %{repository: repository, commit: commit}
  else
    _unreadable -> nil
  end

shared_repositories = managed |> Map.values() |> MapSet.new(&same_repository.(&1["repository"]))

folder = fn app -> Path.relative_to_cwd(deps[app].opts[:dest]) end
git = fn app, args -> System.cmd("git", ["-C", folder.(app) | args], stderr_to_stdout: true) end

copy = fn app ->
  case managed[app] do
    nil ->
      ["#{app} is copied into shared/ but ash-template's registry no longer lists it"]

    %{"sparse" => sparse} ->
      dep = deps[app]

      cond do
        not File.dir?(Path.join(shared, sparse)) ->
          ["#{app}'s folder shared/#{sparse} is missing"]

        dep == nil ->
          ["platform/mix.exs does not name #{app}; it must be a path dependency on shared/#{sparse}"]

        dep.scm != Mix.SCM.Path ->
          ["#{app} must load from this repository's shared/#{sparse}, not #{inspect(dep.scm)}"]

        Path.expand(dep.opts[:dest]) != Path.join(shared, sparse) ->
          ["#{app} loads from #{folder.(app)}; it must be this repository's shared/#{sparse}"]

        true ->
          []
      end
  end
end

pinned_git = fn app, commit, opts, sparse ->
  cond do
    opts[:sparse] != sparse ->
      ["#{app} uses the folder #{inspect(opts[:sparse])}; it must be #{inspect(sparse)}"]

    opts[:ref] != commit or not (commit =~ ~r/\A[0-9a-f]{40}\z/) ->
      ["#{app} must be pinned with ref: set to a full commit, not a branch or tag"]

    git.(app, ["rev-parse", "HEAD"]) != {commit <> "\n", 0} ->
      [
        "#{app}'s checkout is not at its locked commit #{String.slice(commit, 0, 7)}; run mix deps.get"
      ]

    git.(app, ["rev-parse", "--is-shallow-repository"]) != {"false\n", 0} ->
      [
        "#{app}'s commit history is missing (shallow checkout); remove depth:, then run mix deps.clean #{app} and mix deps.get"
      ]

    true ->
      []
  end
end

pin = fn
  app, %{scm: Mix.SCM.Git, opts: opts} ->
    %{"repository" => repository, "sparse" => sparse} = managed[app]

    case {opts[:git], lock[app]} do
      {^repository, {:git, ^repository, commit, locked}} ->
        if Keyword.take(locked, [:ref, :sparse]) == Keyword.take(opts, [:ref, :sparse]),
          do: pinned_git.(app, commit, opts, sparse),
          else: ["#{app}'s mix.lock entry does not match mix.exs; run mix deps.get"]

      {^repository, _entry} ->
        ["#{app}'s mix.lock entry does not match mix.exs; run mix deps.get"]

      {url, _entry} ->
        if same_repository.(url) == same_repository.(repository),
          do: ["#{app} names its repository as #{url}; write exactly #{repository}"],
          else: ["#{app} comes from #{url}, not #{repository}"]
    end

  app, %{scm: Mix.SCM.Path} ->
    [
      "#{app} loads from a local folder (#{folder.(app)}); it must come from a pinned git commit"
    ]

  app, %{scm: scm} ->
    ["#{app} comes from #{inspect(scm)}, not its shared repository"]
end

stray = fn
  app, %{scm: Mix.SCM.Path} ->
    [
      "#{app} loads from a local folder (#{folder.(app)}); use a Hex package or a pinned git commit"
    ]

  app, %{scm: Mix.SCM.Git, opts: opts} ->
    if MapSet.member?(shared_repositories, same_repository.(opts[:git])),
      do: ["#{app} comes from shared repository #{opts[:git]} but is not listed in the registry"],
      else: []

  _app, _dep ->
    []
end

copy_problems = Map.new(copied, &{&1, copy.(&1)})

provenance_problems =
  for {app, dep} <- deps, app not in copied, into: copy_problems do
    {app, if(Map.has_key?(managed, app), do: pin.(app, dep), else: stray.(app, dep))}
  end

loaded_from_shared = for {app, []} <- copy_problems, do: app

inspectable =
  for {app, []} <- provenance_problems,
      Map.has_key?(managed, app),
      app not in copied,
      into: MapSet.new(),
      do: app

mixed_commit_problems =
  for {repository, apps} <-
        inspectable |> Enum.filter(&lock[&1]) |> Enum.group_by(&managed[&1]["repository"]),
      commits = Enum.map(apps, &"#{&1} #{String.slice(elem(lock[&1], 2), 0, 7)}"),
      apps |> Enum.map(&elem(lock[&1], 2)) |> Enum.uniq() |> length() > 1,
      do:
        "#{repository} is pinned at more than one commit (#{Enum.join(commits, ", ")}); pin all its libraries to one commit"

source_problems =
  case source do
    nil ->
      [
        ~s(#{source_file} must hold {"repository": "https://github.com/<owner>/<name>.git", "commit": "<40-character commit>"})
      ]

    %{repository: repository} ->
      for app <- copied,
          %{"repository" => library} <- [managed[app]],
          same_repository.(library) != same_repository.(repository) do
        {library, app}
      end
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {library, apps} ->
        "#{source_file} says shared/ is copied from #{repository}, but the registry names #{library} for #{Enum.join(apps, ", ")}"
      end)
  end

# A fix naming copied packages must be in the history of the commit shared/ is copied
# from: GitHub answers "ahead" or "identical" when the fix is that commit's ancestor.
in_source = fn %{"id" => id, "commit" => fix, "summary" => summary}, apps ->
  "https://github.com/" <> slug = same_repository.(source.repository)
  names = Enum.join(apps, ", ")
  from = String.slice(source.commit, 0, 7)
  compare = "repos/#{slug}/compare/#{fix}...#{source.commit}"

  case System.cmd("gh", ["api", compare, "--jq", ".status"], stderr_to_stdout: true) do
    {status, 0} when status in ["ahead\n", "identical\n"] ->
      []

    {status, 0} ->
      [
        "shared/ (#{names}) is copied from #{from}, which does not contain #{id} (GitHub: #{String.trim(status)}): #{summary}"
      ]

    # gh prints the error body, then its own short reason after "gh: ".
    {output, _failed} ->
      reason = output |> String.split("gh: ") |> List.last() |> String.trim()

      [
        "GitHub could not say whether #{id}'s commit #{fix} is in #{from}, the commit shared/ is copied from: #{reason}"
      ]
  end
end

fix_problems =
  Enum.flat_map(fixes, fn
    %{"kind" => "git", "commit" => fix, "apps" => apps} = entry ->
      pinned =
        for app <- apps,
            MapSet.member?(inspectable, app),
            elem(git.(app, ["merge-base", "--is-ancestor", fix, "HEAD"]), 1) != 0,
            do: "#{app} is pinned without #{entry["id"]}: #{entry["summary"]}"

      # An unreadable or mismatched source file already fails the gate on its own line.
      in_copy =
        case Enum.filter(apps, &(&1 in copied)) do
          [] -> []
          _named when source_problems != [] -> []
          named -> in_source.(entry, named)
        end

      pinned ++ in_copy

    %{"kind" => "hex", "package" => package, "requirement" => requirement} = entry ->
      case {deps[package], lock[package]} do
        {nil, _entry} ->
          []

        {_dep, {:hex, _name, version, _hash, _managers, _deps, _repo, _outer}} ->
          if not Version.match?(version, requirement),
            do: [
              "#{package} #{version} is outside #{requirement} (#{entry["id"]}): #{entry["summary"]}"
            ],
            else: []

        {_dep, _entry} ->
          ["#{package} is not locked as a Hex package, so #{entry["id"]} cannot be checked"]
      end
  end)

problems =
  Enum.flat_map(provenance_problems, &elem(&1, 1)) ++
    source_problems ++ mixed_commit_problems ++ fix_problems

case problems do
  [] ->
    IO.puts("""
    Required fixes #{revision}:
      loaded from shared/, copied from #{source.repository} #{String.slice(source.commit, 0, 7)}: #{loaded_from_shared |> Enum.sort() |> Enum.join(", ")}
      pinned and inspectable: #{inspectable |> Enum.sort() |> Enum.join(", ")}
      every required Hex fix is locked, and every required git fix is in its pinned history or in the commit shared/ is copied from\
    """)

  problems ->
    IO.puts(:stderr, "Required fixes #{revision}:")
    Enum.each(problems, &IO.puts(:stderr, "  " <> &1))
    System.halt(1)
end
