defmodule RegentAgents.PairingMessage do
  @moduledoc """
  What a person pastes to their agent to pair it: that the account is their
  Regents Labs account and which site they pair it on, the pairing code, where
  the pairing steps are and how long the code lasts. ChatGPT and Claude, the
  hosted runtimes, are told to pair through the site's hosted connection
  instead. Every other agent is told to keep its own key, in a folder named after its runtime under
  `~/.siwa-agent`, so agents sharing one computer pair as separate agents; an
  agent on an unlisted runtime, or on none named, names the folder itself. Grok
  Bot keeps its key in `/workspace/.siwa-agent`, the one folder its computer
  keeps after a restart, as its agent guide says.
  Codex, Grok Bot, Hermes and Muse each get one more line for the mistake that
  agent most often makes on its first pairing. Muse runs where siwa.regents.sh
  may not answer, so its line names the SIWA service's other address.

  A site may add its own lines for that agent (`setup`), such as how it checks
  in. A pairing link that names the page the agent should begin on (`start`, a
  path on the same site) ends the message by sending it there once it is paired.
  """

  @doc """
  The message for `code`, made on the site at `origin` (its address with no
  trailing slash), for an agent on `harness`. Options:

    * `:setup` - the site's own lines for this agent, after the pairing lines
    * `:start` - the page the agent begins on once paired, always the last line
  """
  @spec text(String.t(), String.t(), RegentAgents.Harness.t() | nil,
          setup: String.t() | nil,
          start: String.t() | nil
        ) :: String.t()
  def text(code, origin, harness, opts \\ []) do
    [pairing(code, origin, harness), opts[:setup], start_line(origin, opts[:start])]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp pairing(code, origin, :chatgpt), do: hosted(code, origin, "ChatGPT", "plugin", :chatgpt)
  defp pairing(code, origin, :claude), do: hosted(code, origin, "Claude", "connector", :claude)

  defp pairing(code, origin, harness) do
    """
    Pair with my Regents Labs account on #{URI.parse(origin).host}
    Pairing code: #{code}
    Follow the "Pair with a person's account" steps at #{origin}/llms.txt
    The code works once, for ten minutes. If it fails, ask me for a new one.
    If other agents share your computer, use your own key: begin every shell with export SIWA_AGENT_HOME=#{key_home(harness)}\
    """ <> first_pairing(harness)
  end

  # The runtime's own folder; an agent on any other runtime, or on none the site
  # named, picks its own name. Only /workspace survives a Grok Bot restart.
  defp key_home(:grok_bot), do: "/workspace/.siwa-agent"
  defp key_home(harness) when harness in [nil, :other], do: "~/.siwa-agent/YOUR-RUNTIME"

  defp key_home(harness),
    do: "~/.siwa-agent/" <> (harness |> Atom.to_string() |> String.replace("_", "-"))

  defp hosted(code, origin, app, door, harness) do
    """
    Connect #{app} to my existing Regents Labs account on #{URI.parse(origin).host} using this site's #{door}.
    Use register_identity, then get_identity. Reuse this connection across chats.
    If pairing is needed, I approve pair_identity with this one-use code, the name #{app} and the harness #{harness}.
    Pairing code: #{code}
    My Agents page is #{origin}/account/agents#account-pairing. Never repeat this code in your reply.
    If the #{door}'s identity tools are unavailable, report that setup is needed.\
    """
  end

  defp start_line(_origin, nil), do: nil
  defp start_line(origin, start), do: "Once paired, start at #{origin}#{start}"

  defp first_pairing(:codex),
    do:
      "\nIf your sandbox blocks the network, ask me to allow it for this step. " <>
        "Keep pair.json in your home folder, never in this project."

  defp first_pairing(:grok_bot),
    do:
      "\nNever put this code in a public reply or post. " <>
        "Pair from your own tools, then tell me it worked."

  defp first_pairing(:hermes),
    do: "\nKeep the key you pair with and use it in every chat. Never make a second one."

  defp first_pairing(:muse),
    do:
      "\nIf siwa.regents.sh doesn't answer from your host, set " <>
        "SIWA_BROKER=https://siwa-server.fly.dev and try again."

  defp first_pairing(_harness), do: ""
end
