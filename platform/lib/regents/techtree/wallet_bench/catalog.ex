defmodule Regents.Techtree.WalletBench.Catalog do
  @moduledoc """
  What the bench tests, as techtree.sh's catalog lists it: the harnesses and
  wallets it knows, the tests and each test's time limit. Only the tables the
  pages read are here; the prompts, review guides, wallet notes and recipe pack
  stay on techtree.sh with the bench that runs them.

  Eight wallets are listed with a fixed result and never run (founder
  decisions 2 b and 4 b, 6 October 2026): six need a person to sign in, one
  cannot run on a server and one makes no keys. Cline takes the install tests
  only, because it cannot continue a conversation from a script (5 a).
  """

  @install_tests [:T1a, :T1b]

  @harnesses Map.new(
               [
                 %{id: "H01", name: "Muse Code", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H02", name: "Grok Build", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H04", name: "Hermes Agent", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H05", name: "Claude Code", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H06", name: "Cline", tests: @install_tests},
                 %{id: "H07", name: "Kilo Code", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H08", name: "Pi", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H09", name: "oh-my-pi", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H10", name: "Codex CLI", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H12", name: "DeepSeek Harness", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H13", name: "OpenCode", tests: [:T1a, :T1b, :T2, :T2_signature]},
                 %{id: "H16", name: "Prime Agent", tests: [:T1a, :T1b, :T2, :T2_signature]}
               ],
               &{&1.id, &1}
             )

  @wallets Map.new(
             [
               %{
                 id: "W01",
                 name: "Bankr",
                 executable: "bankr",
                 survey_version: "0.3.43",
                 fixed: nil
               },
               %{
                 id: "W02",
                 name: "MetaMask Agent Wallet",
                 executable: "mm",
                 survey_version: "7.0.0",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason: "Signing in needs a person in a browser, or MetaMask Mobile."
                 }
               },
               %{
                 id: "W03",
                 name: "MoonPay",
                 executable: "mp",
                 survey_version: "1.96.5",
                 fixed: nil
               },
               %{
                 id: "W05",
                 name: "Coinbase Agentic Wallet",
                 executable: "awal",
                 survey_version: "2.12.1",
                 fixed: %{outcome: "NOT_RUN", reason: "It cannot run on a server."}
               },
               %{
                 id: "W06",
                 name: "Phantom",
                 executable: "phantom",
                 survey_version: "2.0.1",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason:
                     "Signing in needs a person in a browser, with Google, Apple or the extension."
                 }
               },
               %{
                 id: "W07",
                 name: "Foundry Cast",
                 executable: "cast",
                 survey_version: "1.8.3",
                 fixed: nil
               },
               %{
                 id: "W09",
                 name: "Circle",
                 executable: "circle",
                 survey_version: "1.1.4",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason:
                     "Signing in needs a person to accept Circle's Terms and give an emailed code."
                 }
               },
               %{
                 id: "W10",
                 name: "Safe",
                 executable: "safe-cli",
                 survey_version: "1.9.0",
                 fixed: %{outcome: "NOT_RUN", reason: "It makes no keys of its own."}
               },
               %{
                 id: "W13",
                 name: "Zerion",
                 executable: "zerion",
                 survey_version: "1.9.1",
                 fixed: nil
               },
               %{
                 id: "W14",
                 name: "Splits",
                 executable: "splits",
                 survey_version: "0.2.12",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason: "It needs a person's passkey account and an API key made in a browser."
                 }
               },
               %{
                 id: "W15",
                 name: "Privy",
                 executable: "paw",
                 survey_version: "0.3.6",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason: "Signing in needs a person to approve a device code in a browser."
                 }
               },
               %{
                 id: "W17",
                 name: "Turnkey",
                 executable: "turnkey",
                 survey_version: "1.1.5",
                 fixed: %{
                   outcome: "WAITING_HUMAN",
                   reason: "It needs a person's Turnkey organisation and a registered API key."
                 }
               }
             ],
             &{&1.id, Map.put(&1, :help, ["--help"])}
           )

  @tests [:T1a, :T1b, :T2, :T2_signature, :T3, :T4, :T5, :return]

  # The survey's watchdogs, in seconds.
  @wall_caps %{
    T1a: 1800,
    T1b: 1800,
    T2: 1800,
    T2_signature: 900,
    T3: 1800,
    T4: 1800,
    T5: 1800,
    return: 900
  }

  @type harness :: %{id: String.t(), name: String.t(), tests: [atom()]}
  @type wallet :: %{
          id: String.t(),
          name: String.t(),
          executable: String.t(),
          help: [String.t()],
          survey_version: String.t(),
          fixed: nil | %{outcome: String.t(), reason: String.t()}
        }

  @doc "The harness ids the bench can build."
  @spec harness_ids() :: [String.t()]
  def harness_ids, do: Map.keys(@harnesses)

  @doc "Every wallet id the bench lists, including those with a fixed result."
  @spec wallet_ids() :: [String.t()]
  def wallet_ids, do: Map.keys(@wallets)

  @doc "The tests, in the order they can run."
  @spec tests() :: [atom()]
  def tests, do: @tests

  @doc "The tests a harness takes before any money moves, in the order they can run."
  @spec tests(String.t()) :: [atom()]
  def tests(harness_id), do: harness!(harness_id).tests

  @spec harness!(String.t()) :: harness()
  def harness!(id), do: Map.fetch!(@harnesses, id)

  @spec wallet!(String.t()) :: wallet()
  def wallet!(id), do: Map.fetch!(@wallets, id)

  @doc "A test's folder on the machine and its name on pages."
  @spec turn_name(atom()) :: String.t()
  def turn_name(:T2_signature), do: "T2-signature"
  def turn_name(:return), do: "return"
  def turn_name(test) when test in @tests, do: Atom.to_string(test)

  @spec wall_cap(atom()) :: pos_integer()
  def wall_cap(test), do: Map.fetch!(@wall_caps, test)
end
