defmodule Regents.BrowserAgents do
  @moduledoc """
  The agents the browser walk's person has paired. playwright.config.ts runs
  `pair!/0` before the server serves pages: four agents, paired the way an agent
  pairs, so the account menu's three leave out Spare Agent, paired first
  (account_menu.spec.ts). The walk's "other-account" person has one, Leaving
  Agent, which confirm.spec.ts unpairs. The walk's database outlives a run, so an
  agent already paired is left as it is.
  """

  alias RegentAgents.{Agent, Person}

  # The people `TestPrivyVerifier` signs in for the walk's "valid" and
  # "other-account" sign-ins, and the agents each has paired.
  @people [
    {%Person{privy_user_id: "did:privy:verified"},
     [
       {"Spare Agent", "f"},
       {"Walk Agent", "c"},
       {"Desktop Agent", "d"},
       {"Phone Agent", "e"}
     ]},
    {%Person{privy_user_id: "did:privy:other"}, [{"Leaving Agent", "a"}]}
  ]

  def pair! do
    Enum.each(@people, fn {person, agents} -> pair!(person, agents) end)
  end

  defp pair!(person, agents) do
    {:ok, paired} = RegentAgents.list_my_agents(actor: person)
    names = MapSet.new(paired, & &1.name)

    for {name, digit} <- agents, name not in names do
      code = RegentAgents.issue_pairing_code!(actor: person)

      RegentAgents.pair_agent!(code.code, name, :hermes,
        actor: %Agent{wallet: "0x" <> String.duplicate(digit, 40)}
      )
    end
  end
end
