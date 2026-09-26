defmodule AshPlatform.Agents.Harness do
  @moduledoc "The agent runtimes a person can pair with their account."

  use Ash.Type.Enum,
    values: [
      hermes: [label: "Hermes"],
      grok_bot: [label: "Grok bot"],
      muse: [label: "Muse"],
      openclaw: [label: "OpenClaw"],
      nemoclaw: [label: "NemoClaw"],
      ironclaw: [label: "IronClaw"],
      pi: [label: "Pi"]
    ]
end
