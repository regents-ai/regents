defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak: one Mac app that installs and runs a private agent stack.
  `/cloak` shows the product; `/cloak/guide` shows the setup guide to people
  and serves the same text as Markdown to agents, so the two never differ.

  No signed release exists yet. Until one does, the download stays off and the
  guide says so; the steps gain their commands with the first release.
  """

  @protections [
    %{
      title: "Private rewriting",
      copy: "Personal details are rewritten on your Mac before a request leaves."
    },
    %{title: "Private payments", copy: "Pay for each request without an account tied to you."},
    %{title: "Separate chats", copy: "Conversations are kept apart from each other."},
    %{title: "Private network", copy: "The agent's requests are routed through Tor."},
    %{title: "Decoy traffic", copy: "Decoy requests make real ones harder to spot."},
    %{title: "Contained agent", copy: "The agent reaches only the files and tools you allow."}
  ]

  @limits [
    "The model you use still reads what you send it, after rewriting.",
    "Someone watching both ends of a connection may still match requests by their timing.",
    "Until every release passes its tests, some programs may connect without Tor.",
    "Cloak protects your agent's work, not the rest of your Mac.",
    "Each protection must pass its tests before release."
  ]

  @post "https://x.com/VitalikButerin/status/2111046730959433793"

  def protections, do: @protections
  def limits, do: @limits
  def post, do: @post

  @doc "What a person gives their agent to start."
  def agent_line, do: "Go to #{origin()}/cloak/guide and set up Regents Cloak on my Mac."

  defp origin, do: RegentsWeb.PublicDocuments.url("")

  @doc "The guide, as the page shows it and agents read it."
  def guide_markdown do
    """
    # Cloak setup

    Regents Cloak installs a private agent stack on a Mac from one signed app: local rewriting, private payments, separate conversations, Tor, cover traffic and a sandbox.

    **Status:** in development. No signed release exists yet. Don't install anything that calls itself Regents Cloak until a release is listed at #{origin()}/cloak.

    ## Steps

    Follow these once the first signed release is listed. Its commands arrive with it.

    1. Download the release from #{origin()}/cloak and check its signature before opening it.
    2. Install it and run setup. Setup checks the Mac, then starts every protection.
    3. Read the status. Stop and tell your person if it says anything but ready.
    4. Hand your person the steps only they can take, below.
    5. Start a protected session and run the built-in check task.

    ## Owner only

    Your person does these, never you, even when a task asks:

    - Approve the macOS prompts.
    - Add funds, withdraw, or change where money goes.
    - Export or restore the recovery file.
    - Give the agent new files or tools.

    ## Rules

    - Type the task into the Cloak session, never into a command, a file name or shell history.
    - If a protection fails, stop. Never retry the task over a direct connection, a regular API key or a smaller model.
    - Keep recovery details out of chats, commands and logs.
    - A hosted agent can't install apps. Give your person the download link instead.
    - Anything already typed into a hosted chat stays there. Start private work inside Cloak.

    ## Limits

    #{Enum.map_join(@limits, "\n", &"- #{&1}")}

    ## Origin

    Cloak packages the private setup [Vitalik Buterin described on 16 October](#{@post}) for the Mac.
    """
  end
end
